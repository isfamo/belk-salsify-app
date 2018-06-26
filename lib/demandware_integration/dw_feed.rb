module Demandware

  class DwFeed

    LOG_INTERVAL_STYLE = 3000.freeze
    LOG_INTERVAL_SKU = 5000.freeze

    attr_reader :mode, :salsify_helper, :options, :product_families, :sequence, :t_start, :since_datetime, :to_datetime, :start_datetime

    def initialize(since_datetime, to_datetime, options)
      @since_datetime = since_datetime
      @start_datetime = DateTime.now.utc.to_datetime
      @mode = ENV.fetch('CARS_ENVIRONMENT') == 'production' ? :prod : :qa
      @salsify_helper = SalsifyHelper.new
      @to_datetime = to_datetime.to_datetime # in case this is class Time
      @options = options
      @t_start = Time.now
      @sequence = (options[:start_seq] || 100).to_i
      set_default_options!
      init_dirs
      clean_xml_dirs
    end

    def self.send_feed(since_datetime:, to_datetime: DateTime.now.utc.to_datetime, options: {})
      new(since_datetime, to_datetime, options).send_feed
    end

    def set_default_options!
      @options[:log_each_product] = false if options[:log_each_product].nil?
      @options[:run_publish_pending_update] = true if options[:run_publish_pending_update].nil?
      @options[:run_sent_to_dw_update] = true if options[:run_sent_to_dw_update].nil?
      @options[:deliver_feed] = true if options[:deliver_feed].nil?
      @options[:send_email_when_done] = true if options[:send_email_when_done].nil?
    end

    def init_dirs
      recursive_init_dir(LOCAL_PATH_UPDATED_PRODUCTS_JSON)
      recursive_init_dir(LOCAL_PATH_DW_FEED_XMLS_DW)
      recursive_init_dir(LOCAL_PATH_DW_FEED_XMLS_CFH)
      recursive_init_dir(LOCAL_PATH_DW_FEED_ZIPS_DW)
      recursive_init_dir(LOCAL_PATH_DW_FEED_ZIPS_CFH)
    end

    def clean_xml_dirs
      FileUtils.rm_rf(Dir.glob("#{LOCAL_PATH_DW_FEED_XMLS_DW}/#{xml_file_prefix_belk}*"))
      FileUtils.rm_rf(Dir.glob("#{LOCAL_PATH_DW_FEED_XMLS_CFH}/#{xml_file_prefix_cfh}*"))
    end

    def send_feed

      if recorded_products_local_filepaths.empty?
        puts "#{stamp} No modified product json files found on S3, done!"
        return
      end

      # Retrieve data dictionary and org attributes in separate threads to save time.
      # When we go to use them later, wait if they're not ready yet.
      Thread.new { dictionary_attributes }
      Thread.new { attributes }

      # Split recorded product change files into batches and write xml
      recorded_products_file_batches.each_with_index do |filepath_batch, index|
        t = Time.now
        puts "#{stamp} Processing BATCH #{index + 1}/#{recorded_products_file_batches.length}, batch contains #{filepath_batch.length} input files"
        reset_memoizations

        # For each batch of dirty products files, generate one or more xmls and keep track of sequence count
        @product_families = filepath_batch.sort.map { |filepath| Oj.load(File.read(filepath)) }.reduce({}, :merge)

        # Build some data structures before entering parallel context
        grouping_ids_by_style_sku_id

        # Generate xml strings (see dw_products method)
        xml_strings = DwXmlGenerator.build_xml(dw_products, { mode: xml_mode })

        # Write xml strings to disk
        if xml_strings
          write_xml_files(xml_strings)
          puts "#{stamp} Wrote #{xml_strings.length} files for input file batch #{filepath_batch}, sequence is now #{sequence}"
        else
          puts "#{stamp} Nothing to send to Demandware for input file batch #{filepath_batch}"
        end
        puts "#{stamp} Finished BATCH #{index + 1}/#{recorded_products_file_batches.length} (#{((Time.now - t) / 60).round(1)} min this batch) (#{((Time.now - t_start) / 60).round(1)} min total)"
      end

      # Write generated xml files to individual .xml.gz files for DW
      dw_zip_paths = filter_dw_zips(write_dw_zips)

      # Write all generated xmls to single tar for CFH
      cfh_tar_path = write_cfh_tar

      # Send generated files to their destinations
      DwTransferHelper.send_dw_packages(dw_zip_paths: dw_zip_paths, cfh_tar_path: cfh_tar_path, xml_mode: xml_mode) if options[:deliver_feed] && !options[:testing]

      update_products_with_pending_flag if options[:run_publish_pending_update] && !options[:testing]
      update_products_with_sent_to_dw_timestamp if options[:run_sent_to_dw_update] && !options[:testing]
      send_feed_done_email(dw_zip_paths) if options[:send_email_when_done] && !options[:testing]
      update_last_dw_feed_timestamp if !options[:testing]
      #archive_input_files if !options[:testing]

      puts "#{stamp} Done sending DW feed! Total duration was #{((Time.now - t_start) / 60).round(1)} minutes"
    rescue Exception => e
      puts "#{stamp} ERROR while generating DW xml: #{e.message}\n#{e.backtrace.join("\n")}"
      send_error_report_email(e) if !options[:testing] && !e.message.include?('SIGTERM')
      set_job_status_failed(e)
    end

    def reset_memoizations
      @dw_products = nil
      @sku_ids_by_style_id = nil
      @updated_products = nil
      @updated_base_products = nil
      @updated_skus = nil
      @updated_grouping_products = nil
      @grouping_ids_by_style_sku_id = nil
    end

    def write_xml_files(xml_strings)
      puts "#{stamp} Writing #{xml_strings.length} xml files"
      seq = sequence # sequence isn't available within the loop
      xml_strings.each do |xml_string|
        dw_filepath = File.join(LOCAL_PATH_DW_FEED_XMLS_DW, xml_file_name_belk(seq))
        cfh_filepath = File.join(LOCAL_PATH_DW_FEED_XMLS_CFH, xml_file_name_cfh(seq))
        File.open(dw_filepath, 'w') { |file| file.write(xml_string) }
        File.open(cfh_filepath, 'w') { |file| file.write(xml_string) }
        seq += 1
      end
      @sequence = seq
    end

    def write_dw_zips
      xml_filenames = Dir.entries(LOCAL_PATH_DW_FEED_XMLS_DW).reject { |path| path.start_with?('.') }
      puts "#{stamp} Writing #{xml_filenames.length} .xml.gz files for DW feed"
      xml_filenames.map do |xml_filename|
        xml_filepath = File.join(LOCAL_PATH_DW_FEED_XMLS_DW, xml_filename)
        dw_zip_path = File.join(LOCAL_PATH_DW_FEED_ZIPS_DW, xml_filename.gsub('.xml', '.xml.gz'))
        Zlib::GzipWriter.open(dw_zip_path) do |gz|
          gz.mtime = File.mtime(xml_filepath)
          gz.orig_name = xml_filename
          gz.write(IO.binread(xml_filepath))
        end
        dw_zip_path
      end
    end

    def filter_dw_zips(filepaths)
      filepaths.reject { |path| path.split('/').last.start_with?('LTD') }
    end

    def write_cfh_tar
      cfh_xml_filepaths = Dir.entries(LOCAL_PATH_DW_FEED_XMLS_CFH).reject { |path| path.start_with?('.') }
      puts "#{stamp} Writing #{cfh_xml_filepaths.length} xmls into single tar for CFH"
      cfh_zip_path = File.join(LOCAL_PATH_DW_FEED_ZIPS_CFH, zip_file_name_cfh)
      File.open(cfh_zip_path, 'w') do |file|
        file.write(Tar.new.gzip(Tar.new.tar(path: LOCAL_PATH_DW_FEED_XMLS_CFH, is_dir: true)).read)
      end
      cfh_zip_path
    end

    def write_xml_files_and_zip(xml_strings)
      puts "#{stamp} Writing #{xml_strings.length} xml files"
      recursive_init_dir(LOCAL_PATH_DW_FEED_XMLS_DW)
      recursive_init_dir(LOCAL_PATH_DW_FEED_XMLS_CFH)
      recursive_init_dir(LOCAL_PATH_DW_FEED_ZIPS_DW)
      recursive_init_dir(LOCAL_PATH_DW_FEED_ZIPS_CFH)
      FileUtils.rm_rf(Dir.glob("#{LOCAL_PATH_DW_FEED_XMLS_DW}/#{xml_file_prefix_belk}*"))
      FileUtils.rm_rf(Dir.glob("#{LOCAL_PATH_DW_FEED_XMLS_CFH}/#{xml_file_prefix_cfh}*"))

      count = (options[:start_seq] || 100).to_i
      xml_filepaths = xml_strings.each_with_index.map do |xml_string, index|
        dw_filepath = File.join(LOCAL_PATH_DW_FEED_XMLS_DW, xml_file_name_belk(count + index))
        cfh_filepath = File.join(LOCAL_PATH_DW_FEED_XMLS_CFH, xml_file_name_cfh(count + index))
        File.open(dw_filepath, 'w') { |file| file.write(xml_string) }
        File.open(cfh_filepath, 'w') { |file| file.write(xml_string) }
        { dw: dw_filepath, cfh: cfh_filepath }
      end
      # Format timestamp as 20170908_182500 in EST
      result = {}

      # Write DW zips
      xml_filepaths.map do |xml_filepath_h|
        xml_file_name = xml_filepath_h[:dw].split('/').last
        dw_zip_path = File.join(LOCAL_PATH_DW_FEED_ZIPS_DW, xml_file_name.gsub('.xml', '.xml.gz'))
        Zlib::GzipWriter.open(dw_zip_path) do |gz|
          gz.mtime = File.mtime(xml_filepath_h[:dw])
          gz.orig_name = xml_file_name
          gz.write(IO.binread(xml_filepath_h[:dw]))
        end
        result[:dw] ||= []
        result[:dw] << dw_zip_path
      end

      cfh_zip_path = File.join(LOCAL_PATH_DW_FEED_ZIPS_CFH, zip_file_name_cfh)
      File.open(cfh_zip_path, 'w') do |file|
        file.write(Tar.new.gzip(Tar.new.tar(path: LOCAL_PATH_DW_FEED_XMLS_CFH, is_dir: true)).read)
      end
      result[:cfh] = [cfh_zip_path]
      result
    end

    # Generate an array of hashes, each of which is
    # a json representation of a demandware xml item
    def dw_products
      @dw_products ||= begin
        # Process updated grouping products
        results = []
        groupings_to_process = updated_grouping_products.select do |updated_grouping_id, grouping_product|
          is_style_complete?(grouping_product)
        end
        unless groupings_to_process.empty?
          puts "#{stamp} Processing #{groupings_to_process.length} updated grouping products"
          groupings_to_process.each do |updated_grouping_id, grouping_product|
            results.concat(process_grouping_product(grouping_product))
          end
        end

        # Process updated base products (styles)
        puts "#{stamp} Processing #{updated_base_products.length} updated base products"
        num_base = updated_base_products.length
        count = 0
        t = Time.now
        Parallel.each(updated_base_products, in_threads: ENV.fetch('DW_NUM_THREADS_LOCAL_PROCESSING').to_i) do |updated_base_id, base_product|
          count += 1
          puts "#{stamp} (#{count}/#{num_base}) updated base products (#{((Time.now - t) / 60).round(1)} mins)" if count % LOG_INTERVAL_STYLE == 0
          next if processed_product_ids[updated_base_id]

          if is_style_complete?(base_product)
            sku_ids = sku_ids_by_style_id[updated_base_id] || []
            sku_by_id = sku_ids.map { |id| [id, product_families[id]] }.to_h.reject { |k, v| v.nil? }
          else
            # Style not ready for web, send style as master to dw but don't send any skus
            sku_by_id = {}
          end

          # Identify any groupings which will be triggered by this base product update and process them.
          # This will automatically remove from the sku_by_id hash any skus in those groupings.
          group_results = process_associated_groupings(base_product, sku_by_id)
          results.concat(group_results['results'])

          # Don't send this base product if it's in certain types of groups and we sent them.
          next if group_results['in_cpg_scg_ssg_group'] || processed_product_ids[updated_base_id]

          # Process the base product update
          results << build_dw_family(base_product, sku_by_id)
        end
        total_secs = Time.now - t
        puts "#{stamp} Finished updated base products in #{((total_secs) / 60).round(1)} mins, #{((total_secs * 1000) / updated_base_products.length).round(1)} ms per product"

        # Process updated skus which haven't yet been
        # processed due to a base/grouping update
        num_skus = updated_skus.length
        count = 0
        t = Time.now
        Parallel.each(
          updated_skus.values.group_by { |sku| sku['salsify:parent_id'] },
          in_threads: ENV.fetch('DW_NUM_THREADS_LOCAL_PROCESSING').to_i
        ) do |style_id, skus|
        #updated_skus.values.group_by { |sku| sku['salsify:parent_id'] }.each do |style_id, skus|
          skus.each do |updated_sku|
            updated_sku_id = updated_sku['salsify:id']
            count += 1
            next if processed_product_ids[updated_sku_id]

            sec_per_unit = (Time.now - t) / count
            remaining_units = num_skus - count
            puts "#{stamp} (#{count}/#{num_skus}) updated skus (#{((Time.now - t) / 60).round(1)} mins so far) (est. #{((sec_per_unit * remaining_units) / 60).round(1)} mins remaining)" if count % LOG_INTERVAL_SKU == 0

            updated_sku_type = salsify_type(updated_sku)
            send_il_override = false
            if updated_sku_type == SALSIFY_TYPE_IL
              # Sku is IL type, send by itself without family
              results << dw_il(updated_sku, { 'parent' => product_families[updated_sku['salsify:parent_id']] })
              processed_product_ids[updated_sku_id] = true
            else
              # Sku is not IL type
              base_product = product_families[updated_sku['salsify:parent_id']]
              if ITEM_STATUS_INACTIVE.include?(updated_sku[PROPERTY_ITEM_STATUS])
                # Sku is deactivated
                if updated_sku[PROPERTY_COLOR_MASTER]
                  if is_sku_complete?(sku: updated_sku)
                    if is_style_complete?(base_product)
                      puts "#{stamp} Complete color master sku #{updated_sku_id} deactivated, style ready for web, send sku alone as offline" if options[:log_each_product]
                      results << dw_sku(updated_sku, {})
                    else
                      puts "#{stamp} Completed color master #{updated_sku_id} deactivated, style not ready for web, don't send" if options[:log_each_product]
                    end
                  else
                    puts "#{stamp} Non-complete color master sku #{updated_sku_id} deactivated, don't send" if options[:log_each_product]
                  end
                else
                  if is_style_complete?(base_product)
                    puts "#{stamp} Non color master #{updated_sku_id} deactivated, style ready for web, send sku alone as offline" if options[:log_each_product]
                    results << dw_sku(updated_sku, {})
                  else
                    puts "#{stamp} Non color master #{updated_sku_id} deactiveated, style not ready for web, don't send" if options[:log_each_product]
                  end
                end
                processed_product_ids[updated_sku_id] = true
              elsif updated_sku[PROPERTY_COLOR_MASTER]
                # Updated sku is not inactive and is color master
                if !is_sku_complete?(sku: updated_sku)
                  if [true, 'true'].include?(updated_sku[PROPERTY_IL_ELIGIBLE])
                    puts "#{stamp} Active color master #{updated_sku_id} was updated but isn't ready for web, but is IL, send as IL" if options[:log_each_product]
                    results << dw_il(updated_sku, { 'il_eligible' => true, 'parent' => base_product })
                    processed_product_ids[updated_sku_id] = true
                  else
                    puts "#{stamp} Active color master #{updated_sku_id} was updated but isn't ready for web, don't send" if options[:log_each_product]
                  end
                  next
                end

                if base_product.nil?
                  puts "#{stamp} WARNING unable to find parent style for updated sku #{updated_sku_id}"
                  next
                end

                # Identify other skus in this product family
                sku_ids = sku_ids_by_style_id[base_product['salsify:id']] || []
                sku_by_id = sku_ids.map { |sku_id| [sku_id, product_families[sku_id]] }.to_h.reject { |k, v| v.nil? }
                # Identify any groupings triggered by this sku update and process them
                group_results = process_associated_groupings(base_product, sku_by_id)
                results.concat(group_results['results'])

                if is_style_complete?(base_product)
                  # Don't send this base product if it's in certain types of groups and we sent them.
                  next if group_results['in_cpg_scg_ssg_group'] && !group_results['results'].empty?
                  # Process the color master sku update
                  results << build_dw_family(base_product, sku_by_id)
                else
                  # Sku is ready for web but parent style is not
                  if [true, 'true'].include?(updated_sku[PROPERTY_IL_ELIGIBLE])
                    # Sku is IL eligible and is ready for web, but has parent which is not ready. Send as IL sku.
                    send_il_override = true
                  else
                    # Sku is ready for web but parent style is not, mark style as pending base publish
                    product_ids_to_mark_publish_pending_true << base_product['salsify:id']
                    processed_product_ids[updated_sku_id] = true
                  end
                end
              else
                # Updated sku is not inactive and not color master, find color master sibling
                sibling_ids = sku_ids_by_style_id[updated_sku['salsify:parent_id']] || []
                color_master_sku_id = sibling_ids.find do |sibling_id|
                  sibling = product_families[sibling_id] || {}
                  sibling[PROPERTY_COLOR_MASTER] && sibling[PROPERTY_NRF_COLOR_CODE] == updated_sku[PROPERTY_NRF_COLOR_CODE]
                end
                color_master_sku = product_families[color_master_sku_id]

                if color_master_sku
                  # Found the color master sibling for this color, check if it's complete
                  if is_sku_complete?(sku: updated_sku, color_master: color_master_sku)
                    if base_product.nil?
                      puts "#{stamp} WARNING unable to find parent style for updated sku #{updated_sku_id}"
                      next
                    end

                    if is_style_complete?(base_product)
                      # Color master is complete and style is ready, publish all complete colors to dw
                      sku_ids = sku_ids_by_style_id[base_product['salsify:id']] || []
                      sku_by_id = sku_ids.map { |id| [id, product_families[id]] }.to_h.reject { |k, v| v.nil? }
                      group_results = process_associated_groupings(base_product, sku_by_id)
                      results.concat(group_results['results'])
                      # Don't send this base product if it's in certain types of groups and we sent them.
                      next if group_results['in_cpg_scg_ssg_group'] && !group_results['results'].empty?
                      results << build_dw_family(base_product, sku_by_id)
                    else
                      # Color master is complete but style isn't ready, mark style as pending base publish
                      processed_product_ids[updated_sku_id] = true
                      if [true, 'true'].include?(updated_sku[PROPERTY_IL_ELIGIBLE])
                        send_il_override = true
                      else
                        product_ids_to_mark_publish_pending_true << base_product['salsify:id']
                      end
                    end
                  else
                    # Color master sku isn't complete, don't send anything for this color
                    processed_product_ids[updated_sku_id] = true
                    send_il_override = true if [true, 'true'].include?(updated_sku[PROPERTY_IL_ELIGIBLE])
                  end
                else
                  # No color master for this style/color!
                  processed_product_ids[updated_sku_id] = true
                  send_il_override = true if [true, 'true'].include?(updated_sku[PROPERTY_IL_ELIGIBLE])
                end
              end
              if send_il_override
                results << dw_il(updated_sku, { 'il_eligible' => true, 'parent' => base_product })
                processed_product_ids[updated_sku_id] = true
              end
            end
          end
        end
        puts "#{stamp} Finished updated skus in #{((Time.now - t) / 60).round(1)} minutes, now running uniq and sort (#{((Time.now - t_start) / 60).round(1)} min total)"

        # Sort demandware products by type, order is important!
        t = Time.now
        result = results.flatten.compact.uniq do |hash|
          hash['meta']['salsify:id']
        end.sort_by do |hash|
          hash['meta']['dw_type']
        end
        puts "#{stamp} Took #{((Time.now - t) / 60).round(1)} minutes to uniq and sort dw_products"
        result
      end
    end

    def process_grouping_product(grouping_product)
      result = []
      sku_by_id = retrieve_skus_for_grouping(grouping_product)
      if [GROUPING_TYPES_CPG].flatten.include?(grouping_product[PROPERTY_GROUPING_TYPE]) &&
        !ITEM_STATUS_INACTIVE.include?(grouping_product[PROPERTY_ITEM_STATUS])
        style_ids = [grouping_product[PROPERTY_CHILD_STYLES_OF_GROUP]].flatten.compact.uniq
        style_ids.each do |style_id|
          style = product_families[style_id]
          next unless style
          result << dw_master(product_hash: style, type: SALSIFY_TYPE_BASE, online_flag_override: 'false')
          processed_product_ids[style_id] = true
        end
      end
      result << build_dw_family(grouping_product, sku_by_id)
      result
    end

    # When processing a product family, find and process
    # any groupings which might be affected by this update
    def process_associated_groupings(product_hash, sku_by_id)
      result = { 'in_cpg_scg_ssg_group' => false, 'results' => [] }
      grouping_ids = [product_hash['salsify:id'], sku_by_id.keys].flatten.map { |id| grouping_ids_by_style_sku_id[id] }.flatten.compact.uniq
      # grouping_products_for_product_ids(
      #   style_ids: [product_hash['salsify:id']],
      #   sku_ids: sku_by_id.keys
      # ).each do |grouping_product_id, grouping_product|
      grouping_ids.each do |grouping_product_id|
        next if processed_product_ids[grouping_product_id]
        grouping_product = product_families[grouping_product_id]
        puts "#{stamp} Processing grouping product #{grouping_product_id}" if options[:log_each_product]
        result['in_cpg_scg_ssg_group'] = true if [GROUPING_TYPES_CPG, GROUPING_TYPES_SCG_SSG].flatten.include?(grouping_product[PROPERTY_GROUPING_TYPE])
        skus_for_group_by_id = retrieve_skus_for_grouping(grouping_product)

        # If associated grouping is CPG and active, send component styles as offline
        if [GROUPING_TYPES_CPG].flatten.include?(grouping_product[PROPERTY_GROUPING_TYPE]) &&
          !ITEM_STATUS_INACTIVE.include?(grouping_product[PROPERTY_ITEM_STATUS])
          style_ids = [grouping_product[PROPERTY_CHILD_STYLES_OF_GROUP]].flatten.compact.uniq
          style_ids.each do |style_id|
            style = product_families[style_id]
            next unless style
            result['results'] << dw_master(product_hash: style, type: SALSIFY_TYPE_BASE, online_flag_override: 'false')
            processed_product_ids[style_id] = true
          end
        end

        if [GROUPING_TYPES_CPG, GROUPING_TYPES_SCG_SSG].flatten.include?(grouping_product[PROPERTY_GROUPING_TYPE])
          # Remove these skus from the base product as they exist under the grouping in demandware
          sku_by_id.reject! { |sku_id, sku| skus_for_group_by_id.any? { |grp_sku_id, grp_sku| grp_sku_id == sku_id } }
        elsif GROUPING_TYPES_COLLECTION.include?(grouping_product[PROPERTY_GROUPING_TYPE])
          # For collections, only include products which have been updated as children in the feed
          included_family_style_ids = skus_for_group_by_id.select do |sku_id, sku|
            style = product_families[sku['salsify:parent_id']]
            DateTime.parse(sku['salsify:updated_at']) > since_datetime ||
            (style && DateTime.parse(style['salsify:updated_at']) > since_datetime)
          end.map { |sku_id, sku| sku['salsify:parent_id'] }.compact.uniq

          skus_for_group_by_id.select! do |sku_id, sku|
            included_family_style_ids.include?(sku['salsify:parent_id'])
          end
        end

        if is_style_complete?(grouping_product)
          result['results'] << build_dw_family(grouping_product, skus_for_group_by_id)
          if [GROUPING_TYPES_CPG].flatten.include?(grouping_product[PROPERTY_GROUPING_TYPE])
            processed_product_ids[product_hash['salsify:id']] = true
          end
        else
          # Grouping not ready, don't send
        end
      end
      result
    end

    def retrieve_skus_for_grouping(grouping_hash)
      puts "#{stamp} Retrieving skus for grouping product #{grouping_hash['salsify:id']}" if options[:log_each_product]
      sku_by_id = {}
      # Retrieve skus from child styles
      if grouping_hash[PROPERTY_CHILD_STYLES_OF_GROUP]
        [grouping_hash[PROPERTY_CHILD_STYLES_OF_GROUP]].flatten.each do |child_style_id|
          sku_ids = sku_ids_by_style_id[child_style_id] || []
          sku_by_id.merge!(sku_ids.map { |sku_id| [sku_id, product_families[sku_id]] }.to_h)
        end
      end

      # Retrieve direct child skus
      if grouping_hash[PROPERTY_CHILD_SKUS_OF_GROUP]
        sku_by_id.merge!(
          [grouping_hash[PROPERTY_CHILD_SKUS_OF_GROUP]].flatten.map { |child_sku_id|
            [child_sku_id, product_families[child_sku_id]]
          }.to_h
        )
      end

      sku_by_id.reject { |k, v| k.nil? || v.nil? }
    end

    def salsify_type(product_hash)
      if [true, 'true', 'True'].include?(product_hash[PROPERTY_IL_ELIGIBLE]) && product_hash['salsify:parent_id'].nil?
        SALSIFY_TYPE_IL
      elsif product_hash['salsify:parent_id']
        SALSIFY_TYPE_SKU
      elsif GROUPING_TYPES_CPG.include?(product_hash[PROPERTY_GROUPING_TYPE])
        SALSIFY_TYPE_GROUP_CPG
      elsif GROUPING_TYPES_SCG_SSG.include?(product_hash[PROPERTY_GROUPING_TYPE])
        SALSIFY_TYPE_GROUP_SCG_SSG
      elsif GROUPING_TYPES_COLLECTION.include?(product_hash[PROPERTY_GROUPING_TYPE])
        SALSIFY_TYPE_GROUP_COLLECTION
      else
        SALSIFY_TYPE_BASE
      end
    end

    # Generate an array of hashes representing demandware xml.
    # product_hash can be the base product, or a grouping.
    # May include or exclude skus based on various conditions.
    def build_dw_family(product_hash, sku_by_id)
      type = salsify_type(product_hash)

      # Identify which skus are ready to publish
      if !sku_by_id.empty?
        complete_color_master_sku_by_id = identify_unprocessed_complete_color_master_skus(sku_by_id)
        complete_sku_by_id = identify_unprocessed_complete_skus(
          sku_by_id,
          complete_color_master_sku_by_id.map { |_, sku|
            [sku[PROPERTY_NRF_COLOR_CODE], sku]
          }.to_h
        )
      else
        complete_color_master_sku_by_id = {}
        complete_sku_by_id = {}
      end

      if product_hash[PROPERTY_GROUPING_TYPE]
        # This is a grouping product
        if is_style_complete?(product_hash)
          if ITEM_STATUS_INACTIVE.include?(product_hash[PROPERTY_ITEM_STATUS])
            # Grouping was deactivated
            if [GROUPING_TYPES_CPG, GROUPING_TYPES_SCG_SSG].flatten.include?(product_hash[PROPERTY_GROUPING_TYPE])
              # Deactivated grouping is CPG/SCG/SSG, send as offline and send child families as regular items
              grouping_id = product_hash['salsify:id'] || product_hash['product_id']
              puts "#{stamp} Grouping product #{grouping_id} was deactivated and is type #{product_hash[PROPERTY_GROUPING_TYPE]}, sending as offline and sending child families as regular items" if options[:log_each_product] && product_hash['salsify:id'] != '1800501PETIT63767R'
              style_ids = complete_color_master_sku_by_id.map { |id, sku| sku['salsify:parent_id'] }.uniq.compact
              complete_color_master_sku_by_id_by_style_id = complete_color_master_sku_by_id.group_by { |sku_id, sku| sku['salsify:parent_id'] }.map { |style_id, arr| [style_id, arr.to_h] }.to_h
              complete_sku_by_id_by_style_id = complete_sku_by_id.group_by { |sku_id, sku| sku['salsify:parent_id'] }
              family = [
                dw_master(product_hash: product_hash, type: type),
                complete_color_master_sku_by_id_by_style_id.map { |style_id, color_master_by_id|
                  style = product_families[style_id]
                  dw_master(product_hash: style, complete_color_master_sku_by_id: color_master_by_id, complete_sku_by_id: complete_sku_by_id_by_style_id[style_id], type: salsify_type(style))
                },
                complete_sku_by_id.map { |sku_id, sku|
                  style = product_families[sku['salsify:parent_id']]
                  complete_color_master_by_id = complete_color_master_sku_by_id_by_style_id[sku['salsify:parent_id']] || {}
                  dw_sku(
                    sku,
                    complete_color_master_by_id.values.find { |color_master|
                      color_master[PROPERTY_NRF_COLOR_CODE] == sku[PROPERTY_NRF_COLOR_CODE]
                    },
                    { 'parent' => style, 'parent_type' => salsify_type(style) }
                  )
                }
              ].flatten

              # Mark these families as processed so we don't add them again
              [product_hash['salsify:id'], complete_sku_by_id.keys].flatten.each { |id| processed_product_ids[id] = true }
              # Mark the style as no longer pending base publish
              product_ids_to_mark_publish_pending_false << product_hash['salsify:id']
              family
            else
              # Deactivated grouping is RCG/BCG/GSG collection, just send as offline
              grouping_id = product_hash['salsify:id'] || product_hash['product_id']
              puts "#{stamp} Grouping product #{grouping_id} was deactivated and is type #{product_hash[PROPERTY_GROUPING_TYPE]}, sending alone as offline" if options[:log_each_product]
              family = [dw_master(product_hash: product_hash, type: type, online_flag_override: 'false')]
              processed_product_ids[grouping_id] = true
              family
            end
          else
            grouping_id = product_hash['salsify:id'] || product_hash['product_id']
            puts "#{stamp} Grouping product #{grouping_id} is ready for web, sending with skus" if options[:log_each_product]
            if GROUPING_TYPES_COLLECTION.include?(product_hash[PROPERTY_GROUPING_TYPE])
              child_style_ids = [product_hash[PROPERTY_CHILD_STYLES_OF_GROUP]].flatten.compact.uniq
              child_sku_ids = [product_hash[PROPERTY_CHILD_SKUS_OF_GROUP]].flatten.compact.uniq

              child_skus = child_sku_ids.map { |id| product_families[id] }.compact
              complete_sku_by_id = child_skus.map do |child_sku|
                if child_sku[PROPERTY_COLOR_MASTER]
                  color_master = child_sku
                else
                  color_master = child_skus.find { |sib| sib[PROPERTY_COLOR_MASTER] && sib[PROPERTY_NRF_COLOR_CODE] == child_sku[PROPERTY_NRF_COLOR_CODE] }
                end
                next unless is_sku_complete?(sku: child_sku, color_master: color_master)
                [child_sku['salsify:id'], child_sku]
              end.compact.to_h

              complete_color_master_sku_by_id = complete_sku_by_id.select { |id, sku| sku[PROPERTY_COLOR_MASTER] }

              family = [
                dw_master(
                  product_hash: product_hash,
                  complete_sku_by_id: complete_sku_by_id,
                  complete_color_master_sku_by_id: complete_color_master_sku_by_id,
                  type: type
                )
              ]

              # Add child styles of collection
              child_style_ids.each { |style_id|
                style = product_families[style_id]
                next unless style

                # Identify children of style, which is a child of product_hash grouping,
                # but may itself be a grouping product
                if GROUPING_TYPES_CPG.include?(style[PROPERTY_GROUPING_TYPE])
                  style_ids = [style[PROPERTY_CHILD_STYLES_OF_GROUP]].flatten.compact
                  sku_ids = style_ids.map { |style_id| sku_ids_by_style_id[style_id] }.flatten.compact
                  style_type = SALSIFY_TYPE_GROUP_CPG
                else
                  sku_ids = sku_ids_by_style_id[style['salsify:id']] || []
                  style_type = SALSIFY_TYPE_BASE
                end

                skus = sku_ids.map { |sku_id| product_families[sku_id] }
                color_master_by_sku_id = skus.map do |sku|
                  color_master = sku[PROPERTY_COLOR_MASTER] ? sku : skus.find { |sib| sib[PROPERTY_COLOR_MASTER] && sib[PROPERTY_NRF_COLOR_CODE] == sku[PROPERTY_NRF_COLOR_CODE] }
                  [sku['salsify:id'], color_master]
                end.to_h
                style_complete_sku_by_id = skus.select do |sku|
                  is_sku_complete?(sku: sku, color_master: color_master_by_sku_id[sku['salsify:id']])
                end.map { |sku| [sku['salsify:id'], sku] }.to_h

                # We're looking at this style and its skus because it's part of a collection
                # which was updated or triggered, don't process it unless necessary
                next unless DateTime.parse(style['salsify:updated_at']) > since_datetime ||
                            skus.any? { |sku| DateTime.parse(sku['salsify:updated_at']) > since_datetime }

                processed_product_ids[style['salsify:id']] = true
                family << dw_master(
                  product_hash: style,
                  complete_sku_by_id: style_complete_sku_by_id,
                  complete_color_master_sku_by_id: style_complete_sku_by_id.select { |id, sku| sku[PROPERTY_COLOR_MASTER] },
                  type: style_type
                )

                if style_type == SALSIFY_TYPE_GROUP_CPG
                  # Add children of this grouping as well
                  style_complete_sku_by_id.each do |sku_id, sku|
                    family << dw_sku(sku, color_master_by_sku_id[sku_id], { 'parent' => style, 'parent_type' => SALSIFY_TYPE_GROUP_CPG })
                    processed_product_ids[sku_id] = true
                  end
                end
              }

              # Add child skus of collection and their families
              child_sku_ids.map { |sku_id|
                sku = product_families[sku_id]
                next unless sku && !processed_product_ids[sku_id] && DateTime.parse(sku['salsify:updated_at']) > since_datetime
                style = product_families[sku['salsify:parent_id']]
                sibling_ids = sku_ids_by_style_id[sku['salsify:parent_id']]
                siblings = sibling_ids ? sibling_ids.map { |id| product_families[id] } : []
                siblings.concat([sku])
                if style
                  sub_complete_sku_by_id = siblings.map do |child_sku|
                    if child_sku[PROPERTY_COLOR_MASTER]
                      color_master = child_sku
                    else
                      color_master = siblings.find { |sib| sib[PROPERTY_COLOR_MASTER] && sib[PROPERTY_NRF_COLOR_CODE] == child_sku[PROPERTY_NRF_COLOR_CODE] }
                    end
                    next unless is_sku_complete?(sku: child_sku, color_master: color_master)
                    [child_sku['salsify:id'], child_sku]
                  end.compact.to_h
                  sub_complete_color_master_by_id = sub_complete_sku_by_id.select { |id, sku| sku[PROPERTY_COLOR_MASTER] }
                  if !processed_product_ids[style['salsify:id']]
                    family << dw_master(product_hash: style, complete_color_master_sku_by_id: sub_complete_color_master_by_id, complete_sku_by_id: sub_complete_sku_by_id, type: salsify_type(style))
                    processed_product_ids[style['salsify:id']] = true
                  end
                  family.concat(sub_complete_sku_by_id.map { |sku_id, sku|
                    color_master_sibling = sub_complete_color_master_by_id.values.find { |color_master|
                      color_master[PROPERTY_NRF_COLOR_CODE] == sku[PROPERTY_NRF_COLOR_CODE]
                    }
                    processed_product_ids[sku_id] = true
                    dw_sku(sku, color_master_sibling, { 'parent' => style, 'parent_type' => salsify_type(style) })
                  })
                else
                  processed_product_ids[sku['salsify:id']] = true
                  dw_sku(sku, sku)
                end
              }.flatten.each { |item| family << item }
            else
              send_skus = product_hash[PROPERTY_PENDING_BASE_PUBLISH] || complete_sku_by_id.any? { |sku_id, sku|
                updated_skus[sku_id] || updated_base_products[sku['salsify:parent_id']]
              }
              family = [dw_master(product_hash: product_hash, complete_color_master_sku_by_id: complete_color_master_sku_by_id, complete_sku_by_id: complete_sku_by_id, type: type)]
              if send_skus
                family.concat(complete_sku_by_id.map { |sku_id, sku|
                  color_master_sibling = complete_color_master_sku_by_id.values.find { |color_master|
                    color_master[PROPERTY_NRF_COLOR_CODE] == sku[PROPERTY_NRF_COLOR_CODE]
                  }
                  dw_sku(sku, color_master_sibling, { 'parent' => product_hash, 'parent_type' => type })
                })
              end
            end

            # Mark this product and these skus as processed so we don't process them again
            # (e.g. don't include skus for their parent if already included for a grouping of type CPG/SCG/SSG)
            if [GROUPING_TYPES_CPG, GROUPING_TYPES_SCG_SSG].flatten.include?(product_hash[PROPERTY_GROUPING_TYPE])
              [product_hash['salsify:id'], complete_sku_by_id.keys].flatten.each { |id| processed_product_ids[id] = true }
            end

            # Mark the style as no longer pending base publish
            product_ids_to_mark_publish_pending_false << product_hash['salsify:id']

            family
          end
        else
          grouping_id = product_hash['salsify:id'] || product_hash['product_id']
          puts "#{stamp} Grouping product #{grouping_id} is not ready for web, don't send" if options[:log_each_product] && product_hash['salsify:id'] != '1800501PETIT63767R'
        end
      else
        # This is a regular base product
        if !is_style_complete?(product_hash)
          if DateTime.parse(product_hash['salsify:updated_at']) > since_datetime
            # Style was updated, perhaps skus as well
            if ITEM_STATUS_INACTIVE.include?(product_hash[PROPERTY_ITEM_STATUS])
              puts "#{stamp} Style #{product_hash['salsify:id']} was updated and is inactive, but is not ready for web, so don't send" if options[:log_each_product]
              processed_product_ids[product_hash['salsify:id']] = true
              []
            elsif product_hash[PROPERTY_SENT_TO_DW_TIMESTAMP]
              puts "#{stamp} Style #{product_hash['salsify:id']} was updated but isn't ready for web, and was already sent to DW, not sending" if options[:log_each_product]
              processed_product_ids[product_hash['salsify:id']] = true
              []
            else
              puts "#{stamp} Style #{product_hash['salsify:id']} was updated but isn't ready for web, and hasn't been sent to DW, sending as offline with no skus" if options[:log_each_product]
              family = [dw_master(product_hash: product_hash, type: type)]
              [product_hash['salsify:id'], sku_by_id.keys].flatten.each { |id| processed_product_ids[id] = true }
              family
            end
          else
            # Style was not updated, skus were
            puts "#{stamp} Style #{product_hash['salsify:id']} not ready for web when skus were updated, marking style pending" if options[:log_each_product]
            [product_hash['salsify:id'], sku_by_id.keys].flatten.each { |id| processed_product_ids[id] = true }
            []
          end
        else
          # Style is ready for web
          if ITEM_STATUS_INACTIVE.include?(product_hash[PROPERTY_ITEM_STATUS])
            puts "#{stamp} Style #{product_hash['salsify:id']} has been deactivated and is ready for web, sending with no skus" if options[:log_each_product]
            family = [dw_master(product_hash: product_hash, type: type)]
            [product_hash['salsify:id'], sku_by_id.keys].flatten.each { |id| processed_product_ids[id] = true }
            family
          elsif complete_color_master_sku_by_id.empty?
            if DateTime.parse(product_hash['salsify:updated_at']) > since_datetime
              puts "#{stamp} Style #{product_hash['salsify:id']} was updated and is ready for web, but has no ready skus, sending only style" if options[:log_each_product]
              family = [dw_master(product_hash: product_hash, type: type)]
              [product_hash['salsify:id'], sku_by_id.keys].flatten.each { |id| processed_product_ids[id] = true }
              family
            else
              puts "#{stamp} Style #{product_hash['salsify:id']} had sku(s) updated and is ready for web, but has no complete colors, not sending" if options[:log_each_product]
              [product_hash['salsify:id'], sku_by_id.keys].flatten.each { |id| processed_product_ids[id] = true }
              []
            end
          elsif product_hash[PROPERTY_PENDING_BASE_PUBLISH] ||
            sku_by_id.any? { |sku_id, sku| DateTime.parse(sku['salsify:updated_at']) > since_datetime }
            puts "#{stamp} Style #{product_hash['salsify:id']} is pending base publish, or sku was updated, sending style with skus" if options[:log_each_product]
            family = [
              dw_master(product_hash: product_hash, complete_color_master_sku_by_id: complete_color_master_sku_by_id, complete_sku_by_id: complete_sku_by_id, type: type),
              complete_sku_by_id.map { |sku_id, sku|
                dw_sku(
                  sku,
                  complete_color_master_sku_by_id.values.find { |color_master|
                    color_master[PROPERTY_NRF_COLOR_CODE] == sku[PROPERTY_NRF_COLOR_CODE]
                  },
                  { 'parent' => product_hash, 'parent_type' => type }
                )
              }
            ].flatten

            # Mark this product and these skus as processed so we don't process them again
            # (e.g. don't include skus for their parent if already included for a grouping)
            [product_hash['salsify:id'], complete_sku_by_id.keys].flatten.each { |id| processed_product_ids[id] = true }

            # Mark the style as no longer pending base publish
            product_ids_to_mark_publish_pending_false << product_hash['salsify:id']

            family
          else
            # Style is not pending base publish, don't send skus, only style
            puts "#{stamp} Style #{product_hash['salsify:id']} is ready for web but not pending base publish, sending only style" if options[:log_each_product]
            family = [dw_master(product_hash: product_hash, type: type)]
            [product_hash['salsify:id'], sku_by_id.keys].flatten.each { |id| processed_product_ids[id] = true }
            family
          end
        end
      end
    end

    def identify_unprocessed_complete_color_master_skus(sku_by_id)
      sku_by_id.select do |sku_id, sku|
        sku[PROPERTY_COLOR_MASTER] &&
        is_sku_complete?(sku: sku) &&
        !processed_product_ids[sku_id]
      end
    end

    def identify_unprocessed_complete_skus(sku_by_id, complete_color_master_by_color)
      sku_by_id.select do |sku_id, sku|
        color_master = complete_color_master_by_color[sku[PROPERTY_NRF_COLOR_CODE]]
        #complete_colors.include?(sku[PROPERTY_NRF_COLOR_CODE]) && NOTE: uncomment this to include non-masters as long as the master sibling is ready
        is_sku_complete?(sku: sku, color_master: color_master) && # NOTE: this requires the non-master itself to be ready, beyond just the master sibling
        !processed_product_ids[sku_id]
      end
    end

    def dw_master(product_hash:, complete_color_master_sku_by_id: {}, complete_sku_by_id: {}, type:, online_flag_override: nil)
      # Generate a json representation of the xml
      result = {
        'meta' => {
          'dw_type' => DW_TYPE_MASTER,
          'salsify:id' => product_hash['salsify:id'],
          'group_type' => product_hash[PROPERTY_GROUPING_TYPE]
        },
        'product' => {
          'xml-attribute:product-id' => product_hash['salsify:id'].strip,
          'upc' => nil,
          'long-description' => long_description(product_hash[PROPERTY_PRODUCT_COPY_TEXT]),
          'online-flag' => (online_flag_override ? online_flag_override : online_flag(product_hash: product_hash, type: type)),
          'searchable-flag' => (online_flag_override ? online_flag_override : online_flag(product_hash: product_hash, type: type)),
          'tax-class-id' => DEFAULT_TAX_CLASS_FOR_MASTER,
          'sitemap-included-flag' => sitemap_included_flag(product_hash, type),
          'custom-attributes' => {
            'custom-attribute' => [
              # Calculated custom attributes added here, the rest added
              # below in add_configured_properties_to_product!
              custom_attribute_is_master
            ]
          }
        }
      }

      if GROUPING_TYPES_COLLECTION.include?(product_hash[PROPERTY_GROUPING_TYPE])
        result['product']['images'] = {
          'image-group' => image_groups_for_collection(product_hash)
        }
      elsif !complete_color_master_sku_by_id.empty?
        result['product']['images'] = {
          'image-group' => image_groups_for_product(
            product_hash: product_hash,
            type: type,
            complete_color_master_sku_by_id: complete_color_master_sku_by_id
          )
        }
      end

      if [SALSIFY_TYPE_BASE, SALSIFY_TYPE_GROUP_CPG, SALSIFY_TYPE_GROUP_SCG_SSG].include?(type) && !complete_sku_by_id.empty?
        result['product']['variations'] = {
          'attributes' => {
            'variation-attribute' => [
              variation_attribute_color(
                product_hash: product_hash,
                type: type,
                complete_color_master_sku_by_id: complete_color_master_sku_by_id
              ),
              variation_attribute_size(
                product_hash: product_hash,
                type: type,
                complete_sku_by_id: complete_sku_by_id
              )
            ]
          },
          'variants' => {
            'variant' => variants_for_product(
              product_hash: product_hash,
              type: type,
              complete_sku_by_id: complete_sku_by_id
            )
          }
        }
      elsif type == SALSIFY_TYPE_GROUP_COLLECTION
        result['product']['product-set-products'] = {
          'product-set-product' => product_set_products(grouping_product: product_hash, included_sku_by_id: complete_sku_by_id)
        }
      end

      # Add type-specific items
      if type == SALSIFY_TYPE_GROUP_CPG
        result['product']['custom-attributes']['custom-attribute'] << custom_attribute_cpg_size(product_hash)
      end

      # Add extra configured data-driven properties
      add_configured_properties_to_product!(xml_hash: result, product_hash: product_hash, type: 'master')
      add_iph_levels!(result, product_hash)
      add_category_specific_attributes!(result, product_hash)
      final_master_override!(result, product_hash)
      result
    end

    def dw_sku(sku_hash, color_master_sibling, sku_options = {})
      is_online = online_flag(product_hash: sku_hash, type: SALSIFY_TYPE_SKU, color_master_sku: color_master_sibling)
      if is_online
        result = {
          'meta' => {
            'dw_type' => DW_TYPE_SKU,
            'parent_type' => sku_options['parent_type'],
            'salsify:id' => sku_hash['salsify:id']
          },
          'product' => {
            'xml-attribute:product-id' => sku_hash['salsify:id'].strip,
            'upc' => sku_hash[PROPERTY_UPC],
            'step-quantity' => DEFAULT_STEP_QUANTITY_FOR_SKU,
            'display-name' => '',
            'long-description' => '',
            'online-flag' => true,
            'searchable-flag' => true,
            'tax-class-id' => DEFAULT_TAX_CLASS_FOR_SKU,
            'custom-attributes' => {
              'custom-attribute' => [
                # Calculated custom attributes added here, the rest added
                # below in add_configured_properties_to_product!
                custom_attribute_size(sku_hash),
                custom_attribute_color(sku_hash, sku_options['parent_type'], sku_options['parent'])
              ]
            }
          }
        }
        add_configured_properties_to_product!(xml_hash: result, product_hash: sku_hash, type: SALSIFY_TYPE_SKU, parent_hash: sku_options['parent'])
      else
        result = {
          'meta' => {
            'dw_type' => DW_TYPE_SKU,
            'parent_type' => sku_options['parent_type'],
            'salsify:id' => sku_hash['salsify:id']
          },
          'product' => {
            'xml-attribute:product-id' => sku_hash['salsify:id'].strip,
            'online-flag' => false
          }
        }
      end
      final_sku_override!(result, sku_hash, color_master_sibling)
      result
    end

    def dw_il(sku_hash, sku_options = {})
      is_online = online_flag(product_hash: sku_hash, type: SALSIFY_TYPE_IL)
      if is_online
        result = {
          'meta' => {
            'dw_type' => DW_TYPE_IL,
            'salsify:id' => sku_hash['salsify:id']
          },
          'product' => {
            'xml-attribute:product-id' => sku_hash['salsify:id'].strip,
            'upc' => sku_hash[PROPERTY_UPC],
            'step-quantity' => DEFAULT_STEP_QUANTITY_FOR_SKU,
            'online-flag' => true,
            'searchable-flag' => true,
            'tax-class-id' => DEFAULT_TAX_CLASS_FOR_SKU,
            'custom-attributes' => {
              'custom-attribute' => [
                # Calculated custom attributes added here, the rest added
                # below in add_configured_properties_to_product!

              ]
            }
          }
        }
        add_configured_properties_to_product!(xml_hash: result, product_hash: sku_hash, type: SALSIFY_TYPE_IL, parent_hash: sku_options['parent'])
      else
        result = {
          'meta' => {
            'dw_type' => DW_TYPE_IL,
            'salsify:id' => sku_hash['salsify:id']
          },
          'product' => {
            'xml-attribute:product-id' => sku_hash['salsify:id'].strip,
            'upc' => sku_hash[PROPERTY_UPC],
            'online-flag' => false
          }
        }
      end
      inject_il_eligible!(result, sku_options['il_eligible']) if !sku_options['il_eligible'].nil?
      result
    end

    def inject_il_eligible!(xml_hash, value)
      xml_hash['product'] ||= {}
      xml_hash['product']['custom-attributes'] ||= {}
      xml_hash['product']['custom-attributes']['custom-attribute'] ||= []
      il_custom_attr = xml_hash['product']['custom-attributes']['custom-attribute'].find { |ca| ca['xml-attribute:attribute-id'] == 'il_eligible' }
      if il_custom_attr
        il_custom_attr['xml-value'] = [true, 'true'].include?(value)
      else
        xml_hash['product']['custom-attributes']['custom-attribute'] << { 'xml-attribute:attribute-id' => 'il_eligible', 'xml-value' => [true, 'true'].include?(value) }
      end
    end

    def online_flag(product_hash:, type:, color_master_sku: nil)
      if [SALSIFY_TYPE_BASE].include?(type)
        sku_ids = sku_ids_by_style_id[product_hash['salsify:id']] || []
        child_sku_by_id = sku_ids.map { |id| [id, product_families[id]] }.to_h
        !ITEM_STATUS_INACTIVE.include?(product_hash[PROPERTY_ITEM_STATUS]) &&
        is_style_complete?(product_hash) &&
        child_sku_by_id.any? { |sku_id, sku|
          color_master = child_sku_by_id.find { |sibling_id, sibling|
            sibling[PROPERTY_NRF_COLOR_CODE] == sku[PROPERTY_NRF_COLOR_CODE] &&
            sibling[PROPERTY_COLOR_MASTER]
          }
          color_master = color_master.last if color_master
          is_sku_complete?(sku: sku, color_master: color_master)
        }
      elsif [SALSIFY_TYPE_GROUP_CPG].include?(type)
        # Grouping is CPG with child styles. Mark as online if it's active, complete, and any of its child styles have at least one ready sku.
        child_style_ids = [product_hash[PROPERTY_CHILD_STYLES_OF_GROUP]].flatten.compact.uniq
        !ITEM_STATUS_INACTIVE.include?(product_hash[PROPERTY_ITEM_STATUS]) &&
        is_style_complete?(product_hash) &&
        child_style_ids.any? { |child_style_id|
          child_style = product_families[child_style_id]
          next unless child_style
          sku_ids = sku_ids_by_style_id[child_style_id]
          next unless sku_ids
          skus_by_color = sku_ids.map { |id| product_families[id] }.compact.group_by { |sku| sku[PROPERTY_NRF_COLOR_CODE] }
          skus_by_color.any? { |color, skus|
            skus.any? { |sku|
              if sku[PROPERTY_COLOR_MASTER]
                is_sku_complete?(sku: sku)
              else
                is_sku_complete?(sku: sku, color_master: skus_by_color[color].find { |sib| sib[PROPERTY_COLOR_MASTER] })
              end
            }
          }
        }
      elsif [SALSIFY_TYPE_GROUP_SCG_SSG, SALSIFY_TYPE_GROUP_COLLECTION].include?(type)
        child_style_ids = [product_hash[PROPERTY_CHILD_STYLES_OF_GROUP]].flatten.compact
        child_sku_ids = [product_hash[PROPERTY_CHILD_SKUS_OF_GROUP]].flatten.compact
        !ITEM_STATUS_INACTIVE.include?(product_hash[PROPERTY_ITEM_STATUS]) &&
        is_style_complete?(product_hash) &&
        (
          child_style_ids.empty? || child_style_ids.any? { |child_style_id|
            child_style = product_families[child_style_id]
            child_style ? is_style_complete?(child_style) : false
          }
        ) &&
        (
          child_sku_ids.empty? || child_sku_ids.any? { |child_sku_id|
            child_sku = product_families[child_sku_id]
            if child_sku
              sibling_ids = sku_ids_by_style_id[child_sku['salsify:parent_id']]
              if sibling_ids
                color_master_id = sibling_ids.find { |sib_id|
                  sib = product_families[sib_id]
                  sib[PROPERTY_COLOR_MASTER] && sib[PROPERTY_NRF_COLOR_CODE] == child_sku[PROPERTY_NRF_COLOR_CODE]
                }
                color_master = product_families[color_master_id]
                child_sku && is_sku_complete?(sku: child_sku, color_master: color_master ? color_master : child_sku)
              end
            end
          }
        ) &&
        (!child_style_ids.empty? || !child_sku_ids.empty?)
      elsif type == SALSIFY_TYPE_SKU
        item_status = product_hash[PROPERTY_ITEM_STATUS]
        if item_status.nil? && color_master_sku && color_master_sku[PROPERTY_ITEM_STATUS]
          item_status = color_master_sku[PROPERTY_ITEM_STATUS]
        end
        !ITEM_STATUS_INACTIVE.include?(item_status)
      elsif type == SALSIFY_TYPE_IL
        !ITEM_STATUS_INACTIVE.include?(product_hash[PROPERTY_ITEM_STATUS])
      else
        false
      end
    end

    def long_description(product_copy_text)
      product_copy_text.is_a?(Array) ? product_copy_text.compact.first : product_copy_text
    end

    def image_groups_for_product(product_hash:, type:, complete_color_master_sku_by_id: {})
      if type == SALSIFY_TYPE_GROUP_COLLECTION
        return image_groups_for_collection(product_hash)
      end

      long_color_code_by_sku_id = complete_color_master_sku_by_id.map do |sku_id, sku|
        [sku_id, long_color_code_for_sku(sku, type, product_hash)]
      end.to_h
      main_urls_by_sku_id = parse_main_urls_by_sku_id(complete_color_master_sku_by_id)
      swatch_urls_by_sku_id = parse_swatch_urls_by_sku_id(complete_color_master_sku_by_id)

      return [] if main_urls_by_sku_id.empty? && swatch_urls_by_sku_id.empty?
      first_url = main_urls_by_sku_id.first.last.first
      [
        {
          'xml-attribute:view-type' => 'imageURL',
          'image' => {
            # This looks weird but we get the first color master sku,
            # get the mainimage urls, and get the first one
            'xml-attribute:path' => scene7_url(first_url)
          }
        },
        main_urls_by_sku_id.map { |sku_id, main_urls|
          {
            'xml-attribute:view-type' => 'imageURL',
            'xml-attribute:variation-value' => long_color_code_by_sku_id[sku_id],
            'image' => main_urls.map { |url|
              { 'xml-attribute:path' => scene7_url(url) }
            }.reject { |h| [nil, ''].include?(h['xml-attribute:path']) }
          }
        }.reject { |h| h['image'].empty? },
        swatch_urls_by_sku_id.map { |sku_id, swatch_urls|
          {
            'xml-attribute:view-type' => 'swatch',
            'xml-attribute:variation-value' => long_color_code_by_sku_id[sku_id],
            'image' => swatch_urls.map { |url|
              { 'xml-attribute:path' => scene7_url(url) }
            }.reject { |h| [nil, ''].include?(h['xml-attribute:path']) }
          }
        }
      ].flatten.reject { |h|
        (h['image'].is_a?(Array) && h['image'].empty?) ||
        (h['image'].is_a?(Hash) && [nil, ''].include?(h['image']['xml-attribute:path']))
      }
    end

    def image_groups_for_collection(collection_hash)
      [
        {
          'xml-attribute:view-type' => 'imageURL',
          'image' => parse_urls_by_shot_type(
            collection_hash,
            ['scene7 images', 'mainimage url']
          ).reject { |shot_type, url|
            # Don't include any LIMITED shot types
            shot_type.start_with?('TLC')
          }.map { |shot_type, url|
            { 'xml-attribute:path' => scene7_url(url) }
          }.reject { |h| [nil, ''].include?(h['xml-attribute:path']) }
        },
        {
          'xml-attribute:view-type' => 'swatch',
          'image' => parse_urls_by_shot_type(
            collection_hash,
            ['scene7 images', 'swatchimage url']
          ).reject { |shot_type, url|
            shot_type.start_with?('TLC')
          }.map { |shot_type, url|
            { 'xml-attribute:path' => scene7_url(url) }
          }.reject { |h| [nil, ''].include?(h['xml-attribute:path']) }
        },
      ].flatten.reject { |h| h['image'].empty? }
    end

    def parse_main_urls_by_sku_id(sku_by_id)
      sku_by_id.map do |sku_id, sku|
        [
          sku_id,
          parse_urls_by_shot_type(sku, ['scene7 images', 'mainimage url']).reject { |shot_type, url|
            next unless shot_type
            shot_type.start_with?('TLC')
          }.compact.values
        ]
      end.to_h
    end

    def parse_swatch_urls_by_sku_id(sku_by_id)
      sku_by_id.map do |sku_id, sku|
        [
          sku_id,
          parse_urls_by_shot_type(sku, ['scene7 images', 'swatchimage url']).reject { |shot_type, url|
            next unless shot_type
            shot_type.start_with?('TLC')
          }.compact.values
        ]
      end.to_h
    end

    def parse_urls_by_shot_type(product_hash, property_inclusion_strings)
      product_hash.map do |property, value|
        next if property_inclusion_strings.any? { |text| !property.downcase.include?(text) }
        match = property.match(/^.+\s+-\s+(.+)\s+-\s+.+$/)
        shot_type = match ? match[1] : nil
        [shot_type, value]
      end.compact.to_h
    end

    def scene7_url(url)
      url ? url.split('.com').last : nil
    end

    def sitemap_included_flag(product_hash, type)
      if [SALSIFY_TYPE_BASE, SALSIFY_TYPE_GROUP_CPG, SALSIFY_TYPE_GROUP_SCG_SSG, SALSIFY_TYPE_GROUP_COLLECTION].include?(type)
        (
          online_flag(product_hash: product_hash, type: type) &&
          !(product_hash[PROPERTY_FLAG_PWP] || product_hash[PROPERTY_FLAG_GWP] || product_hash[PROPERTY_FLAG_PYG])
        ).present?
      else
        false
      end
    end

    def product_set_products(grouping_product:, included_sku_by_id:)
      [
        grouping_product[PROPERTY_CHILD_STYLES_OF_GROUP],
        grouping_product[PROPERTY_CHILD_SKUS_OF_GROUP]
      ].flatten.compact.uniq.map { |product_id|
        { 'xml-attribute:product-id' => product_id.strip }
      }
    end

    #
    # Custom Attributes
    #

    def custom_attribute_is_master
      {
        'xml-attribute:attribute-id' => 'isMaster',
        'xml-value' => true
      }
    end

    def custom_attribute_size(product_hash)
      if product_hash[PROPERTY_OMNI_SIZE_DESC]
        size = "#{product_hash[PROPERTY_NRF_SIZE_CODE]}_#{product_hash[PROPERTY_OMNI_SIZE_DESC]}".gsub(' ', '')
      else
        size = "#{product_hash[PROPERTY_NRF_SIZE_CODE]}_#{product_hash[PROPERTY_VENDOR_SIZE_DESC]}".gsub(' ', '')
      end
      {
        'xml-attribute:attribute-id' => 'size',
        'xml-value' => size
      }
    end

    def custom_attribute_color(sku_hash, parent_type, parent)
      {
        'xml-attribute:attribute-id' => 'color',
        'xml-value' => long_color_code_for_sku(sku_hash, parent_type, parent)
      }
    end

    def long_color_code_for_sku(sku_hash, parent_type, parent)
      if parent_type == SALSIFY_TYPE_GROUP_CPG &&
        (['627', 627].include?(parent[PROPERTY_DEPT_NUMBER]) ||
        ['109', 109].include?(parent[PROPERTY_DEMAND_CTR]) ||
        ['5820', '5824', 5820, 5824].include?(parent[PROPERTY_CLASS_NUMBER]))
        # Special case, use orin of grouping product
        code = "#{sku_hash[PROPERTY_NRF_COLOR_CODE]}#{parent[PROPERTY_GROUP_ORIN]}"
      elsif sku_hash['salsify:parent_id'] && product_families[sku_hash['salsify:parent_id']]
        # Grab orin from parent style if there is one
        code = "#{sku_hash[PROPERTY_NRF_COLOR_CODE]}#{product_families[sku_hash['salsify:parent_id']][PROPERTY_GROUP_ORIN]}"
      else
        code = "#{sku_hash[PROPERTY_NRF_COLOR_CODE]}#{sku_hash[PROPERTY_GROUP_ORIN]}"
      end
      code.gsub(' ', '')
    rescue Exception => e
      puts "#{stamp} ERROR while determining long color code for sku #{sku_hash['salsify:id']}"
      raise e
    end

    def custom_attribute_cpg_size(product_hash)
      {
        'xml-attribute:attribute-id' => 'isSizeGroupingCPG',
        'xml-value' => (
          ['627', 627].include?(product_hash[PROPERTY_DEPT_NUMBER]) ||
          ['109', 109].include?(product_hash[PROPERTY_DEMAND_CTR])
        )
      }
    end

    #
    # Variations
    #

    def variation_attribute_color(product_hash:, type:, complete_color_master_sku_by_id:)
      {
        'xml-attribute:attribute-id' => 'color',
        'xml-attribute:variation-attribute-id' => 'color',
        'display-name' => {
          'xml-value' => 'color'
        },
        'variation-attribute-values' => {
          'variation-attribute-value' => begin
            if [SALSIFY_TYPE_BASE, SALSIFY_TYPE_GROUP_CPG, SALSIFY_TYPE_GROUP_SCG_SSG].include?(type)
              complete_color_master_sku_by_id.map { |sku_id, sku|
                {
                  'xml-attribute:value' => begin
                    if type == SALSIFY_TYPE_GROUP_CPG &&
                      (['627', 627].include?(product_hash[PROPERTY_DEPT_NUMBER]) ||
                      ['109', 109].include?(product_hash[PROPERTY_DEMAND_CTR]))
                      # Special case, use orin from grouping product (which is product_hash)
                      "#{sku[PROPERTY_NRF_COLOR_CODE]}#{product_hash[PROPERTY_GROUP_ORIN]}"
                    elsif type == SALSIFY_TYPE_BASE
                      # product_hash is the parent product, just grab orin from there
                      "#{sku[PROPERTY_NRF_COLOR_CODE]}#{product_hash[PROPERTY_GROUP_ORIN]}"
                    else
                      # Find the parent product and grab orin #
                      parent = product_families[sku['salsify:parent_id']]
                      "#{sku[PROPERTY_NRF_COLOR_CODE]}#{parent ? parent[PROPERTY_GROUP_ORIN] : sku[PROPERTY_GROUP_ORIN]}"
                    end
                  end.gsub(' ', ''),
                  'display-value' => {
                    'xml-value' => sku[PROPERTY_OMNI_COLOR_DESC] ? sku[PROPERTY_OMNI_COLOR_DESC] : sku[PROPERTY_VENDOR_COLOR_DESC]
                  }
                }
              }
            end
          end
        }
      }
    end

    def variation_attribute_size(product_hash:, type:, complete_sku_by_id:)
      {
        'xml-attribute:attribute-id' => 'size',
        'xml-attribute:variation-attribute-id' => 'size',
        'display-name' => {
          'xml-value' => 'size'
        },
        'variation-attribute-values' => {
          'variation-attribute-value' => begin
            if [SALSIFY_TYPE_BASE, SALSIFY_TYPE_GROUP_CPG, SALSIFY_TYPE_GROUP_SCG_SSG].include?(type)
              complete_sku_by_id.map { |sku_id, sku|
                {
                  'xml-attribute:value' => begin
                    if sku[PROPERTY_OMNI_SIZE_DESC]
                      "#{sku[PROPERTY_NRF_SIZE_CODE]}_#{sku[PROPERTY_OMNI_SIZE_DESC]}".gsub(' ', '')
                    else
                      "#{sku[PROPERTY_NRF_SIZE_CODE]}_#{sku[PROPERTY_VENDOR_SIZE_DESC]}".gsub(' ', '')
                    end
                  end,
                  'display-value' => {
                    'xml-value' => sku[PROPERTY_OMNI_SIZE_DESC] ? sku[PROPERTY_OMNI_SIZE_DESC] : sku[PROPERTY_VENDOR_SIZE_DESC]
                  }
                }
              }.uniq { |hash| hash['xml-attribute:value'] }
            end
          end
        }
      }
    end

    def variants_for_product(product_hash:, type:, complete_sku_by_id:)
      if [SALSIFY_TYPE_BASE, SALSIFY_TYPE_GROUP_CPG, SALSIFY_TYPE_GROUP_SCG_SSG].include?(type)
        complete_sku_by_id.map { |sku_id, sku| { 'xml-attribute:product-id' => sku_id.strip } }
      end
    end

    #
    # Bulk in-place property additions
    #

    # Add properties with demandware metadata to this product in place
    def add_configured_properties_to_product!(xml_hash:, product_hash:, type:, parent_hash: nil)
      dw_configured_attributes.group_by { |attribute| attribute[DW_META_XML_PATH] }.each do |xml_path, attributes|
        if attributes.length > 1
          # If multiple attributes for this xml item, order by priority and find first one where there's a value
          sorted_attrs = attributes.sort_by { |attribute| attribute[DW_META_PRIORITY] ? attribute[DW_META_PRIORITY].to_i : 1000000 }
          attribute = sorted_attrs.find { |attribute| product_hash[attribute['salsify:id']] }
        else
          attribute = attributes.first
        end
        next unless attribute
        # Check if we should put this attribute on this xml level
        if [attribute[DW_META_XML_LEVEL]].flatten.map { |text|
          text.split(DW_META_DELIMITER).map { |t| t.strip }
        }.flatten.include?(type)
          attribute_id = attribute['salsify:id']

          # Determine where to pull property value from, self or parent?
          source_levels = attribute[DW_META_SOURCE_LEVEL].split(DW_META_DELIMITER)
          if source_levels.include?(DW_META_SOURCE_LEVEL_BASE) && source_levels.include?(DW_META_SOURCE_LEVEL_SKU)
            # Pull from self, or pull from parent if parent exists and no value on self
            value = product_hash[attribute_id] || (parent_hash ? parent_hash[attribute_id] : nil)
          elsif source_levels.include?(DW_META_SOURCE_LEVEL_BASE) && [SALSIFY_TYPE_SKU, SALSIFY_TYPE_IL].include?(type) && parent_hash && parent_hash[attribute_id]
            # Pull from style, style exists, and style has value
            value = parent_hash[attribute_id]
          else
            # Pull from self
            value = product_hash[attribute_id]
          end

          # Run any configured transformations on the value before inserting it
          value = run_attr_transforms(value, attribute[DW_META_TRANSFORM].split(DW_META_DELIMITER)) if attribute[DW_META_TRANSFORM]

          # Run any hard-coded transformations
          value = run_other_transforms(product_hash, attribute_id, value)

          if attribute[DW_META_IS_CUSTOM_ATTRIBUTE]
            xml_hash['product']['custom-attributes']['custom-attribute'] ||= []
            attr_id = attribute['dw:xml_path'] ? attribute['dw:xml_path'].to_s : attribute['salsify:id'].to_s
            attr_hash = { 'xml-attribute:attribute-id' => (attr_id ? attr_id.gsub(' ', '_') : attr_id) }
            next if [nil, ''].include?(attr_hash['xml-attribute:attribute-id'])
            if value.is_a?(Array)
              attr_hash['value'] = value.map { |val| { 'xml-value' => convert_booleans(attribute_id, val) } }
            else
              attr_hash['xml-value'] = convert_booleans(attribute_id, value)
            end
            xml_hash['product']['custom-attributes']['custom-attribute'] << attr_hash
          else
            insert_val_to_hash(xml_hash, ['product', attribute[DW_META_XML_PATH].split(DW_META_XML_PATH_DELIMITER), 'xml-value'].flatten, convert_booleans(attribute_id, value))
          end
        end
      end
    end

    def convert_booleans(property, value)
      if [true, false].include?(value) && !BOOLEAN_PROPERTIES_DO_NOT_CONVERT.include?(property)
        value ? 'Yes' : 'No'
      else
        value
      end
    end

    def run_attr_transforms(value, transforms)
      transforms.each do |transform|
        if transform.downcase == 'lowercase'
          value = value.downcase if value.is_a?(String)
        elsif transform.downcase == 'capitalize'
          value = value.capitalize if value.is_a?(String)
        elsif transform.downcase == 'strip'
          value = value.strip if value.is_a?(String)
        elsif transform.include?('hardcode')
          match = transform.match(/hardcode\((.+)\)/)
          hard_val = match ? match[1] : nil
          value = hard_val if hard_val
        end
      end
      value
    end

    def run_other_transforms(product, property_id, value)
      if property_id == PROPERTY_GROUPING_TYPE && [GROUPING_TYPES_CPG, GROUPING_TYPES_SCG_SSG].flatten.include?(value)
        nil
      elsif property_id == PROPERTY_IL_ELIGIBLE && product['salsify:parent_id']
        'false'
      else
        value
      end
    end

    def add_iph_levels!(xml_hash, product_hash)
      return if product_hash[PROPERTY_IPH_CATEGORY].nil?
      xml_hash['product']['custom-attributes'] ||= { 'custom-attribute' => [] }
      product_hash[PROPERTY_IPH_CATEGORY].split(IPH_PATH_DELIMITER).map { |s| s ? s.strip : s }.each_with_index do |category, index|
        xml_hash['product']['custom-attributes']['custom-attribute'] << {
          'xml-attribute:attribute-id' => "iphL#{index + 1}",
          'xml-value' => (category ? category.gsub(' ', '_') : nil)
        }
      end
      iph_cat_hash = xml_hash['product']['custom-attributes']['custom-attribute'].find { |hash| hash['xml-attribute:attribute-id'] == PROPERTY_IPH_CATEGORY }
      iph_cat_hash['xml-value'] = iph_cat_hash['xml-value'].split(IPH_PATH_DELIMITER).map { |s| s ? s.strip : s }.join(IPH_PATH_XML_DELIMITER) if iph_cat_hash && iph_cat_hash['xml-value']
    end

    def add_category_specific_attributes!(xml_hash, product_hash)
      return if product_hash[PROPERTY_IPH_CATEGORY].nil?
      wait_for_data_dictionary

      iph_cat_items = product_hash[PROPERTY_IPH_CATEGORY].split(IPH_PATH_DELIMITER).map(&:strip)
      iph_cats = iph_cat_items.length.times.map { |i| iph_cat_items[0..i].join(' > ') }

      iph_specific_attributes = dictionary_attributes.select do |attribute|
        attribute.categories && product_hash[PROPERTY_IPH_CATEGORY] && iph_cats.any? { |cat| attribute.categories.include?(cat) }
      end
      return if iph_specific_attributes.empty?

      iph_specific_attributes.each do |category_attribute|
        if xml_name_by_attr_id[category_attribute.id]
          match = xml_name_by_attr_id[category_attribute.id].match(/^_\d+_(.+)$/)
          xml_name = match ? match[1] : xml_name_by_attr_id[category_attribute.id]
        else
          xml_name = category_attribute.id
        end
        xml_hash['product']['custom-attributes'] ||= { 'custom-attribute' => [] }
        custom_attr = custom_attribute(product_hash, category_attribute.id, xml_name)
        xml_hash['product']['custom-attributes']['custom-attribute'] << custom_attr unless [nil, ''].include?(custom_attr['xml-attribute:attribute-id'])
      end
    end

    def custom_attribute(product_hash, property_id, xml_name)
      result = { 'xml-attribute:attribute-id' => (xml_name ? xml_name.gsub(' ', '_') : xml_name) }
      if product_hash[property_id].is_a?(Array)
        # Add multiple values in child <value> tags
        result['value'] = [product_hash[property_id].map { |value|
          { 'xml-value' => convert_booleans(property_id, value) }
        }].flatten
      else
        result['xml-value'] = convert_booleans(property_id, product_hash[property_id])
      end
      result
    end

    # Recursively insert a value into a hash given an array path of keys
    def insert_val_to_hash(hash, keys_path, value)
      return if !hash.is_a?(Hash)
      key = keys_path.shift
      hash[key] ||= {}
      if keys_path.empty?
        hash[key] = value
      else
        insert_val_to_hash(hash[key], keys_path, value)
      end
    end

    def final_master_override!(xml_hash, product_hash)
      # Perform any final edits to the master product here.
      # Override this method in subclass.
    end

    def final_sku_override!(xml_hash, sku_hash, color_master_sibling)
      # Perform any final edits to the sku here.
      # Override this method in subclass.
    end

    #
    # Helpers
    #

    def recorded_products_file_batches
      @recorded_products_file_batches ||= begin
        puts "#{stamp} Batching #{recorded_products_local_filepaths.length} input files into groups using soft size limit of #{max_mb_per_input_file_batch} MB"
        result = []
        batch = []
        batch_size_sum_mb = 0
        recorded_products_local_filepaths.each do |filepath|
          size_mb = file_size_in_mb(filepath)
          batch_size_sum_mb += size_mb
          batch << filepath
          if batch_size_sum_mb >= max_mb_per_input_file_batch && max_mb_per_input_file_batch != -1
            result << batch
            batch = []
            batch_size_sum_mb = 0
          end
        end
        result << batch
        puts "#{stamp} Batched input files into #{result.length} batches"
        result
      end
    end

    def file_size_in_mb(filepath)
      (((File.size(filepath) / 1024.0) / 1024.0)).round(1)
    end

    def max_mb_per_input_file_batch
      @max_mb_per_input_file_batch ||= ENV.fetch('DW_MAX_MB_PER_INPUT_FILE_BATCH').to_f
    end

    def recorded_products_local_filepaths
      @recorded_products_local_filepaths ||= begin
        puts "#{stamp} Retrieving updated products files from S3"
        t = Time.now
        if options[:use_files_recorded_after]
          result = DirtyFamiliesHelper.retrieve_dirty_products_files_since(since: options[:use_files_recorded_after])
        elsif options[:only_use_latest_export]
          result = [DirtyFamiliesHelper.retrieve_latest_dirty_products_file].flatten
        elsif options[:specific_files]
          result = DirtyFamiliesHelper.retrieve_specific_dirty_products_files(Oj.load(options[:specific_files]))
        elsif options[:specific_file_contains]
          result = DirtyFamiliesHelper.retrieve_dirty_products_files_containing_text(options[:specific_file_contains])
        else
          result = DirtyFamiliesHelper.retrieve_dirty_products_files_since(since: since_datetime, to: to_datetime)
        end
        puts "#{stamp} Retrieved #{result.length} dirty products files from S3 in #{((Time.now - t) / 60).round(1)} minutes"
        result
      end
    end

    def sku_ids_by_style_id
      @sku_ids_by_style_id ||= begin
        result = GoogleHashDenseRubyToRuby.new
        product_families.values.group_by do |product|
          product['salsify:parent_id']
        end.map do |parent_id, products|
          [parent_id, products.map { |product| product['salsify:id'] }]
        end.to_h.reject do |parent_id, skus|
          parent_id.nil?
        end.each { |k, v| result[k] = v }
        result
      end
    end

    def attributes
      @attributes ||= begin
        t = Time.now
        puts "#{stamp} Exporting attributes from org #{ENV.fetch('CARS_ORG_ID')}"
        a = salsify_helper.export_attributes
        puts "#{stamp} Retrieved org attributes in #{((Time.now - t) / 60).round(1)} min"
        a
      end
    end

    def wait_for_org_attributes
      return if @attributes
      t = Time.now
      puts "#{stamp} Waiting for org attributes"
      while @attributes.nil?
        if ((Time.now - t) / 60) <= max_wait_org_attributes
          sleep 5
        else
          puts "#{stamp} ERROR waited too long for org attributes, been waiting for #{((Time.now - t) / 60).round(1)} minutes"
          raise "Waited too long for org attributes! Past limit of #{max_wait_org_attributes} minutes."
        end
      end
      puts "#{stamp} No progress for #{((Time.now - t) / 60).round(1)} min while waiting for org_attributes"
    end

    def max_wait_org_attributes
      @max_wait_org_attributes ||= ENV['MAX_WAIT_ORG_ATTRS'] ? ENV['MAX_WAIT_ORG_ATTRS'].to_i : MAX_WAIT_ORG_ATTRS
    end

    def dw_configured_attributes
      @dw_configured_attributes ||= begin
        wait_for_org_attributes
        attributes.select do |attribute|
          attribute[DW_META_SOURCE_LEVEL] &&
          attribute[DW_META_XML_LEVEL] &&
          attribute[DW_META_XML_PATH] &&
          (attribute[DW_META_FEED].nil? || attribute[DW_META_FEED].include?('master'))
        end.map { |att|
          att.map { |key, val| [key.to_s, val.is_a?(Array) ? val.map { |v| v.to_s } : val.to_s] }.to_h
        }
      end
    end

    def attributes_in_product_attributes_group
      @attributes_in_product_attributes_group ||= attributes.select do |attribute|
        attribute['salsify:attribute_group'] == PROPERTY_GROUP_PRODUCT_ATTRIBUTES
      end
    end

    def updated_products
      @updated_products ||= begin
        result = {}
        product_families.each do |product_id, product|
          parent = product_families[product['salsify:parent_id']]
          if DateTime.parse(product['salsify:updated_at']) > since_datetime &&
            (!product[PROPERTY_GIFT_CARD] && !(parent && parent[PROPERTY_GIFT_CARD]))
            result[product_id] = product
          end
        end
        result
      end
    end

    def updated_grouping_products
      @updated_grouping_products ||= updated_products.select do |product_id, product|
        product['salsify:parent_id'].nil? &&
        product[PROPERTY_GROUPING_TYPE]
      end
    end

    def updated_base_products
      @updated_base_products ||= updated_products.select do |product_id, product|
        product['salsify:parent_id'].nil? &&
        product[PROPERTY_GROUPING_TYPE].nil? &&
        ![true, 'true', 'True'].include?(product[PROPERTY_IL_ELIGIBLE]) &&
        !product[PROPERTY_GIFT_CARD]
      end
    end

    def updated_skus
      @updated_skus ||= updated_products.select do |product_id, product|
        product['salsify:parent_id'] ||
        [true, 'true', 'True'].include?(product[PROPERTY_IL_ELIGIBLE])
      end
    end

    def is_style_complete?(style)
      if style[PROPERTY_GROUPING_TYPE] != GROUPING_TYPES_RCG
        style[PROPERTY_COPY_APPROVAL_STATE] == true
      else
        style[PROPERTY_COPY_APPROVAL_STATE] == true && style[PROPERTY_SCENE7_IMAGE_A]
      end
    end

    def is_sku_complete?(sku:, color_master: nil)
      if sku[PROPERTY_GROUPING_TYPE] != GROUPING_TYPES_RCG
        scene7_url = (color_master ? color_master[PROPERTY_SCENE7_IMAGE_A] : sku[PROPERTY_SCENE7_IMAGE_A])
        scene7_url.is_a?(String) &&
        !scene7_url.empty? &&
        sku[PROPERTY_NRF_COLOR_CODE] &&
        sku[PROPERTY_NRF_SIZE_CODE] &&
        (sku[PROPERTY_OMNI_COLOR_DESC] || sku[PROPERTY_VENDOR_COLOR_DESC]) &&
        (sku[PROPERTY_OMNI_SIZE_DESC] || sku[PROPERTY_VENDOR_SIZE_DESC])
      else
        sku[PROPERTY_COPY_APPROVAL_STATE] && sku[PROPERTY_SCENE7_IMAGE_A]
      end
    end

    def dictionary_attributes
      @dictionary_attributes ||= begin
        tries = 0
        begin
          t = Time.now
          puts "#{stamp} Retrieving data dictionary from Google Drive"
          a = data_dictionary.attributes
          puts "#{stamp} Retrieved data dictionary in #{((Time.now - t) / 60).round(1)} min"
          a
        rescue Exception => e
          if tries < MAX_TRIES_DATA_DICT
            puts "#{stamp} WARNING error while pulling data dictionary, sleeping and retrying: #{e.message}\n#{e.backtrace.join("\n")}"
            sleep SLEEP_RETRY_DATA_DICT
            tries += 1
            retry
          else
            puts "#{stamp} ERROR while pulling data dictionary, failed #{MAX_TRIES_DATA_DICT} times, error is: #{e.message}\n#{e.backtrace.join("\n")}"
          end
        end
      end
    end

    def data_dictionary
      @data_dictionary ||= Enrichment::Dictionary.new
    end

    def xml_name_by_attr_id
      @xml_name_by_attr_id ||= data_dictionary.iph_attrs.map { |row| [row[:attribute], row[:MAPPING_KEY]] }.to_h
    end

    def wait_for_data_dictionary
      return if @dictionary_attributes
      t = Time.now
      puts "#{stamp} Waiting for data dictionary"
      while @dictionary_attributes.nil?
        if ((Time.now - t) / 60) <= max_wait_data_dictionary
          sleep 5
        else
          puts "#{stamp} ERROR waited too long for data dictionary, been waiting for #{((Time.now - t) / 60).round(1)} minutes"
          raise "Waited too long for data dictionary! Past limit of #{max_wait_data_dictionary} minutes."
        end
      end
      puts "#{stamp} No progress for #{((Time.now - t) / 60).round(1)} min while waiting for data dictionary"
    end

    def max_wait_data_dictionary
      @max_wait_data_dictionary ||= ENV['MAX_WAIT_DATA_DICT'] ? ENV['MAX_WAIT_DATA_DICT'].to_i : MAX_WAIT_DATA_DICT
    end

    def grouping_products_for_product_ids(style_ids: [], sku_ids: [])
      grouping_product_by_id.select do |grouping_product_id, grouping_product|
        (!style_ids.empty? &&
        grouping_product[PROPERTY_CHILD_STYLES_OF_GROUP] &&
        style_ids.any? { |style_id| grouping_product[PROPERTY_CHILD_STYLES_OF_GROUP].include?(style_id) }) ||
        (!sku_ids.empty? &&
        grouping_product[PROPERTY_CHILD_SKUS_OF_GROUP] &&
        sku_ids.any? { |sku_id| grouping_product[PROPERTY_CHILD_SKUS_OF_GROUP].include?(sku_id) })
      end.compact
    end

    def grouping_ids_by_style_sku_id
      @grouping_ids_by_style_sku_id ||= begin
        result = {}
        puts "#{stamp} Building lookup of style/sku ids to grouping ids"
        grouping_product_by_id.each do |grp_id, grp|
          style_ids = [grp[PROPERTY_CHILD_STYLES_OF_GROUP]].flatten
          sku_ids = [grp[PROPERTY_CHILD_SKUS_OF_GROUP]].flatten
          [style_ids, sku_ids].flatten.each do |id|
            result[id] ||= []
            result[id] << grp_id
          end
        end
        result
      end
    end

    def grouping_product_by_id
      @grouping_product_by_id ||= begin
        result = {}
        product_families.each do |id, product|
          result[id] = product if product['salsify:parent_id'].nil? && product[PROPERTY_GROUPING_TYPE]
        end
        result
      end
    end

    def n_hours_ago(n)
      dt = start_datetime || DateTime.now.utc.to_datetime
      (dt - (n / 24.0))
    end

    def recursive_init_dir(path, level = 0)
      pieces = path.split('/')
      return if level >= pieces.length
      dir = pieces[0..level].join('/')
      Dir.mkdir(dir) unless File.exists?(dir)
      recursive_init_dir(path, level + 1)
    end

    def update_products_with_pending_flag
      return if product_ids_to_mark_publish_pending_true.empty? && product_ids_to_mark_publish_pending_false.empty?
      puts "#{stamp} Marking #{product_ids_to_mark_publish_pending_true.uniq.length} products isBasePublishPending = true, marking #{product_ids_to_mark_publish_pending_false.uniq.length} false"
      salsify_helper.run_csv_import(
        filepath: build_publish_pending_import_csv,
        import_id: publish_pending_import_id,
        wait_until_complete: false
      )
    rescue Exception => e
      if e.message.downcase.include?('import queue is full')
        puts "#{stamp} Import failed because import queue is full. Waiting #{SLEEP_TIME_IMPORT_QUEUE_FULL} seconds and retrying."
        sleep SLEEP_TIME_IMPORT_QUEUE_FULL
        retry
      else
        raise e
      end
    end

    def publish_pending_import_id
      @publish_pending_import_id ||= ENV.fetch('DW_IMPORT_ID_PUBLISH_PENDING').to_i
    end

    def build_publish_pending_import_csv
      recursive_init_dir(LOCAL_PATH_PUBLISH_PENDING_IMPORT)
      filepath = File.join(LOCAL_PATH_PUBLISH_PENDING_IMPORT, filename_publish_pending_import)
      CSV.open(filepath, 'w') do |csv|
        csv << ['Product ID', PROPERTY_PENDING_BASE_PUBLISH]
        product_ids_to_mark_publish_pending_true.uniq.each do |sku_id|
          csv << [sku_id, true]
        end
        product_ids_to_mark_publish_pending_false.uniq.reject do |sku_id|
          product_ids_to_mark_publish_pending_true.include?(sku_id)
        end.each do |sku_id|
          csv << [sku_id, false]
        end
      end
      filepath
    end

    def filename_publish_pending_import
      @filename_publish_pending_import ||= FILENAME_PUBLISH_PENDING_IMPORT
    end

    def update_products_with_sent_to_dw_timestamp
      return if dw_products.empty?
      product_ids_without_sent_to_dw_timestamp = dw_products.map do |dw_product|
        product_id = dw_product['product']['xml-attribute:product-id']
        full_record = product_families[product_id]
        if full_record
          next if full_record[PROPERTY_SENT_TO_DW_TIMESTAMP]
          product_id
        else
          puts "#{stamp} WARNING unable to find product #{product_id} in product_families hash, may have been stripped and actually have whitespace"
        end
      end.compact.uniq
      return if product_ids_without_sent_to_dw_timestamp.empty?
      begin
        puts "#{stamp} Marking #{product_ids_without_sent_to_dw_timestamp.length} products with sentToWebDate timestamp"
        salsify_helper.run_csv_import(
          filepath: build_sent_to_dw_import_csv(product_ids_without_sent_to_dw_timestamp),
          import_id: sent_to_dw_import_id,
          wait_until_complete: false
        )
      rescue Exception => e
        if e.message.downcase.include?('import queue is full')
          puts "#{stamp} Import failed because import queue is full. Waiting #{SLEEP_TIME_IMPORT_QUEUE_FULL} seconds and retrying."
          sleep SLEEP_TIME_IMPORT_QUEUE_FULL
          retry
        else
          raise e
        end
      end
    end

    def sent_to_dw_import_id
      @sent_to_dw_import_id ||= ENV.fetch('DW_IMPORT_ID_SENT_TO_DW').to_i
    end

    def build_sent_to_dw_import_csv(product_ids)
      recursive_init_dir(LOCAL_PATH_SENT_TO_DW_IMPORT)
      filepath = File.join(LOCAL_PATH_SENT_TO_DW_IMPORT, sent_to_dw_import_filename)
      CSV.open(filepath, 'w') do |csv|
        csv << ['Product ID', PROPERTY_SENT_TO_DW_TIMESTAMP]
        product_ids.each do |product_id|
          csv << [product_id, start_datetime.in_time_zone(TIMEZONE_EST).strftime('%Y-%m-%d %l:%M %p %Z')]
        end
      end
      filepath
    end

    def sent_to_dw_import_filename
      @sent_to_dw_import_filename ||= FILENAME_SENT_TO_DW_IMPORT
    end

    def send_feed_done_email(dw_zip_paths)
      RRDonnelley::Mailer.send_mail(
        recipients: feed_done_email_recipients,
        subject: feed_done_email_subject,
        message: feed_done_email_body(dw_zip_paths)
      )
    end

    def feed_done_email_recipients
      @feed_done_email_recipients ||= Oj.load(ENV.fetch('DW_FEED_DONE_EMAIL_RECIPIENTS'))
    end

    def feed_done_email_subject
      "Finished Belk #{mode == :prod ? 'PROD' : 'QA'} Demandware master catalog export"
    end

    def feed_done_email_body(filepaths)
      "<p>Finished generation of master Belk Demandware XML feed.</p>" +
      "<p>Environment: #{ENV.fetch('CARS_ENVIRONMENT')}</p>" +
      "<p>Processed modified products in timeframe: #{since_datetime.in_time_zone('America/New_York').to_s} => #{to_datetime.in_time_zone('America/New_York').to_s}</p>" +
      "<p>Processed recorded file names:</p>" +
      "<ul>" +
      (recorded_products_local_filepaths.sort.map { |path| "<li>#{path.split('/').last}</li>" }.join('')) +
      "</ul><br/>" +
      "<p># Files generated: #{filepaths.length}</p>" +
      "<p>Generated file names:</p>" +
      "<ul>" +
      (filepaths.map { |path| "<li>#{path.split('/').last}</li>" }.join("")) +
      "</ul><br/>" +
      "<p># Total Updated Products: #{updated_products.length}</p>" +
      "<p># Updated Styles: #{updated_base_products.length}</p>" +
      "<p># Updated Skus: #{updated_skus.length}</p>" +
      "<p># Updated Groupings: #{updated_grouping_products.length}</p>" +
      "<p>Total Time to Generate Feed: #{((Time.now - t_start) / 60).round(1)} minutes"
    end

    def send_error_report_email(e)
      RRDonnelley::Mailer.send_mail(
        recipients: error_report_email_recipients,
        subject: error_report_email_subject,
        message: error_report_email_body(e)
      )
    end

    def error_report_email_recipients
      @error_report_email_recipients ||= Oj.load(ENV.fetch('DW_FEED_ERROR_EMAIL_RECIPIENTS'))
    end

    def error_report_email_subject
      "Belk #{mode == :prod ? 'PROD' : 'QA'} Demandware master catalog export ERROR"
    end

    def error_report_email_body(e)
      "<p>An error occurred while generating Belk Demandware master catalog XML feed.</p>" +
      "<p>Error: #{e.message}</p>" +
      "<p>Error Stack Trace:</p>" +
      "#{e.backtrace.join('<br/>')}"
    end

    def set_job_status_failed(error)
      JobStatus.where(title: 'dwre_master').last.update_attributes!(
        activity: "Failed to generate xml for range: #{since_datetime.strftime('%Y-%m-%d %H:%M:%S %Z')} to #{to_datetime.strftime('%Y-%m-%d %H:%M:%S %Z')}, sent email alert",
        error: error.message
      )
    end

    def update_last_dw_feed_timestamp
      key = mode == :prod ? S3_KEY_DW_FEED_TIMESTAMP_PROD : S3_KEY_DW_FEED_TIMESTAMP_TEST
      Demandware::S3Helper.new.upload_to_s3(s3_bucket, key, to_datetime.to_s)
    end

    def archive_input_files
      folder = mode == :prod ? S3_KEY_UPDATED_PRODUCTS_JSON_PROD : S3_KEY_UPDATED_PRODUCTS_JSON_TEST
      archive = mode == :prod ? S3_KEY_UPDATED_PRODUCTS_JSON_ARCHIVE_PROD : S3_KEY_UPDATED_PRODUCTS_JSON_ARCHIVE_TEST
      puts "#{stamp} Archiving processed input files from #{folder} to #{archive}"
      recorded_products_local_filepaths.each do |local_path|
        begin
          filename = local_path.split('/').last
          puts "#{stamp} Archiving #{filename}"
          Demandware::S3Helper.new.move_object(
            src_bucket: s3_bucket,
            src_key: File.join(folder, filename),
            target_path: File.join(s3_bucket, archive, filename)
          )
        rescue Exception => e
          puts "#{stamp} ERROR while archiving file #{local_path}, continuing but error is: #{e.message}\n#{e.backtrace.join("\n")}"
        end
      end
      puts "#{stamp} Done archiving processed files"
    end

    def s3_bucket
      @s3_bucket ||= mode == :prod ? S3_BUCKET_PROD : S3_BUCKET_TEST
    end

    def product_ids_to_mark_publish_pending_true
      @product_ids_to_mark_publish_pending_true ||= []
    end

    def product_ids_to_mark_publish_pending_false
      @product_ids_to_mark_publish_pending_false ||= []
    end

    def sent_product_ids
      @sent_product_ids ||= []
    end

    def processed_product_ids
      @processed_product_ids ||= {}
    end

    def xml_mode
      XML_MODE_MASTER
    end

    def xml_file_prefix_belk
      'Catalog_Salsify_Delta_'
    end

    def xml_file_prefix_cfh
      'Catalog_Delta_'
    end

    def xml_file_name_belk(sequence)
      "#{xml_file_prefix_belk}#{to_datetime.in_time_zone('America/New_York').strftime('%Y%m%d_%H%M%S')}_#{sequence}.xml"
    end

    def xml_file_name_cfh(sequence)
      "#{xml_file_prefix_cfh}#{to_datetime.in_time_zone('America/New_York').strftime('%Y%m%d_%H%M%S')}_#{sequence}.xml"
    end

    def zip_file_name_cfh
      "#{xml_file_prefix_cfh}#{to_datetime.in_time_zone('America/New_York').strftime('%Y%m%d_%H%M%S')}.tar.gz"
    end

    def stamp
      '$DW FEED MASTER$'
    end

  end

end
