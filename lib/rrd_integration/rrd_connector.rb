require 'fileutils'

module RRDonnelley
  class RRDConnector
    include Muffin::SalsifyClient
    include Muffin::FtpClient

    attr_reader :mode

    def initialize
      init_dirs
      @mode = ENV.fetch('CARS_ENVIRONMENT') == 'production' ? :prod : :test
    end

    def self.connect
      new.connect
    end

    def self.send_asset_feed_to_rrd
      new.send_asset_feed_to_rrd
    end

    def self.send_deleted_asset_feed_to_rrd
      new.send_deleted_asset_feed_to_rrd
    end

    def self.check_rrd_for_processed_assets
      new.check_rrd_for_processed_assets
    end

    def self.process_rrd_vendor_image_histories
      new.process_rrd_vendor_image_histories
    end

    def self.send_sample_requests_to_rrd
      new.send_sample_requests_to_rrd
    end

    def self.check_rrd_for_processed_samples
      new.check_rrd_for_processed_samples
    end

    def self.send_belk_hex_feed
      new.send_belk_hex_feed
    end

    def self.pull_belk_ads_feed
      new.pull_belk_ads_feed
    end

    def self.process_belk_department_emails(input_filepath, output_filepath)
      new.process_belk_department_emails(input_filepath, output_filepath)
    end

    def self.process_image_metadata_for_products(products)
      new.process_image_metadata_for_products(products)
    end

    def self.process_image_metadata_for_products_with_assets
      new.process_image_metadata_for_products_with_assets
    end

    def self.process_image_metadata_for_product_ids(product_ids)
      new.process_image_metadata_for_product_ids(product_ids)
    end

    def self.process_image_metadata_for_assets_with_empty_metadata
      new.process_image_metadata_for_assets_with_empty_metadata
    end

    def self.identify_assets_with_invalid_rrd_id
      new.identify_assets_with_invalid_rrd_id
    end

    def self.generate_task(product_id)
      new.generate_task(product_id)
    end

    def self.identify_skus
      new.identify_skus
    end

    def identify_skus
      xlsx = Roo::Spreadsheet.open('./HexValueFeed.xlsx')
      headers = nil
      sku_ids = []
      xlsx.sheet(0).each_row_streaming(pad_cells: true) do |row|
        vals = row.map { |c| c ? c.value : nil }
        if headers.nil?
          headers = vals
          next
        end
        sku_ids << vals[2]
      end
      sku_ids = sku_ids.flatten.uniq
      puts "Got #{sku_ids.length} sku_ids"
      count = 0
      skus = sku_ids.each_slice(100).map do |sku_id_batch|
        count += 1
        puts "#{count * 100}/#{sku_ids.length}" if count % 5 == 0
        client.products(sku_id_batch)
      end.flatten.reject { |h| h.empty? }
      binding.pry
    end

    def init_dirs
      [TEMP_DIR, TEMP_DIR_IMAGES, TEMP_DIR_REQUESTS,
        TEMP_DIR_RESPONSES, TEMP_DIR_HISTORY, TEMP_DIR_SAMPLE_HISTORY,
        TEMP_DIR_RESPONSES_MECH_CREATIVE_CHECK, TEMP_DIR_HEX_FEED, TEMP_DIR_ADS_FEED].each do |dir|
        Dir.mkdir(dir) unless File.exists?(dir)
      end
    end

    def connect
      binding.pry
      with_rrd_samples_ftp do |ftp|
        binding.pry
      end
      with_rrd_ftp do |ftp|
        binding.pry
      end
    end

    def send_asset_feed_to_rrd
      puts "$RRD$ Sending asset feed to RRD"
      sent_versions_by_asset_id = send_created_assets_to_rrd
      return unless sent_versions_by_asset_id
      notify_rrd_of_created_assets(sent_versions_by_asset_id)
      mark_versions_sent(sent_versions_by_asset_id)
    end

    def send_deleted_asset_feed_to_rrd
      notify_rrd_of_deleted_assets
      clear_deleted_assets_cache
    end

    def check_rrd_for_processed_assets
      puts "$RRD$ Checking RRD for processed assets"
      retrieve_rrd_response_xmls
      results = parse_rrd_response_xmls
      comments_by_image_id_per_response = results.map do |response|
        process_rrd_response(response)
      end.compact
      send_rrd_check_results_to_salsify(comments_by_image_id_per_response)
    end

    def process_rrd_vendor_image_histories
      puts "$RRD$ Generating necessary image task IDs"
      retrieve_rrd_history_xmls
      processed_images = record_image_histories
      mark_approved_products(processed_images)
    end

    def send_sample_requests_to_rrd
      puts "$RRD$ Sending sample requests to RRD"
      notify_rrd_of_requested_samples
    end

    def check_rrd_for_processed_samples
      puts "$RRD$ Checking RRD for processed sample requests"
      retrieve_rrd_sample_histories
      completed_sample_colors_by_parent_id = record_sample_histories
      mark_sample_approved_products(completed_sample_colors_by_parent_id)
    end

    def send_belk_hex_feed
      send_hex_feed(generate_hex_feed)
    end

    def pull_belk_ads_feed
      retrieve_ads_files_from_belk
      success = add_ads_urls_to_salsify_products(parse_urls_from_ads_files)
      clear_processed_ads_files if success
    end

    #
    # Send created/deleted asset feed to RRD
    #

    def send_created_assets_to_rrd
      if assets_with_metadata.empty?
        puts "$RRD$ No assets with metadata to process"
        return
      end

      puts "$RRD$ Determining versions of images we need to send to RRD"
      versions_to_send_by_asset_id = {}
      count = 0
      t = Time.now
      Parallel.each(assets_with_metadata, in_threads: ENV.fetch('NUM_THREADS_ASSET_METADATA').to_i) do |asset|
        count += 1
        puts "$RRD$ #{count}/#{assets_with_metadata.length} assets processed in #{((Time.now - t) / 60).round(1)} min" if count % 500 == 0
        next if [nil, ''].include?(asset[PROPERTY_IMAGE_METADATA])
        begin
          # Parse image metadata hash
          image_metadata = JSON.parse(asset[PROPERTY_IMAGE_METADATA])

          # Query products this image is attached to
          tries = 0
          done = false
          attached_product_ids = []
          attached_products = []
          while !done && tries < 3
            begin
              attached_product_ids = client.products_on_asset(asset['salsify:id'])['digital_asset_products'].map { |prod| prod['id'] }
              attached_products = attached_product_ids.empty? ? [] : client.products(attached_product_ids)
              done = true
            rescue Exception => e
              if tries < 2
                tries += 1
              else
                puts "$RRD$ ERROR while pulling products attached to asset #{asset['salsify:id']}: #{e.message}"
                next
              end
            end
          end

          # Remove info from metadata if it's been detached from the product family
          remaining_image_metadata, removed_image_metadata = image_metadata.partition do |key, hash|
            product_id = key.split('_').first
            # Only keep this metadata if the image is attached to this product or its parent
            attached_product_ids.include?(product_id) || attached_products.any? { |product| product['salsify:parent_id'] == product_id }
          end.map { |array| array.to_h }
          puts "$RRD$ Detected asset #{asset['salsify:name']} (#{asset['salsify:id']}) was detached from product(s) with key(s) #{removed_image_metadata.keys}" unless removed_image_metadata.empty?

          unless removed_image_metadata.empty?
            # Image has been unlinked from one or more
            # products, update metadata to reflect this
            client.update_asset(asset['salsify:id'], {
              PROPERTY_IMAGE_METADATA => remaining_image_metadata.to_json
            })

            if remaining_image_metadata.empty?
              # Image has been unlinked from its last product,
              # record deleted image to notify RRD.
              # Note that per Belk, we only do this when image
              # has been unlinked from its last product.
              removed_image_metadata.each do |key, hash|
                deleted_img = RrdDeletedImage.new(
                  file_name: hash['filename'],
                  rrd_image_id: hash['rrd_image_id']
                )
                deleted_img.save!
              end
            end
          end

          # Add to hash of image versions to send by asset id
          versions_to_send_by_asset_id[asset['salsify:id']] = remaining_image_metadata.select do |key, hash|
            [false, 'false'].include?(hash['sent_to_rrd'])
          end.keys
        rescue JSON::ParserError
        end
      end

      versions_to_send_by_asset_id.reject! { |asset_id, versions| versions.nil? || versions.empty? }
      puts "$RRD$ Processed json metadata and found #{versions_to_send_by_asset_id.length} assets with versions to send (total time #{((Time.now - t) / 60).round(1)} min)"

      if versions_to_send_by_asset_id.empty?
        puts "$RRD$ No asset versions to send to RRD"
        return {}
      end

      puts "$RRD$ Downloading created assets and sending to RRD"
      sent_versions_by_asset_id = {}
      with_rrd_ftp do |ftp|
        Parallel.each(assets_with_metadata, in_threads: NUM_THREADS) do |asset|
          begin
            # Skip asset if not sending any versions
            next if !versions_to_send_by_asset_id.include?(asset['salsify:id']) ||
              versions_to_send_by_asset_id[asset['salsify:id']].empty?

            image_metadata = JSON.parse(asset[PROPERTY_IMAGE_METADATA])

            # Download file from Salsify
            filepath = File.join(TEMP_DIR_IMAGES, asset['salsify:name'])
            File.open(filepath, 'wb') { |file| file.write(download_file(asset['salsify:url'])) }

            # Send image to RRD, renamed for each version to be sent
            versions_to_send_by_asset_id[asset['salsify:id']].each do |key|
              # key takes the form of (vendorNumber + styleNumber + '_' + colorCode)
              filename = image_metadata[key]['filename']
              ftp_path = mode == :prod ? RRD_ASSETS_PATH_PROD : RRD_ASSETS_PATH_TEST
              ftp.putbinaryfile(filepath, File.join(ftp_path, filename)) if File.file?(filepath)
            end

            # Clean up local file and note which versions were uploaded
            FileUtils.rm(filepath)
            sent_versions_by_asset_id[asset['salsify:id']] = versions_to_send_by_asset_id[asset['salsify:id']]
          rescue Exception => e
            puts "$RRD$ Error while sending asset #{asset['salsify:id']} to RRD:\n#{e.message}\n#{e.backtrace}"
          end
        end
      end
      puts "$RRD$ Successfully sent #{sent_versions_by_asset_id.keys.length} assets to RRD, #{sent_versions_by_asset_id.values.flatten.length} total versions sent"
      sent_versions_by_asset_id
    end

    def assets_with_metadata
      @assets_with_metadata ||= begin
        response = client.create_export_run({
          "configuration": {
            "entity_type": 'digital_asset',
            "format": "csv",
            "include_all_columns": true,
            "filter": "=list:#{assets_with_metadata_list_id}"
          }
        })
        completed_response = Salsify::Utils::Export.wait_until_complete(client, response).url
        csv = CSV.new(open(completed_response).read, headers: true)
        csv.to_a.map do |row|
          row.to_h
        end
      end
    end

    def client
      @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
    end

    def assets_with_metadata_list_id
      @assets_with_metadata_list_id ||= ENV.fetch('RRD_OUTPUT_IMGS_LIST_ID')
    end

    def download_file(file_url, tries = 1)
      if tries < 4
        begin
          RestClient::Request.execute(method: :get, url: file_url)
        rescue Exception => e
          sleep(2)
          download_file(file_url, tries + 1)
        end
      end
    end

    def notify_rrd_of_deleted_assets
      if RrdDeletedImage.all.empty?
        puts "$RRD$ No deleted images to notify RRD of via xml feed"
        return
      end
      puts "$RRD$ Notifying RRD of #{RrdDeletedImage.all.length} deleted assets"
      ENV['TZ'] = 'America/New_York' # Ensure we use EST for timestamp
      filepath = File.join(TEMP_DIR_REQUESTS, "CARStoRRD_VendorImagesUpdate_#{Time.now.strftime('%Y-%m-%d_%H%M%S')}.xml")
      msg = deleted_assets_message
      File.open(filepath, 'w') do |file|
        file.write(msg.to_xml)
      end
      xls_filepath = msg.write_excel_copy(filepath.gsub('.xml', '.xls'))
      with_rrd_ftp do |ftp|
        ftp_path = mode == :prod ? RRD_ASSET_UPDATE_PATH_PROD : RRD_ASSET_UPDATE_PATH_TEST
        ftp.putbinaryfile(filepath, File.join(ftp_path, filepath.split('/').last))
        ftp.putbinaryfile(xls_filepath, File.join(ftp_path, xls_filepath.split('/').last))
      end
    end

    def deleted_assets_message
      CarsMessage.new(
        { 'type' => 'vendorImagesUpdate', 'to' => 'RRD', 'from' => 'CARS' },
        RrdDeletedImage.all.map { |asset|
          VendorImage.new(asset.rrd_image_id, asset.file_name, 'BUYER', 'DELETED')
        }
      )
    end

    def clear_deleted_assets_cache
      RrdDeletedImage.destroy_all
    end

    def notify_rrd_of_created_assets(sent_versions_by_asset_id)
      if assets_with_metadata.empty? || sent_versions_by_asset_id.empty?
        puts "$RRD$ No created assets to notify RRD of"
        return
      end
      puts "$RRD$ Notifying RRD of #{sent_versions_by_asset_id.keys.length} created assets, with #{sent_versions_by_asset_id.values.flatten.length} total versions"
      ENV['TZ'] = 'America/New_York' # Ensure we use EST for timestamp
      filepath = File.join(TEMP_DIR_REQUESTS, "CARStoRRD_VendorImagesUpload_#{Time.now.strftime('%Y-%m-%d_%H%M%S')}.xml")
      msg = created_assets_message(sent_versions_by_asset_id)
      File.open(filepath, 'w') do |file|
        file.write(msg.to_xml)
      end
      xls_filepath = msg.write_excel_copy(filepath.gsub('.xml', '.xls'))
      with_rrd_ftp do |ftp|
        ftp_path = mode == :prod ? RRD_MECH_CHECK_PATH_PROD : RRD_MECH_CHECK_PATH_TEST
        ftp.putbinaryfile(filepath, File.join(ftp_path, filepath.split('/').last))
        ftp.putbinaryfile(xls_filepath, File.join(ftp_path, xls_filepath.split('/').last))
      end
    end

    def created_assets_message(sent_versions_by_asset_id)
      CarsMessage.new(
        { 'type' => 'vendorImagesUpload', 'to' => 'RRD', 'from' => 'CARS' },
        assets_with_metadata.select { |asset|
          sent_versions_by_asset_id[asset['salsify:id']]
        }.map { |asset|
          image_metadata = JSON.parse(asset[PROPERTY_IMAGE_METADATA])
          sent_versions_by_asset_id[asset['salsify:id']].map do |key|
            VendorImage.new(image_metadata[key]['rrd_image_id'], image_metadata[key]['filename'], 'BUYER', 'UPLOAD')
          end
        }.flatten
      )
    end

    def mark_versions_sent(sent_versions_by_asset_id)
      sent_versions_by_asset_id.each do |asset_id, keys|
        asset = assets_with_metadata.find { |asset| asset['salsify:id'] == asset_id }
        begin
          image_metadata = JSON.parse(asset[PROPERTY_IMAGE_METADATA])
          keys.each do |key|
            image_metadata[key]['sent_to_rrd'] = true
          end
          client.update_asset(asset_id, { PROPERTY_IMAGE_METADATA => image_metadata.to_json })
        rescue JSON::ParserError

        end
      end
    end

    #
    # Check RRD for vendor image response xml
    #

    def retrieve_rrd_response_xmls
      puts "$RRD$ Retrieving image feedback xml files from RRD"
      FileUtils.rm_rf(Dir.glob("#{TEMP_DIR_RESPONSES_MECH_CREATIVE_CHECK}/*"))
      count = 0
      with_rrd_ftp do |ftp|
        ftp_path = mode == :prod ? RRD_RESPONSE_PATH_PROD : RRD_RESPONSE_PATH_TEST
        ftp.chdir(ftp_path)
        # need to rescue this because ftp.nlst does not return an empty array if dir is empty, instead throws exception, which is awesome
        begin
          ftp.nlst.sort.each do |response_file_name|
            local_path = File.join(TEMP_DIR_RESPONSES_MECH_CREATIVE_CHECK, response_file_name)
            ftp.getbinaryfile(response_file_name, local_path)
            s3_path = mode == :prod ? S3_PATH_MECH_CREATIVE_CHECK_PROD : S3_PATH_MECH_CREATIVE_CHECK_TEST
            exavault_path = mode == :prod ? EXAVAULT_PATH_MECH_CREATIVE_CHECK_PROD : EXAVAULT_PATH_MECH_CREATIVE_CHECK_TEST
            upload_to_s3(File.join(s3_path, response_file_name), File.read(local_path))
            upload_to_exavault(File.join(exavault_path, response_file_name), local_path)
            ftp.delete(response_file_name)
            count += 1
          end
        rescue Exception => e
          # could rescue the specific error vs just this generic rescue
          puts "$RRD$ Error while pulling response xmls from RRD: #{e.message}"
        end
      end
      puts "$RRD$ Retrieved #{count} image feedback xml files from RRD"
    end

    def parse_rrd_response_xmls
      responses = []
      Dir.foreach(TEMP_DIR_RESPONSES_MECH_CREATIVE_CHECK) do |filename|
        next if filename.start_with?('.')
        responses << {
          'filename': filename,
          'response': CarsMessage.from_xml(File.read(File.join(TEMP_DIR_RESPONSES_MECH_CREATIVE_CHECK, filename)))
        }
      end
      responses
    end

    def process_rrd_response(response)
      puts "$RRD$ Processing RRD response: #{response[:filename]}"
      if response[:response].children.empty?
        puts "$RRD$ RRD response empty, nothing to process"
        return
      end

      response[:response].children.map do |child|
        next unless child.is_a?(ImageResult)
        result = ["RRD IMAGE #{child.image_id}: RRD #{child.check['type']} CHECK: #{child.check['result']}"]
        result.concat(child.reasons.map do |reason|
          "RRD IMAGE #{child.image_id}: REASON: #{reason}"
        end) if child.reasons
        result.concat(child.review_comments.map do |review_comment|
          "RRD IMAGE #{child.image_id}: REVIEW COMMENT: #{review_comment}"
        end) if child.review_comments
        [child.image_id, result]
      end.compact.to_h
    end

    # Update ALL skus attached to this asset
    # Add RRD comments to sku
    # Detach asset from sku
    def update_skus_with_rrd_check_results(asset_id, comments)
      # asset_id is the asset hash id in salsify, the comments
      # are an array of comments which are scanned for "reason"
      return if comments.nil? || comments.empty?

      attached_sku_ids = client.products_on_asset(asset_id)['digital_asset_products'].map { |sku| sku['id'] }
      return if attached_sku_ids.empty?
      attached_skus = client.products(attached_sku_ids)
      asset_name = client.asset(asset_id)['salsify:name']

      attached_skus.each do |sku|
        next unless [true, 'true', 'Yes'].include?(sku[PROPERTY_COLOR_MASTER]) || sku[PROPERTY_GROUP_ORIN]

        # Determine which property this asset is on on the product
        asset_property = sku.find do |property, value|
          value == asset_id
        end

        asset_failed_property = nil
        if asset_property
          # asset_property will be [property, value] if present, get property
          asset_property = asset_property.first
          shot_type_match = asset_property.match(/^.+- (.+) -.+$/)
          shot_type = shot_type_match && shot_type_match[1] ? shot_type_match[1] : nil
          next unless shot_type
          asset_failed_property = "Vendor Images - #{shot_type} - imageFailed"
        end

        # If the asset failed, remove it from the product and
        # flip the associated flag to indicate it failed
        clear_asset_property = false
        if comments.any? { |comment| ['fail', 'reject'].any? { |keyword| comment.downcase.include?(keyword) }}
          clear_asset_property = true
        end

        # Determine comments to add to product's RRD notes
        rrd_notes = comments.map do |comment|
          if comment.include?('RRD IMAGE')
            match = comment.match(/RRD IMAGE (\d+):/)
            if match && match[1]
              rrd_image_id = match[1]
              comment.gsub("RRD IMAGE #{rrd_image_id}:", "RRD IMAGE #{rrd_image_id} (#{asset_name}):")
            end
          else
            comment
          end
        end

        # Add new RRD notes to existing notes
        update_hash = {
          PROPERTY_RRD_NOTES => [
            sku[PROPERTY_RRD_NOTES],
            rrd_notes
          ].flatten.reject { |note|
            [nil, ''].include?(note)
          }
        }

        if asset_property && asset_failed_property && clear_asset_property
          update_hash.merge!({
            asset_property => nil, # clear the asset from this property
            asset_failed_property => true, # set the asset failed flag
            PROPERTY_REJECTED_IMAGES => [ # add asset to rejected images
              sku[PROPERTY_REJECTED_IMAGES],
              asset_id
            ].flatten.reject { |note|
              [nil, ''].include?(note)
            }
          })
        end

        #puts "$RRD$ Applying comments to SKU #{sku['salsify:id']}"
        client.update_product(sku['salsify:id'], update_hash)
      end
    end

    def send_rrd_check_results_to_salsify(comments_by_image_id_per_response)
      puts "$RRD$ Applying RRD image feedback to salsify images from #{comments_by_image_id_per_response.length} xml responses"
      image_failures = []
      all_comments_by_asset_id = {}
      comments_by_product_info = {}
      comments_by_image_id_per_response.each do |comments_by_image_id|
        puts "$RRD$ Applying RRD image feedback to #{comments_by_image_id.length} salsify image versions"
        comments_by_image_id.each do |image_id, comments|
          # ACHTUNG:
          #   The image_id here is a String.
          #   The image_id that is the key in the asset_by_image_id hash is an int
          if asset_by_image_id[image_id.to_i]
            salsify_asset_id = asset_by_image_id[image_id.to_i]['salsify:id']
            salsify_asset_name = asset_by_image_id[image_id.to_i]['salsify:name']
            salsify_asset_metadata = asset_by_image_id[image_id.to_i][PROPERTY_IMAGE_METADATA]

            if all_comments_by_asset_id[salsify_asset_id]
              all_comments_by_asset_id[salsify_asset_id].concat(comments)
            else
              all_comments_by_asset_id[salsify_asset_id] = comments
            end
            image_failed = [comments].flatten.any? do |comment|
              comment.downcase.include?('fail') || comment.downcase.include?('reject')
            end

            if image_failed
              image_failures << {
                salsify_asset_id: salsify_asset_id,
                salsify_asset_name: salsify_asset_name,
                image_id: image_id,
                comments: comments,
                image_metadata: salsify_asset_metadata
              }
            end
          else
            img = RrdImageId.find_by(id: image_id.to_i)
            next unless img
            product_info = {
              'product_id' => img.product_id,
              'color_code' => img.color_code,
              'shot_type' => img.shot_type
            }
            comments_by_product_info[product_info] = [] unless comments_by_product_info[product_info]
            comments_by_product_info[product_info].concat(comments)
          end
        end
      end

      # Add comments to salsify assets (pass or fail)
      # NOTE: Could DRY these up now that we call them the same way, but leaving
      # as is in case we want to handle these differently in the future
      puts "$RRD$ Applying comments to #{all_comments_by_asset_id.length} assets and related products"
      all_comments_by_asset_id.each do |asset_id, comments|
        client.update_asset(asset_id, { 'rrd_results' => comments })
        if [comments].flatten.any? { |comment| comment.downcase.include?('fail') || comment.downcase.include?('reject') || comment.downcase.include?('retouch') }

          # Mechanical check failure
          if [comments].flatten.any? { |comment| comment.downcase.include?('mechanical') }
            update_skus_with_rrd_check_results(asset_id, comments)
          end

          # Creative check failure
          if [comments].flatten.any? { |comment| comment.downcase.include?('creative') }
            update_skus_with_rrd_check_results(asset_id, comments)
          end

        elsif [comments].flatten.any? { |comment| comment.downcase.include?('pass') || comment.downcase.include?('approv') }

          # Mechanical check pass
          if [comments].flatten.any? { |comment| comment.downcase.include?('mechanical') }
            update_skus_with_rrd_check_results(asset_id, comments)
          end

          # Creative check pass
          if [comments].flatten.any? { |comment| comment.downcase.include?('creative') }
            update_skus_with_rrd_check_results(asset_id, comments)
          end

        else
          # asset_id is in the void
          puts "Asset ID: #{asset_id} was neither pass nor fail. (#{comments})"
        end
      end

      # Add comments for image IDs which aren't associated to any assets in salsify
      if !comments_by_product_info.empty?
        puts "$RRD$ Applying comments to products without related assets"
        add_comments_to_products_without_assets(comments_by_product_info)
      end

      puts "$RRD$ Querying related SKU info to send failure report emails"
      # Query related sku info to determine department, which determines email recipients,
      #   but also used to update PROPERTY_WORKFLOW_ATTRIBUTE
      product_ids_by_asset_id = image_failures.map do |failure|
        failure[:salsify_asset_id]
      end.map do |salsify_asset_id|
        ids = client.products_on_asset(salsify_asset_id)['digital_asset_products'].map { |prod| prod['id'] }
        unless ids.empty?
          [salsify_asset_id, ids]
        end
      end.compact.to_h

      products_by_id = product_ids_by_asset_id.values.flatten.uniq.compact.each_slice(100).map do |product_id_batch|
        client.products(product_id_batch)
      end.flatten.reject do |product|
        product.empty?
      end.map do |product|
        [product['salsify:id'], product]
      end.to_h

      parent_by_id = products_by_id.map do |id, product|
        product['salsify:parent_id']
      end.uniq.compact.each_slice(100).map do |parent_id_batch|
        client.products(parent_id_batch)
      end.flatten.reject do |parent|
        parent.empty?
      end.map do |parent|
        [parent['salsify:id'], parent]
      end.to_h

      email_groups_path = mode == :prod ? BELK_EMAIL_GROUPS_FILEPATH_PROD : BELK_EMAIL_GROUPS_FILEPATH_TEST
      if !image_failures.empty? && File.exists?(email_groups_path)
        begin
          depts_by_id = JSON.parse(File.read(email_groups_path))

          image_failures_by_dept_num = {}
          image_failures.each do |failure|
            product = products_by_id[product_ids_by_asset_id[failure[:salsify_asset_id]].first]
            next unless product
            parent = parent_by_id[product['salsify:parent_id']]
            next unless product || parent
            if product && product[PROPERTY_DEPT_NUMBER]
              dept_num = product[PROPERTY_DEPT_NUMBER]
            elsif parent && parent[PROPERTY_DEPT_NUMBER]
              dept_num = parent[PROPERTY_DEPT_NUMBER]
            else
              dept_num = nil
            end
            next unless dept_num
            all_metadata = JSON.parse(failure[:image_metadata])
            key = parent ? "#{parent['salsify:id']}_#{product[PROPERTY_COLOR_CODE]}" : "#{product['salsify:id']}_000"
            metadata = all_metadata[key]
            next unless metadata
            image_failures_by_dept_num[dept_num] = [] unless image_failures_by_dept_num[dept_num]
            expected_date_str = product[PROPERTY_COMPLETION_DATE] || parent[PROPERTY_COMPLETION_DATE]
            failure_reason_match = failure[:comments].last.match(/REASON:\s(.+)$/)
            image_failures_by_dept_num[dept_num] << {
              'SKU' => product['salsify:id'],
              'Style#' => product[PROPERTY_STYLE_NUMBER] || parent[PROPERTY_STYLE_NUMBER],
              'Color Code' => product[PROPERTY_COLOR_CODE],
              'Expected Ship Date' => expected_date_str ? DateTime.parse(expected_date_str) : nil,
              'Image Name' => metadata['filename'],
              'Original Image Name' => failure[:salsify_asset_name],
              'Type of Failure' => failure[:comments].any? { |comment| comment.downcase.include?('mechanical') } ? 'MECHANICAL' : 'CREATIVE',
              'Reason for Failure' => failure_reason_match ? failure_reason_match[1] : nil
            }
          end

          # Sort failures within each dept by expected ship date, with nils at end
          image_failures_by_dept_num = image_failures_by_dept_num.map do |dept_num, failures|
            [dept_num, failures.sort_by do |failure|
              failure['Expected Ship Date'] ? failure['Expected Ship Date'] : Date.new(10000, 1, 1)
            end]
          end.to_h

          failures_by_dept_by_recipient = {}
          image_failures_by_dept_num.each do |dept_num, failures|
            dept = depts_by_id[dept_num]
            next unless dept
            recipients = [dept['Lead'], dept['PDC'], dept['APC']].reject { |rec| [nil, ''].include?(rec) }
            recipients.each do |recipient|
              failures_by_dept_by_recipient[recipient] = {} unless failures_by_dept_by_recipient[recipient]
              failures_by_dept_by_recipient[recipient][dept_num] = failures
            end
          end

          failures_by_dept_by_recipient.each do |recipient, failures_by_dept|
            Mailer.send_mail(
              recipients: [recipient],
              subject: "Immediate Action Required - SKUs with Failed Images",
              message: belk_image_failure_email_html(failures_by_dept)
            )
          end
        rescue JSON::ParserError => e
          puts "$RRD$ Unable to send email notifications for RRD image failures, couldn't process json file defining email groups: #{e.message}"
        end
      end
    end

    def add_comments_to_products_without_assets(comments_by_product_info)
      product_ids = comments_by_product_info.keys.map { |product_info| product_info['product_id'] }.flatten.uniq.compact
      products_by_id = product_ids.each_slice(100).map do |product_id_batch|
        client.products(product_id_batch)
      end.flatten.reject do |product|
        product.empty?
      end.map do |product|
        [product['salsify:id'], product]
      end.to_h

      skus_by_parent_id = products_by_id.map do |product_id, product|
        sku_ids = filter_products(filter_hash: { PROPERTY_PARENT_PRODUCT => product_id }).map { |sku| sku.id }
        if sku_ids && !sku_ids.empty?
          [product_id, client.products(sku_ids)]
        else
          [product_id, []]
        end
      end.to_h

      comments_by_product_info.each do |product_info, comments|
        skus = skus_by_parent_id[product_info['product_id']]
        if skus && !skus.empty?
          skus.select do |sku|
            sku[PROPERTY_COLOR_CODE] == product_info['color_code'] &&
            sku[PROPERTY_COLOR_MASTER] == true
          end.each do |sku|
            client.update_product(sku['salsify:id'], {
              PROPERTY_RRD_NOTES => [sku[PROPERTY_RRD_NOTES], comments].flatten
            })
          end
        elsif product_info['color_code'] == '000'
          grouping = products_by_id[product_info['product_id']]
          client.update_product(grouping['salsify:id'], {
            PROPERTY_RRD_NOTES => [grouping[PROPERTY_RRD_NOTES], comments].flatten
          })
        end
      end
    end

    def belk_image_failure_email_html(failures_by_dept)
      "<p>Dear User,</p>" +
      "<p>Recent image(s) uploaded to Salsify failed the image check and do not meet Belk's requirements. " +
      "Please see below for the specific image(s) by SKU that failed and the reasons for which a failure resulted.</p>" +
      "<p>Replacement images that meet our requirements must be uploaded within 48 hours to allow for reprocessing of the SKU. " +
      "Please contact the Asset Procurement Coordinator with your replacement images.</p>" +
      "<p>The following list is prioritized by Expected Ship Date and should be addressed in this order:</p><br/>" +
      failures_by_dept.map { |dept_num, failure_hashes|
        "<b>Department ##{dept_num}</b>" +
        "<table style=\"border: solid 1px black\"><thead style=\"background-color: #E5E5E5;\"><tr>" +
        "<td><b>SKU</b></td>" +
        "<td><b>Style#</b></td>" +
        "<td><b>Color Code</b></td>" +
        "<td><b>Expected Ship Date</b></td>" +
        "<td><b>Image Name</b></td>" +
        "<td><b>Original Image Name</b></td>" +
        "<td><b>Type of Failure</b></td>" +
        "<td><b>Reason for Failure</b></td>" +
        "</tr></thead>" +
        "<tbody>" +
        failure_hashes.map { |hash|
          "<tr><td>#{hash['SKU']}</td>" +
          "<td>#{hash['Style#']}</td>" +
          "<td>#{hash['Color Code']}</td>" +
          "<td>#{hash['Expected Ship Date'] ? hash['Expected Ship Date'].strftime('%Y-%m-%d') : 'NONE'}</td>" +
          "<td>#{hash['Image Name']}</td>" +
          "<td>#{hash['Original Image Name']}</td>" +
          "<td>#{hash['Type of Failure']}</td>" +
          "<td>#{hash['Reason for Failure']}</td></tr>"
        }.join +
        "</tbody></table>"
      }.join('<br/><br/>') +
      "<p>For information regarding our specific requirements, please contact the Asset Procurement Coordinator in your area.</p><br/><br/>" +
      "<p>Thank you for your attention and commitment to the Belk.com digital content process.</p>"
    end

    def asset_by_image_id
      # NOTE: (ESS) even though this is memoized to limit multiple calls, this is still going to be really slow since we are getting every asset id.
      #   They are doing us a giant favor by saying they do not want to import their Scene7 images, so this may help us - but if this is like 1-2M images
      #     this will take well over a hour and maybe like 3 hours.
      # Should likely figure out how we can limit this query.
      @asset_by_image_id ||= begin
        puts "$RRD$ Retrieving assets from org #{ENV.fetch('CARS_ORG_ID')}..."
        # t = Time.now
        response = client.create_export_run({
          "configuration": {
            "entity_type": "digital_asset",
            "format": "csv",
            "include_all_columns": true
          }
        })
        completed_response = Salsify::Utils::Export.wait_until_complete(client, response).url
        csv = CSV.new(open(completed_response).read, headers: true)
        csv.to_a.map do |row|
          begin
            asset = row.to_hash
            next if [nil, ''].include?(asset[PROPERTY_IMAGE_METADATA])
            image_metadata = JSON.parse(asset[PROPERTY_IMAGE_METADATA])
            image_metadata.map do |key, hash|
              [hash['rrd_image_id'], asset]
            end
          rescue JSON::ParserError => e
            puts "There was a JSON Parsing error: #{e}"
          end
        end.compact.flatten(1).to_h.reject do |image_id, asset|
          image_id.nil?
        end
      end
    end

    #
    # Retrieve vendor image history xmls and generate image task IDs
    #

    def retrieve_rrd_history_xmls
      puts "$RRD VENDOR IMG HISTORIES$ Retrieving RRD image history files"
      FileUtils.rm_rf(Dir.glob("#{TEMP_DIR_HISTORY}/*"))
      count = 0
      with_rrd_ftp do |ftp|
        ftp_path = mode == :prod ? RRD_HISTORY_PATH_PROD : RRD_HISTORY_PATH_TEST
        ftp.chdir(ftp_path)
        # need to rescue this because ftp.nlst does not return an empty array if dir is empty, instead throws exception, which is awesome
        begin
          ftp.nlst.sort.each do |history_file_name|
            local_path = File.join(TEMP_DIR_HISTORY, history_file_name)
            ftp.getbinaryfile(history_file_name, local_path)
            s3_path = mode == :prod ? S3_PATH_IMAGE_HISTORIES_PROD : S3_PATH_IMAGE_HISTORIES_TEST
            exavault_path = mode == :prod ? EXAVAULT_PATH_IMAGE_HISTORIES_PROD : EXAVAULT_PATH_IMAGE_HISTORIES_TEST
            upload_to_s3(File.join(s3_path, history_file_name), File.read(local_path))
            upload_to_exavault(File.join(exavault_path, history_file_name), local_path)
            ftp.delete(history_file_name)
            count += 1
          end
        rescue
          puts "$RRD VENDOR IMG HISTORIES$ RRD FTP folder #{ftp_path} is empty."
        end
      end
      puts "$RRD VENDOR IMG HISTORIES$ Retrieved #{count} image history xml files from RRD"
    end

    def record_image_histories
      puts "$RRD VENDOR IMG HISTORIES$ Recording new RRD image histories"

      existing_histories = image_histories_by_image_id
      processed_images = {}
      Dir.foreach(TEMP_DIR_HISTORY) do |filename|
        next if filename.start_with?('.')
        puts "$RRD VENDOR IMG HISTORIES$ Processing image histories from #{filename}"

        # filename takes format RRDtoCARS_vendorImagesHistory_2017-12-31_235959.xml
        begin
          file_date = Date.parse(filename.split('_')[-2])
        rescue Exception => e
          # Error parsing date from filename, use today
          file_date = Date.today
        end

        CarsMessage.from_xml(
          File.read(File.join(TEMP_DIR_HISTORY, filename))
        ).children.first.vendor_images.each do |vendor_image|

          if wrong_img_id_to_correct[vendor_image.image_id]
            correct_id = wrong_img_id_to_correct[vendor_image.image_id]
          else
            correct_id = vendor_image.image_id
          end

          if existing_histories[vendor_image.image_id]
            history = existing_histories[vendor_image.image_id].first
          else
            history = RrdImageHistory.new
          end
          history.image_id = correct_id
          history.name = vendor_image.name
          history.date = file_date
          history.save!

          # Record that this image has been approved
          img_id = RrdImageId.find_by(id: history.image_id)
          if img_id
            img_id.approved = true
            img_id.save!
          end

          existing_histories[history.image_id] = [history]
          processed_images[history.image_id] = history.name.split('_')[2]
        end
      end
      puts "$RRD VENDOR IMG HISTORIES$ Recorded #{processed_images.length} approved images from history file(s)"
      processed_images
    end

    def image_histories_by_image_id
      RrdImageHistory.all.to_a.each_with_object({}) do |hist, hash|
        if hash[hist.image_id]
          hash[hist.image_id] << hist
        else
          hash[hist.image_id] = [hist]
        end
      end
    end

    def mark_approved_products(processed_images)
      if processed_images.empty?
        puts "$RRD VENDOR IMG HISTORIES$ No salsify products to add task IDs to"
        return
      end
      puts "$RRD VENDOR IMG HISTORIES$ Marking salsify products with task IDs for #{processed_images.length} images"
      approved_product_ids = []

      product_ids_by_image_id = product_ids_related_to_history_images(processed_images.keys.map { |image_id| image_id.to_i })

      # Create hash of product ID to array of approved shot types
      approved_shot_types_by_product_id = {}
      product_ids_by_image_id.each do |image_id, product_ids|
        product_ids.each do |product_id|
          approved_shot_types_by_product_id[product_id] ||= []
          unless approved_shot_types_by_product_id[product_id].include?(processed_images[image_id.to_s])
            approved_shot_types_by_product_id[product_id] << processed_images[image_id.to_s]
          end
        end
      end

      # Query all products which potentially need to be put into PIP workflow
      product_ids_by_image_id.values.flatten.uniq.compact.each_slice(100) do |product_id_batch|
        products = client.products(product_id_batch)
        parent_ids = products.map { |product| product['salsify:parent_id'] }.uniq.compact
        parents = parent_ids.empty? ? [] : client.products(parent_ids)
        products.each do |product|
          # Only start/restart the PIP workflow for this product if the
          # required shot type was approved, or if it's already been started
          parent = parents.find { |parent| parent['salsify:id'] == product['salsify:parent_id'] }
          if approved_shot_types_by_product_id[product['salsify:id']].include?(REQUIRED_VEN_IMG_SHOT_TYPE) ||
            ((parent && parent[RRD_TASK_ID_PROPERTY]) || product[RRD_TASK_ID_PROPERTY])
            approved_product_ids << (product['salsify:parent_id'] ? product['salsify:parent_id'] : product['salsify:id'])
          end
        end
      end

      # Query the styles we're going to mark as having approved
      # images so we know whether we need to reopen them or not
      parent_by_id = approved_product_ids.each_slice(100).map do |parent_id_batch|
        client.products(parent_id_batch)
      end.flatten.map do |parent|
        [parent['salsify:id'], parent]
      end.to_h

      parent_ids_to_reopen = approved_product_ids.select do |parent_id|
        parent_by_id[parent_id] && parent_by_id[parent_id][PROPERTY_PIP_ALL_IMAGES_VERIFIED]
      end

      # Remove reopened parent product ids from user-specific
      # queues so they go back to the assignment queue
      puts "$RRD VENDOR IMG HISTORIES$ Removing approved image products from user queues, sending back to assignment queue"
      if !parent_ids_to_reopen.empty?
        Parallel.each(query_lists('pip user list'), in_threads: NUM_THREADS) do |list|
          update_list(list_id: list['id'], removals: parent_ids_to_reopen)
        end
      end

      puts "$RRD VENDOR IMG HISTORIES$ Marking #{approved_product_ids.length} salsify products with task IDs"
      approved_product_ids.each do |product_id|
        puts "$RRD VENDOR IMG HISTORIES$ Setting task ID on product #{product_id}"
        pip_status = pip_workflow_value(product_id)
        update_hash = {
          RRD_TASK_ID_PROPERTY => generate_task(product_id).id,
          PIP_WORKFLOW_STATUS => pip_status
        }
        if parent_ids_to_reopen.include?(product_id)
          time_est = DateTime.now.in_time_zone(TIMEZONE_EST)
          update_hash.merge!({
            PROPERTY_REOPENED_REASON => "Task reopened on #{time_est.strftime('%Y-%m-%d')} at #{time_est.strftime('%l:%M %p %Z')} because of RRD approved images on sku(s)",
            PROPERTY_PIP_ALL_IMAGES_VERIFIED => nil,
            PROPERTY_PIP_IMAGE_APPROVED => nil
          })
        end
        client.update_product(product_id, update_hash)
      end
    end

    def pip_workflow_value(product_id)
      product = client.product(product_id)
      # Open if it is not anything
      return 'Open' unless product[PIP_WORKFLOW_STATUS]
      # Re-open if it was closed
      return 'Re-open' if product[PIP_WORKFLOW_STATUS] == 'Closed'
      # this last one is essentially an else - in this case, if it isn't these other two, just set it to what it is now
      return product[PIP_WORKFLOW_STATUS]
    end

    def product_ids_related_to_history_images(rrd_image_ids)
      image_id_records = RrdImageId.distinct.where(id: rrd_image_ids)
      image_id_records.map do |rrd_image|
        if rrd_image.salsify_asset_id
          # Record has asset id, find related products attached to it
          begin
            [rrd_image.id, client.products_on_asset(rrd_image.salsify_asset_id)['digital_asset_products'].map { |prod| prod['id'] }]
          rescue Exception => e
            puts "$RRD VENDOR IMG HISTORIES$ ERROR while finding products on asset #{rrd_image.salsify_asset_id} for RRD image ID #{rrd_image.id}: #{e.message}"
            nil
          end
        elsif rrd_image.product_id && rrd_image.color_code && rrd_image.shot_type
          # Record has no asset id, find associated product via product info
          begin
            sku_ids = filter_products(filter_hash: { PROPERTY_PARENT_PRODUCT => rrd_image.product_id }).map { |sku| sku.id }
            if sku_ids && !sku_ids.empty?
              [rrd_image.id, client.products(sku_ids).select do |sku|
                sku[PROPERTY_COLOR_CODE] == rrd_image.color_code
              end.map { |sku| sku['salsify:id'] }]
            else
              product = client.product(rrd_image.product_id)
              if product[PROPERTY_GROUP_ORIN]
                [rrd_image.id, rrd_image.product_id]
              end
            end
          rescue Exception => e
            puts "$RRD VENDOR IMG HISTORIES$ ERROR while finding children for product #{rrd_image.product_id} for RRD image ID #{rrd_image.id}: #{e.message}"
            nil
          end
        end
      end.compact.to_h
    end

    def generate_task(product_id)
      task = RrdTaskId.find_by(product_id: product_id)
      if task.nil?
        task = RrdTaskId.new
        task.product_id = product_id
        task.save!
      end
      task
    end

    #
    # Send new sample photo requests to RRD
    #

    def notify_rrd_of_requested_samples
      requests = RrdRequestedSample.where(sent_to_rrd: false)
      if requests.empty?
        puts "$RRD SEND SAMPLE REQS$ No sample requests to send to RRD"
        return
      else
        puts "$RRD SEND SAMPLE REQS$ Sending #{requests.length} sample requests to RRD"
        ENV['TZ'] = 'America/New_York' # Ensure we use EST for timestamp
        filepath = File.join(TEMP_DIR_REQUESTS, "CARStoRRD_PhotoRequests_#{Time.now.strftime('%Y-%m-%d_%H%M%S')}.xml")
        msg = sampled_products_message(requests)
        File.open(filepath, 'w') do |file|
          file.write(msg.to_xml)
        end
        xls_filepath = msg.write_excel_copy(filepath.gsub('.xml', '.xls'))
        if mode == :prod
          with_rrd_ftp do |ftp|
            ftp.putbinaryfile(filepath, File.join(RRD_SAMPLE_REQUEST_PATH_XML_PROD, filepath.split('/').last))
          end
          with_rrd_samples_ftp do |ftp|
            ftp.putbinaryfile(xls_filepath, File.join(RRD_SAMPLE_REQUEST_PATH_EXCEL_PROD, xls_filepath.split('/').last))
          end
        else
          with_rrd_samples_ftp do |ftp|
            ftp.putbinaryfile(filepath, File.join(RRD_SAMPLE_REQUEST_PATH_XML_TEST, filepath.split('/').last))
            ftp.putbinaryfile(xls_filepath, File.join(RRD_SAMPLE_REQUEST_PATH_EXCEL_TEST, xls_filepath.split('/').last))
          end
        end

        requests.each do |req|
          req.sent_to_rrd = true
          req.save!
        end
      end
    end

    def product_by_id_for_sample(product_ids)
      if product_ids.empty?
        {}
      else
        product_ids.each_slice(100).map do |product_id_batch|
          client.products(product_id_batch)
        end.flatten.reject do |product|
          product.empty?
        end.map do |product|
          [product['salsify:id'], product]
        end.to_h
      end
    end

    def sampled_products_message(requests)
      CarsMessage.new(
        { 'type' => 'photoRequests', 'to' => 'RRD', 'from' => 'CARS' },
        ProductPhotoRequests.new(
          product_by_id_for_sample(
            requests.map { |req|
              req.product_id
            }.compact.uniq
          ).map { |product_id, product|
            ProductPhotoRequest.new(
              car: { 'id' => product_id },
              product: ProductPhotoRequest::Product.new(
                type: product[PROPERTY_IPH_CATEGORY] ? product[PROPERTY_IPH_CATEGORY].split(IPH_PATH_DELIMITER).last : nil,
                name: strip_non_ascii(product[PROPERTY_DISPLAY_NAME]),
                vendor: {
                  'id' => product_id[0..6],
                  'name' => strip_non_ascii(product[PROPERTY_VENDOR_NAME])
                },
                style: {
                  'id' => product_id[7..-1]
                },
                brand: {
                  'name' => strip_non_ascii(product[PROPERTY_BRAND])
                },
                department: {
                  'id' => product[PROPERTY_DEPT_NUMBER],
                  'name' => strip_non_ascii(product[PROPERTY_DEPT_NAME])
                },
                _class: {
                  'id' => product[PROPERTY_CLASS_NUMBER],
                  'name' => strip_non_ascii(product[PROPERTY_CLASS_NAME])
                }
              ),
              photos: requests.select { |req|
                req.product_id == product[product_id_property]
              }.map { |req|
                ProductPhotoRequest::Photo.new(
                  type: 'sample',
                  file: {
                    'OForSLvalue' => req.of_or_sl,
                    'name' => {
                      'prefix' => "#{product_id[0..6]}_#{product_id[7..-1]}_X_#{req.color_id ? req.color_id.strip : ''}"
                    }
                  },
                  instructions: [req.instructions],
                  samples: [
                    ProductPhotoRequest::Photo::Sample.new(
                      id: req.id,
                      type: req.sample_type,
                      color: {
                        'code' => (req.color_id ? req.color_id.strip : ''),
                        'name' => req.color_name
                      },
                      return_requested: req.must_be_returned ? 'Y' : 'N',
                      return_information: {
                        'shipping_account' => {
                          'carrier' => 'UPS'
                        },
                        'instructions' => []
                      },
                      silhouette_required: req.silhouette_required ? 'Y' : 'N'
                    )
                  ]
                )
              }
            )
          }.compact
        )
      )
    end

    def generate_car(product)
      car = RrdCarId.find_by(product_id: product[product_id_property])
      return car if car
      car = RrdCarId.new
      car.product_id = product[product_id_property]
      car.save!
      car
    end

    #
    # Check RRD for sample history xmls
    #

    def retrieve_rrd_sample_histories
      puts "$RRD SAMPLE HISTORIES$ Retrieving RRD sample history files"
      Dir.foreach(TEMP_DIR_SAMPLE_HISTORY) do |filename|
        next if filename.start_with?('.')
        File.delete(File.join(TEMP_DIR_SAMPLE_HISTORY, filename))
      end
      count = 0
      with_rrd_ftp do |ftp|
        ftp_path = mode == :prod ? RRD_SAMPLE_HISTORY_PATH_PROD : RRD_SAMPLE_HISTORY_PATH_TEST
        ftp.chdir(ftp_path)
        # need to rescue this because ftp.nlst does not return an empty array if dir is empty, instead throws exception, which is awesome
        begin
          ftp.nlst.sort.each do |history_file_name|
            next unless history_file_name.include?('.xml')
            local_path = File.join(TEMP_DIR_SAMPLE_HISTORY, history_file_name)
            ftp.getbinaryfile(history_file_name, local_path)
            s3_path = mode == :prod ? S3_PATH_SAMPLE_HISTORIES_PROD : S3_PATH_SAMPLE_HISTORIES_TEST
            exavault_path = mode == :prod ? EXAVAULT_PATH_SAMPLE_HISTORIES_PROD : EXAVAULT_PATH_SAMPLE_HISTORIES_TEST
            upload_to_s3(File.join(s3_path, history_file_name), File.read(local_path))
            upload_to_exavault(File.join(exavault_path, history_file_name), local_path)
            ftp.delete(history_file_name)
            count += 1
          end
        rescue
          puts "$RRD SAMPLE HISTORIES$ RRD FTP folder #{ftp_path} is empty."
        end
      end
      puts "$RRD SAMPLE HISTORIES$ Retrieved #{count} sample history files from RRD"
    end

    def record_sample_histories
      puts "$RRD SAMPLE HISTORIES$ Recording RRD sample histories"

      # This is a hash of parent ID to array of color codes from completed samples
      completed_sample_colors_by_parent_id = {}
      existing_sample_histories_by_id = RrdRequestedSample.all.map do |sample|
        [sample.id, sample]
      end.to_h
      Dir.foreach(TEMP_DIR_SAMPLE_HISTORY) do |filename|
        next if filename.start_with?('.')

        sample_history_message = CarsMessage.from_xml(
          File.read(File.join(TEMP_DIR_SAMPLE_HISTORY, filename))
        )
        # sample_history_message will be nil if file is empty
        next unless sample_history_message && sample_history_message.children && sample_history_message.children.first

        sample_history_message.children.first.sample_histories.each do |sample_history|
          sample = existing_sample_histories_by_id[sample_history.sample['id'].to_i]
          if sample && sample_history.events.any? { |event|
            event['type'] == 'photo sent'
          }
            # Sample has been completed, record in db
            ENV['TZ'] = 'America/New_York' # Ensure we use EST for timestamp
            sample.completed_at = Time.now.to_s
            sample.save!
            completed_sample_colors_by_parent_id[sample.product_id] = [] unless completed_sample_colors_by_parent_id[sample.product_id]
            completed_sample_colors_by_parent_id[sample.product_id] << sample.color_id
            # TODO: Pull images generated from this sample request
            # ^ this is the spot to make the call for temp images using web services code (see java example)
          end
        end
      end
      puts "$RRD SAMPLE HISTORIES$ Detected #{completed_sample_colors_by_parent_id.length} products affected by completed sample requests based on sample histories"
      completed_sample_colors_by_parent_id
    end

    def mark_sample_approved_products(completed_sample_colors_by_parent_id)
      if completed_sample_colors_by_parent_id.empty?
        puts "$RRD SAMPLE HISTORIES$ No salsify products to generate sample task IDs for"
        return
      end
      product_by_id = {}
      completed_sample_colors_by_parent_id.keys.each_slice(100) do |product_id_batch|
        client.products(product_id_batch).each do |product|
          product_by_id[product['salsify:id']] = product
        end
      end

      parent_ids_to_reopen = completed_sample_colors_by_parent_id.keys.select do |parent_id|
        product_by_id[parent_id] && product_by_id[parent_id][PROPERTY_PIP_ALL_IMAGES_VERIFIED]
      end

      # Remove reopened parent product ids from user-specific
      # queues so they go back to the assignment queue
      puts "$RRD SAMPLE HISTORIES$ Removing approved sample products from user queues, sending back to assignment queue"
      if !parent_ids_to_reopen.empty?
        Parallel.each(query_lists('pip user list'), in_threads: NUM_THREADS) do |list|
          update_list(list_id: list['id'], removals: parent_ids_to_reopen)
        end
      end

      puts "$RRD SAMPLE HISTORIES$ Adding image task ID to #{completed_sample_colors_by_parent_id.length} products due to completed sample requests (may already have task ID)"
      Parallel.each(completed_sample_colors_by_parent_id, in_threads: NUM_THREADS) do |product_id, color_codes|
        # Add a task ID and flip a flag on the parent product
        begin
          pip_status = pip_workflow_value(product_id)
          update_hash = {
            RRD_TASK_ID_PROPERTY => generate_task(product_id).id,
            PROPERTY_SKU_IMAGES_UPDATED => true,
            PIP_WORKFLOW_STATUS => pip_status
          }
          if parent_ids_to_reopen.include?(product_id)
            time_est = DateTime.now.in_time_zone(TIMEZONE_EST)
            update_hash.merge!({
              PROPERTY_REOPENED_REASON => "Task reopened on #{time_est.strftime('%Y-%m-%d')} at #{time_est.strftime('%l:%M %p %Z')} because of RRD completed samples on sku(s) for color code(s): #{color_codes.join(', ')}",
              PROPERTY_PIP_ALL_IMAGES_VERIFIED => nil,
              PROPERTY_PIP_IMAGE_APPROVED => nil
            })
          end
          product = product_by_id[product_id]
          update_hash[PROPERTY_SAMPLE_COMPLETE] = true if product[PROPERTY_GROUP_ORIN]
          client.update_product(product_id, update_hash)

          if product[PROPERTY_GROUP_ORIN].nil?
            next if color_codes.empty?
            sku_ids = filter_products(filter_hash: { PROPERTY_PARENT_PRODUCT => product_id }).map { |sku| sku.id }
            next if sku_ids.empty?
            skus = sku_ids.each_slice(100).map do |sku_id_batch|
              client.products(sku_id_batch)
            end.flatten
            next unless skus && !skus.empty?
            color_codes.each do |color_code|
              sku = skus.find do |sku|
                sku[PROPERTY_COLOR_CODE] == color_code &&
                sku[PROPERTY_COLOR_MASTER] == true
              end
              client.update_product(sku['salsify:id'], { PROPERTY_SAMPLE_COMPLETE => true }) if sku
            end
          end
        rescue RestClient::InternalServerError => e
          puts "$RRD SAMPLE HISTORIES$ 500 ERROR: #{e.message}\n#{e.backtrace.join("\n")}\n\nproduct_id = #{product_id}"
        rescue RestClient::ResourceNotFound => e
          puts "$RRD SAMPLE HISTORIES$ No product found for ID #{product_id} while adding task ID from completed sample request"
        end

      end
    end

    #
    # Generate and send hex value feed to Belk
    #
    def generate_hex_feed
      FileUtils.rm_rf(Dir.glob("#{TEMP_DIR_HEX_FEED}/*"))
      puts "$HEX$ Generating hex feed files"
      # Find products with actual hex values that we want to send
      hex_products_by_id = products_with_hex_value.select do |product_id, product|
        product[PROPERTY_HEX_COLOR] && (
          product['salsify:parent_id'] ||
          (
            product['salsify:parent_id'].nil? &&
            product[PROPERTY_GROUPING_TYPE]
          )
        )
      end

      # Remove whitespace and split on commas, but should be stored as multi-value
      hex_products_by_id.each do |product_id, product|
        product[PROPERTY_HEX_COLOR] = [product[PROPERTY_HEX_COLOR]].flatten.map do |hex_color|
          hex_color.gsub(' ', '').split(',')
        end.flatten
      end

      hex_products_by_id.values.group_by { |product| product['salsify:parent_id'] }.map do |parent_id, skus|
        valid_hex_values_by_sku_id = skus.map do |sku|
          [sku['salsify:id'], [sku[PROPERTY_HEX_COLOR]].flatten.select do |hex_color|
            hex_color.is_a?(String) && hex_color.length > 5
          end]
        end.to_h

        # Skip this if no valid hex values
        next unless valid_hex_values_by_sku_id.any? do |sku_id, hex_colors|
          !hex_colors.empty?
        end

        if parent_id
          # skus are a product family
          parent = products_with_hex_value[parent_id]
          filepath = File.join(TEMP_DIR_HEX_FEED, "#{parent[PROPERTY_VENDOR_NUMBER]}_#{parent[PROPERTY_STYLE_NUMBER]}_color.txt")
          CSV.open(filepath, 'w', { col_sep: "\t" }) do |csv|
            skus.each do |sku|
              hex_colors = valid_hex_values_by_sku_id[sku['salsify:id']]
              next unless hex_colors && !hex_colors.empty?
              csv << [
                parent[PROPERTY_VENDOR_NUMBER],
                parent[PROPERTY_STYLE_NUMBER],
                sku[PROPERTY_COLOR_CODE],
                hex_colors.join(',')
              ]
            end
          end
          filepath
        else
          # skus are grouping products without parents
          skus.map do |sku|
            hex_colors = valid_hex_values_by_sku_id[sku['salsify:id']]
            next unless hex_colors && !hex_colors.empty?
            filepath = File.join(TEMP_DIR_HEX_FEED, "#{sku[PROPERTY_VENDOR_NUMBER]}_#{sku[PROPERTY_STYLE_NUMBER]}_color.txt")
            CSV.open(filepath, 'w', { col_sep: "\t" }) do |csv|
              csv << [
                sku[PROPERTY_VENDOR_NUMBER],
                sku[PROPERTY_STYLE_NUMBER],
                sku[PROPERTY_COLOR_CODE],
                hex_colors.join(',')
              ]
            end
            filepath
          end.compact
        end
      end.flatten.uniq.compact
    end

    def send_hex_feed(filepaths)
      puts "$HEX$ Sending Belk #{filepaths.length} hex feed files..."
      successes = 0
      permission_failures = 0
      disconnect_failures = 0
      other_failures = []
      total = 0
      with_belk_hex_sftp do |sftp|
        Parallel.each(filepaths, in_threads: 4) do |filepath|
          tries = 0
          begin
            filename = filepath.split('/').last
            ftp_path = mode == :prod ? BELK_HEX_FEED_FTP_PATH_PROD : BELK_HEX_FEED_FTP_PATH_TEST
            sftp.upload(filepath, "#{ftp_path}/#{filename}")
            successes += 1
          rescue Net::SFTP::StatusException => e
            if e.message.include?('permission denied')
              #puts "$HEX$ Permission denied while uploading hex file #{filepath}, likely already exists and can't overwrite"
              permission_failures += 1
            else
              raise e
            end
          rescue Net::SSH::Disconnect => e
            if tries < 3
              tries += 1
              retry
            else
              puts "$HEX$ DISCONNECT - Got disconnect error after 3 retries for file #{filepath}"
              disconnect_failures += 1
            end
          rescue Exception => e
            puts "$HEX$ Unknown error: #{e}\n#{e.message}"
            other_failures << e
          end
          total += 1
          puts "#{total}/#{filepaths.length}" if total % 400 == 0
        end
      end
      puts "$HEX$ DONE! #{successes} successes and #{permission_failures} permission denied failures and #{disconnect_failures} disconnect failures and #{other_failures.length} other failures"
      if !other_failures.empty?
        other_failures.each { |failure| puts failure }
      end
    end

    # Includes all products with an updated Hex Color as well as their parents
    # Returns hash of product info keyed on product IDs
    def products_with_hex_value
      @products_with_hex_value ||= begin
        response = client.create_export_run({
          "configuration": {
            "entity_type": 'product',
            "format": "json",
            "include_all_columns": false,
            "properties": "'salsify:id','salsify:parent_id','#{PROPERTY_VENDOR_NUMBER}','#{PROPERTY_STYLE_NUMBER}','#{PROPERTY_COLOR_CODE}','#{PROPERTY_HEX_COLOR}','#{PROPERTY_GROUPING_TYPE}'",
            "filter": "=list:#{hex_color_list_id}:product_type:all"
          }
        })
        completed_response = Salsify::Utils::Export.wait_until_complete(client, response).url
        Hash[JSON.parse(open(completed_response).read)[4]['products'].map do |product|
          [product['salsify:id'], product.select do |attribute|
            [
              'salsify:parent_id', 'salsify:id',
              PROPERTY_VENDOR_NUMBER, PROPERTY_STYLE_NUMBER,
              PROPERTY_COLOR_CODE, PROPERTY_HEX_COLOR
            ].include?(attribute)
          end]
        end]
      end
    end

    def hex_color_list_id
      @hex_color_list_id ||= ENV.fetch('HEX_COLOR_LIST_ID')
    end

    #
    # Pull ADS files from Belk which contain Scene7 image urls
    # with identifying product info, add urls to Salsify products
    #
    def retrieve_ads_files_from_belk
      # clear dir first
      FileUtils.rm_rf(Dir.glob("#{TEMP_DIR_ADS_FEED}/*"))
      with_belk_ads_sftp do |sftp|
        # Setup as glob so that can later limit by filetype or name contents
        ftp_path = mode == :prod ? BELK_ADS_FEED_FTP_PATH_PROD : BELK_ADS_FEED_FTP_PATH_TEST
        max_files = ENV['ADS_DAEMON_MAX_FILES'] ? ENV.fetch('ADS_DAEMON_MAX_FILES').to_i : nil
        count = 0
        sftp.find_files(ftp_path, '').each do |filepath|
          next if max_files && count >= max_files
          begin
            filename = filepath.split('/').last
            puts "$ADS$ Retrieving ADS file: #{filepath}"
            sftp.download(filepath, "#{TEMP_DIR_ADS_FEED}/#{filename}")
          rescue Exception => e
            puts "$ADS$ ERROR while downloading ADS file #{filepath}: #{e.message}"
          end
          count += 1
        end
      end
    end

    def parse_urls_from_ads_files
      # Each ADS file row contains the following data separated by tabs
      # vendorNumber styleNumber shotType colorCode main_url swatch_url viewer_url

      urls_by_property_by_product_info = {}
      Dir.foreach(TEMP_DIR_ADS_FEED) do |filename|
        # We iterate through files in alpha order, they should go
        # oldest to newest because of their timestamps
        next if filename.start_with?('.')
        puts "$ADS$ Processing ADS file #{filename}"
        CSV.foreach(File.join(TEMP_DIR_ADS_FEED, filename), { :col_sep => "\t"}) do |row|
          next if row.nil? || row.empty?
          # Overwrite any previous urls for this product
          # since we move from oldest to newest files.
          # Hash key is vendorNumberStyleNumber_colorCode,
          # first two point to parent, color specifies a sku.
          product_info_key = "#{row[0]}#{row[1]}_#{row[3]}"
          urls_by_property = {
            "Scene7 Images - #{row[2]} - mainImage URL" => row[4],
            "Scene7 Images - #{row[2]} - swatchImage URL" => row[5],
            "Scene7 Images - #{row[2]} - viewerImage URL" => row[6]
          }
          if urls_by_property_by_product_info[product_info_key]
            urls_by_property_by_product_info[product_info_key].merge!(urls_by_property)
          else
            urls_by_property_by_product_info[product_info_key] = urls_by_property
          end
        end
      end
      urls_by_property_by_product_info
    end

    def add_ads_urls_to_salsify_products(urls_by_property_by_product_info)
      if urls_by_property_by_product_info.empty?
        puts "$ADS$ No ADS files with Scene7 urls to process"
        return
      end

      puts "$ADS$ Query A"
      parent_ids = urls_by_property_by_product_info.map do |product_info, urls_by_property|
        product_info.split('_').first
      end.uniq.compact

      puts "$ADS$ Query B"
      parents_by_id = parent_ids.each_slice(100).map do |parent_id_batch|
        client.products(parent_id_batch)
      end.flatten.reject do |product|
        product.empty?
      end.map do |product|
        [product['salsify:id'], product]
      end.to_h

      puts "$ADS$ Query C"
      sku_ids_by_parent_id = parent_ids.select do |parent_id|
        parents_by_id[parent_id]
      end.map do |parent_id|
        [parent_id, filter_products(filter_hash: { PROPERTY_PARENT_PRODUCT => parent_id }).map { |sku| sku.id }]
      end.to_h

      puts "$ADS$ Query D"
      skus_by_id = sku_ids_by_parent_id.values.flatten.uniq.each_slice(100).map do |sku_id_batch|
        client.products(sku_id_batch)
      end.flatten.reject do |sku|
        sku.empty?
      end.map do |sku|
        [sku['salsify:id'], sku]
      end.to_h

      # Reference this class so we autoload it.  Autoloading it for the first time
      # in the parallel code below can result in a race condition and crash.
      PIMFeed::SalsifyImportFile::AddImagesToStyle

      puts "$ADS$ Updating skus and grouping products"
      parent_ids_to_process = {}
      parent_ids_to_reopen = {}
      errors_to_report = []
      Parallel.each(urls_by_property_by_product_info, in_threads: NUM_THREADS) do |product_info, urls_by_property|
        begin
          parent = parents_by_id[product_info.split('_').first]
          next unless parent
          sku_ids = sku_ids_by_parent_id[parent['salsify:id']]
          same_color_skus = skus_by_id.values.select do |sku|
            sku_ids.include?(sku['salsify:id']) &&
            sku[PROPERTY_COLOR_CODE] &&
            sku[PROPERTY_COLOR_CODE].is_a?(String) &&
            sku[PROPERTY_COLOR_CODE].strip == product_info.split('_').last
          end

          begin
            if same_color_skus.empty? && parent[PROPERTY_GROUPING_TYPE]
              # Modify grouping product in place, adding the All Images property
              parent_by_id = { parent['salsify:id'] => parent.merge(urls_by_property) }
              PIMFeed::SalsifyImportFile::AddImagesToStyle.run(parent_by_id)
              client.update_product(parent['salsify:id'],
                urls_by_property.merge({
                  PROPERTY_PIP_ALL_IMAGES_VERIFIED => nil,
                  PROPERTY_PIP_IMAGE_APPROVED => nil,
                  PROPERTY_ALL_IMAGES => parent_by_id[parent['salsify:id']][PROPERTY_ALL_IMAGES]
                })
              )
            elsif !same_color_skus.empty?
              same_color_skus.each do |sku|
                if !(urls_by_property.keys - sku.keys).empty? && parent[PROPERTY_PIP_ALL_IMAGES_VERIFIED]
                  # This sku is having a new scene7 url property added AND style is PIP complete, need to reopen the style task
                  parent_ids_to_reopen[parent['salsify:id']] = 1
                end
                # Add scene7 urls to sku
                sku.merge!(urls_by_property) # merge this in for later // 20170928-LW: not sure why we're doing this, maybe clean this up?
                client.update_product(sku['salsify:id'], urls_by_property.merge({ PROPERTY_ALL_IMAGES => ' ' }))
              end
              parent_ids_to_process[parent['salsify:id']] = 1
            end
          rescue RestClient::UnprocessableEntity => e
            puts "$ADS$ Error while updating product with product info #{product_info} from ADS file. urls_by_property keys are: #{urls_by_property.keys}"
            errors_to_report << {
              'product_info' => product_info,
              'url_properties' => urls_by_property.keys
            }
          end
        rescue Exception => e
          puts "$ADS$ Error while processing product_info #{product_info}, skipping! Error is: #{e.message}\n#{e.backtrace.join("\n")}"
        end
      end

      send_ads_error_report(errors_to_report) unless errors_to_report.empty?

      # Remove reopened parent product ids from user-specific
      # queues so they go back to the assignment queue
      if !parent_ids_to_reopen.empty?
        Parallel.each(query_lists('pip user list'), in_threads: NUM_THREADS) do |list|
          update_list(list_id: list['id'], removals: parent_ids_to_reopen.keys)
        end
      end

      puts "$ADS$ Updating parent products"
      # Process any updates to updated sku parents
      Parallel.each(parent_ids_to_process.keys, in_threads: NUM_THREADS) do |parent_id|
        parent = parents_by_id[parent_id]
        sku_ids = sku_ids_by_parent_id[parent_id]
        child_sku_by_id = skus_by_id.select { |sku_id, sku| sku_ids.include?(sku_id) }
        family_by_id = child_sku_by_id.merge({ parent_id => parent })

        PIMFeed::SalsifyImportFile::AddImagesToStyle.run(family_by_id)
        update_hash = { PROPERTY_ALL_IMAGES => family_by_id[parent_id][PROPERTY_ALL_IMAGES] }

        if parent_ids_to_reopen[parent_id]
          # Need to reopen this task, clear these fields and add a reason
          time_est = DateTime.now.in_time_zone(TIMEZONE_EST)
          update_hash.merge!({
            PROPERTY_PIP_ALL_IMAGES_VERIFIED => nil,
            PROPERTY_PIP_IMAGE_APPROVED => nil,
            PROPERTY_REOPENED_REASON => "Task reopened on #{time_est.strftime('%Y-%m-%d')} at #{time_est.strftime('%l:%M %p %Z')} because of new Scene7 URLs on sku(s)"
          })
        end

        client.update_product(parent_id, update_hash)
      end
      return true
    end

    def clear_processed_ads_files
      puts "$ADS$ Clearing processed ADS files from Belk FTP"
      processed_local_filenames = []
      Dir.foreach(TEMP_DIR_ADS_FEED) do |filename|
        next if filename.start_with?('.')
        processed_local_filenames << filename
      end
      with_belk_ads_sftp do |sftp|
        ftp_path = mode == :prod ? BELK_ADS_FEED_FTP_PATH_PROD : BELK_ADS_FEED_FTP_PATH_TEST
        sftp.find_files(ftp_path, '').each do |filepath|
          filename = filepath.split('/').last
          local_file = processed_local_filenames.find { |local| local == filename }
          if local_file
            puts "$ADS$ Archiving #{filename} on S3 and deleting from Belk FTP"
            s3_path = mode == :prod ? S3_PATH_ADS_FILES_PROD : S3_PATH_ADS_FILES_TEST
            exavault_path = mode == :prod ? EXAVAULT_PATH_ADS_FILES_PROD : EXAVAULT_PATH_ADS_FILES_TEST
            upload_to_s3(File.join(s3_path, filename), File.read(File.join(TEMP_DIR_ADS_FEED, local_file)))
            upload_to_exavault(File.join(exavault_path, filename), File.join(TEMP_DIR_ADS_FEED, local_file))
            sftp.remove(filepath)
          end
        end
      end
    end

    def send_ads_error_report(errors_to_report)
      Mailer.send_mail(
        recipients: ADS_FEED_ERROR_EMAIL_RECIPIENTS,
        subject: 'Issue(s) detected in ADDS feed',
        message: "<p>One or more issues were detected while processing ADDS files. " +
                  "Below is a list of the processed ADDS files, as well as a list of issues. " +
                  "Each issue description has a product code and NRF color code, as well as the " +
                  "list of Salsify properties we attempted to apply the Scene7 URLs to based " +
                  "on the shot type provided in the ADDS file.<br/><br/>" +
                  "<b>ADDS files processed:</b><br/>" +
                  "#{local_ads_file_names.join("<br/>")}<br/><br/>" +
                  "<b>Issues:</b><br/>" +
                  errors_to_report.map { |hash|
                    "Product Info: #{hash['product_info']}<br/>" +
                    "Properties Applied: #{hash['url_properties']}<br/>"
                  }.join("<br/>") +
                  "</p>"
      )
    end

    def local_ads_file_names
      Dir.foreach(TEMP_DIR_ADS_FEED).to_a.reject { |filename| filename.start_with?('.') }
    end

    #
    # Process a csv file provided by Belk specifying department email contacts into json
    # Column headers are:
    # Dept Dept_Name FOB Lead PDC APC
    #

    def process_belk_department_emails(input_filepath, output_filepath)
      department_info_by_id = {}
      CSV.foreach(input_filepath, { headers: true, encoding: "bom|utf-8" }) do |row|
        hash = row.to_h
        department_info_by_id[hash['Dept']] = hash.reject { |key, val| key == 'Dept' }.compact
      end
      File.open(output_filepath, 'w') do |file|
        file.write(department_info_by_id.to_json)
      end
    end

    #
    # Generate image metadata for new images on a set of products
    #

    def process_image_metadata_for_products(products)
      # Collect sku, parent, asset info
      sku_by_id = products.map do |sku|
        # The to_unsafe_h gets rid of the weird ActionController::Parameters, which was also sneaking into the database
        if sku.is_a?(Hash)
          [sku['salsify:id'], sku]
        else
          [sku['salsify:id'], sku.to_unsafe_h]
        end
      end.to_h

      sku_parent_ids = sku_by_id.values.map { |sku| sku['salsify:parent_id'] }.compact.uniq
      parent_by_id = {}
      unless sku_parent_ids.empty?
        parent_by_id = sku_parent_ids.each_slice(100).map do |parent_id_batch|
          client.products(parent_id_batch).map do |parent|
            # to_h here to avoid the hashie issue, which was also sneaking into the database
            [parent['salsify:id'], parent.to_h]
          end.to_h
        end.reduce({}, :merge)
      end

      asset_ids_by_sku_id = products.map do |sku|
        [sku['salsify:id'], sku.select do |key, value|
          key.downcase.include?('imagepath')
        end.values.flatten.uniq]
      end.to_h

      # For each sku, check its assets to see if the
      # vendorNumStyleNum_colorCode key is not in its image_metadata.
      # If not, add it to the metadata
      flagged_colors_by_parent_id = {}
      count = 0
      #asset_ids_by_sku_id.each do |sku_id, asset_ids|
      Parallel.each(asset_ids_by_sku_id, in_threads: 4) do |sku_id, asset_ids|
        count += 1
        sku = sku_by_id[sku_id]
        sku_color = sku[PROPERTY_COLOR_CODE]
        parent = parent_by_id[sku['salsify:parent_id']]

        # Must either have parent product or be a group product.
        # Group products have no parents/children and use a group #.
        next unless parent || sku[PROPERTY_GROUP_ORIN]

        parent_id = parent ? parent['salsify:id'] : sku_id
        next if flagged_colors_by_parent_id[parent_id] &&
          flagged_colors_by_parent_id[parent_id].include?(sku_color)

        flagged_colors_by_parent_id[parent_id] = [] unless flagged_colors_by_parent_id[parent_id]
        flagged_colors_by_parent_id[parent_id] << sku_color

        puts "$RRD$ Processing image metadata on #{sku_id} (#{count}/#{asset_ids_by_sku_id.length})" if count % 50 == 0

        # Key of the image metadata hash is (parentID + '_' + colorCode).
        # Or use sku ID for grouping products as they don't have parents.
        key = parent ? "#{parent_id}_#{sku_color}" : "#{sku_id}_000"

        asset_ids.each do |asset_id|
          begin
            asset = client.asset(asset_id)
            if [nil, ''].include?(asset[PROPERTY_IMAGE_METADATA])
              image_metadata = {}
            else
              image_metadata = JSON.parse(asset[PROPERTY_IMAGE_METADATA])
            end

            unless image_metadata[key]
              shot_type = find_shot_type(sku, asset)
              file_type = asset['salsify:format']
              next unless shot_type
              begin
                image_metadata[key] = {
                  'filename' => image_filename(parent, sku, shot_type, file_type),
                  'sent_to_rrd' => false,
                  'rrd_image_id' => generate_image_id(asset_id)
                }
              rescue ActiveRecord::RecordNotUnique => e
                sleep 1
                retry
              end
              client.update_asset(asset_id, {
                PROPERTY_IMAGE_METADATA => image_metadata.to_json
              })
            end
          rescue JSON::ParserError => e
            puts "$RRD$ Error while generating metadata: #{e.message}\n#{e.backtrace}"
          end
        end

        # Mark parent for workflow
        if parent
          client.update_product(
            parent['salsify:id'],
            { PROPERTY_SKU_IMAGES_UPDATED => true }
          )
        end
      end
    end

    def find_shot_type(sku, asset)
      prop_value_pair = sku.find do |key, value|
        (value.is_a?(String) && value == asset['salsify:id']) ||
        (value.is_a?(Array) && value.include?(asset['salsify:id']))
      end
      return nil unless prop_value_pair
      match = prop_value_pair.first.match(/^.+-\ (.+)\ -.+$/)
      return nil unless match
      match[1]
    end

    def image_filename(parent, sku, shot_type, file_type)
      if [nil, ''].include?(sku[PROPERTY_COLOR_CODE])
        "#{sku['salsify:id'][0..6]}_#{sku[PROPERTY_GROUP_ORIN]}_#{shot_type}_000.#{file_type}"
      else
        "#{parent['salsify:id'][0..6]}_" +
        "#{parent['salsify:id'][7..-1]}_" +
        "#{shot_type.strip}_" +
        "#{sku[PROPERTY_COLOR_CODE].strip}.#{file_type}"
      end
    end

    def generate_image_id(salsify_asset_id)
      img_id = RrdImageId.find_by(salsify_asset_id: salsify_asset_id)
      img_id = RrdImageId.new unless img_id
      img_id.salsify_asset_id = salsify_asset_id
      img_id.approved = false
      img_id.save!
      img_id.id
    end

    def process_image_metadata_for_products_with_assets
      process_image_metadata_for_products(products_with_assets)
    end

    def process_image_metadata_for_product_ids(product_ids)
      products = product_ids.each_slice(100).map do |product_id_batch|
        client.products(product_id_batch)
      end.flatten.reject { |h| h.empty? }
      process_image_metadata_for_products(products)
    end

    def products_with_assets
      @products_with_assets ||= begin
        response = client.create_export_run({
          "configuration": {
            "entity_type": 'product',
            "format": "json",
            "filter": "=list:#{products_with_assets_list_id}"
          }
        })
        completed_response = Salsify::Utils::Export.wait_until_complete(client, response).url
        JSON.parse(open(completed_response).read).find do |item|
          item.is_a?(Hash) && item.keys.include?('products')
        end['products']
      end
    end

    def identify_assets_with_invalid_rrd_id
      results = []
      Parallel.each(assets_with_metadata, in_threads: 1) do |asset|
        #next unless asset['image_metadata']
        metadata = JSON.parse(asset['image_metadata'])
        invalid_rrd_ids = metadata.values.each do |md_hash|
          img_id = RrdImageId.find_by(id: md_hash['rrd_image_id'].to_i)
          if img_id.nil?
            # results << {
            #   'case' => 'rrd img id not in database',
            #   'salsify_asset_id' => asset['salsify:id'],
            #   'rrd_image_id' => md_hash['rrd_image_id']
            # }
          elsif img_id.salsify_asset_id != asset['salsify:id']
            real_img_id = RrdImageId.find_by(salsify_asset_id: asset['salsify:id'])
            results << {
              'case' => 'rrd img id points to wrong asset id',
              'salsify_asset_id' => asset['salsify:id'],
              'rrd_image_id' => img_id.id,
              'rrd_image_id approved?' => img_id.approved,
              'rrd_image_ids asset id' => img_id.salsify_asset_id,
              'real rrd_image_id' => (real_img_id ? real_img_id.id : nil),
              'real rrd_image_id approved?' => (real_img_id ? real_img_id.approved : nil)
            }
          end
        end
      end
      filepath = 'belk_invalid_rrd_img_id_analysis.csv'
      CSV.open(filepath, 'w') do |csv|
        csv << ['Situation', 'Salsify Asset ID', 'RRD Image ID', 'RRD Image ID Approved', 'Salsify Asset ID pointed to by RRD Image ID', 'Correct RRD Image ID', 'Correct RRD Image ID Approved']
        results.each do |result|
          csv << [result['case'], result['salsify_asset_id'], result['rrd_image_id'], result['rrd_image_id approved?'], result['rrd_image_ids asset id'], result['real rrd_image_id'], result['real rrd_image_id approved?']]
        end
      end
      FTP::Wrapper.new.upload(filepath, filepath)
    end

    def self.adjust_image_metadata_from_csv
      new.adjust_image_metadata_from_csv
    end

    def adjust_image_metadata_from_csv
      asset_info = {}
      CSV.foreach('belk_invalid_rrd_img_id_analysis.csv', headers: true) do |row|
        asset_info[row['Salsify Asset ID']] ||= []
        asset_info[row['Salsify Asset ID']] << row.to_h
      end
      metadata_by_asset_id = {}
      CSV.open('belk_rrd_img_id_replacement.csv', 'w') do |csv|
        csv << ['Salsify Asset ID', 'image_metadata']
        assets_with_metadata.each do |asset|
          info = asset_info[asset['salsify:id']]
          next unless info
          metadata = JSON.parse(asset['image_metadata'])
          metadata.each do |key, hash|
            correct_img_id_info = info.find { |h| h['RRD Image ID'] == hash['rrd_image_id'].to_s }
            if correct_img_id_info
              metadata[key]['rrd_image_id'] = correct_img_id_info['Correct RRD Image ID'].to_i
            end
          end
          csv << [asset['salsify:id'], metadata.to_json]
          metadata_by_asset_id[asset['salsify:id']] = metadata.to_json
        end
      end
      binding.pry
      count = 0
      Parallel.each(metadata_by_asset_id, in_threads: 8) do |asset_id, metadata_json|
      #metadata_by_asset_id.each do |asset_id, metadata_json|
        client.update_asset(asset_id, { PROPERTY_IMAGE_METADATA => metadata_json })
        count += 1
        puts "#{count}/#{metadata_by_asset_id.length}" if count % 100 == 0
      end
    end

    def self.identify_products_for_asset_ids
      new.identify_products_for_asset_ids
    end

    def identify_products_for_asset_ids
      asset_ids = []
      CSV.foreach('belk_invalid_rrd_img_id_analysis.csv', headers: true) do |row|
        asset_ids << row['Salsify Asset ID']
      end
      product_ids = []
      Parallel.each(asset_ids, in_threads: 8) do |asset_id|
        attached_product_ids = client.products_on_asset(asset_id)['digital_asset_products'].map { |prod| prod['id'] }
        attached_product_ids.each { |id| product_ids << id }
      end
      binding.pry
    end

    def products_with_assets_list_id
      @products_with_assets_list_id ||= ENV.fetch('PRODUCTS_WITH_ASSETS_LIST_ID')
    end

    def retrieve_assets_with_empty_metadata(page = 1)
      result = client.assets_filtered_by({ PROPERTY_IMAGE_METADATA => '{}' }, page: page)
      assets = result['digital_assets']
      if result['meta']['total_entries'] > (result['meta']['current_page'] * result['meta']['per_page'])
        assets + retrieve_assets_with_empty_metadata(page + 1)
      else
        assets
      end
    end

    #
    # Helpers
    #

    def product_id_property
      @product_id_property ||= lazily_paginate(client: client, resource: :properties).find do |property|
        property['role'] == 'product_id'
      end['id']
    end

    def product_name_property
      @product_name_property ||= lazily_paginate(client: client, resource: :properties).find do |property|
        property['role'] == 'product_name'
      end['id']
    end

    def query_lists(query, entity_type = 'product', page = 1, per_page = 50)
      result = client.lists(entity_type, query: query, page: page, per_page: per_page)
      if (page * per_page) < result['meta']['total_entries']
        result['lists'].concat(query_lists(query, entity_type, page, per_page))
      else
        result['lists']
      end
    end

    def update_list(list_id:, additions: [], removals: [])
      tries = 0
      unless additions.empty? && removals.empty?
        begin
          tries += 1
          client.update_list(
            list_id,
            {
              additions: { member_external_ids: additions },
              removals: { member_external_ids: removals }
            }
          )
        rescue RestClient::Locked => e
          if tries < 4
            sleep 10
            retry
          else
            puts "$RRD$ ERROR while updating list #{list_id}: #{e.message}\n#{e.backtrace.join("\n")}"
          end
        end
      end
    end

    def filter_products(filter_hash: nil, filter_string: nil, selections: nil, per_page: 100, page: 1)
      if selections
        result = client.products_filtered_by(filter_hash, filter: filter_string, selections: selections, per_page: per_page, page: page)
      else
        result = client.products_filtered_by(filter_hash, filter: filter_string, per_page: per_page, page: page)
      end
      if (page * per_page) < result['meta']['total_entries']
        result['products'].concat(filter_products(filter_hash: filter_hash, filter_string: filter_string, selections: selections, per_page: per_page, page: (page + 1)))
      else
        result['products']
      end
    end

    def upload_to_exavault(ftp_path, local_path)
      Net::FTP.open(
        ENV.fetch('SALSIFY_FTP_HOST'),
        ENV.fetch('SALSIFY_SFTP_USERNAME'),
        ENV.fetch('SALSIFY_SFTP_PASSWORD')
      ) do |ftp|
        ftp.putbinaryfile(local_path, ftp_path)
      end
    end

    def with_rrd_ftp
      yield Net::FTP.open(
        ENV.fetch('RRD_FTP_HOST'),
        ENV.fetch('RRD_FTP_USERNAME'),
        ENV.fetch('RRD_FTP_PASSWORD')
      )
    end

    def with_rrd_samples_ftp
      yield Net::FTP.open(
        ENV.fetch('RRD_SAMPLE_FTP_HOST'),
        ENV.fetch('RRD_SAMPLE_FTP_USERNAME'),
        ENV.fetch('RRD_SAMPLE_FTP_PASSWORD')
      )
    end

    def with_belk_hex_sftp
      # module is RRDonnelley because that is the functionality section
      # we are in, but the actual SFTP cases tend to be a Belk server
      yield RRDonnelley::SFTPProxy.new(
        ENV.fetch('BELK_HEX_SFTP_HOST'),
        ENV.fetch('BELK_HEX_SFTP_USER'),
        ENV.fetch('BELK_HEX_SFTP_PASSWORD')
      )
    end

    def with_belk_ads_sftp
      # Use diff ENV vars for hex and ads as Belk may change these so they are not both the same server
      # module is RRDonnelley because that is the functionality section we are in, but the actual SFTP cases tend to be a Belk server
      yield RRDonnelley::SFTPProxy.new(
        ENV.fetch('BELK_ADS_SFTP_HOST'),
        ENV.fetch('BELK_ADS_SFTP_USER'),
        ENV.fetch('BELK_ADS_SFTP_PASSWORD')
      )
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new(
        region: ENV.fetch('AWS_REGION'),
        access_key_id: ENV['AWS_ACCESS_KEY_ID'],
        secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
      )
    end

    def upload_to_s3(key, body)
      s3_client.put_object(
        bucket: mode == :prod ? S3_BUCKET_PROD : S3_BUCKET_TEST,
        key: key,
        body: body
      )
    end

    def strip_non_ascii(text)
      return '' unless text
      text.encode(
        Encoding.find('ASCII'),
        {
          invalid: :replace,
          undef: :replace,
          replace: '',
          universal_newline: true
        }
      )
    end


    # TODO - get temp images
#     RRD temp photo request is a daily scheduled job which will send the photo requests based on the sample request created on that day.
# The sample requests are created via the herokuapp page that louis has created for samples. When the temp photos are available from RRD they need to be downloaded and shown in salsify.
# We don’t have to copy them into belk ftp server. We need to make sure we send the photo request only once per sample request.





  end
end
