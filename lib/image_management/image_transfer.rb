module ImageManagement
  class ImageTransfer
    include Muffin::SalsifyClient

    MAX_FILE_UPLOAD_TRIES = 8.freeze
    MIN_SLEEP_SEC = 5.freeze
    MAX_SLEEP_SEC = 30.freeze

    attr_reader :products

    def initialize(products)
      @products = products
    end

    def self.send_images(products)
      new(products).send_images
    end

    def self.send_unsent_assets
      new(nil).send_unsent_assets
    end

    def send_images
      if assets_to_send.empty?
        puts "#{STAMP} No assets to send to Belk, done!"
        return
      end
      execute_ftp_delivery
      execute_asset_updates
      puts "#{STAMP} Done!"
    end

    def send_unsent_assets
      if assets_to_send.empty?
        puts "#{STAMP} No assets to send to Belk, done!"
        return
      end
      execute_ftp_delivery
      execute_asset_updates
      puts "#{STAMP} Done!"
    end

    def sent_filenames_by_asset_id
      @sent_filenames_by_asset_id ||= {}
    end

    def execute_ftp_delivery
      t = Time.now
      puts "#{STAMP} Connecting to Belk via SFTP for image upload..."

      with_sftp do |sftp|
        puts "#{STAMP} Connected! Sending #{assets_to_send.length} unique assets using #{assets_to_send.map { |id, as| as[:filenames].length }.sum } file names"
        count = 0
        assets_to_send.each do |asset_id, asset_info|
          count += 1
          local_path = "#{asset_id}.#{asset_info[:asset_url].split('.').last}"
          download_asset(asset_info[:asset_url], local_path)
          asset_info[:filenames].each do |filename|
            remote_path = File.join(image_upload_path, filename)
            tries = 0
            begin
              sftp.upload!(local_path, remote_path)
              sent_filenames_by_asset_id[asset_id] ||= []
              sent_filenames_by_asset_id[asset_id] << filename
            rescue Net::SFTP::Exception => e
              tries += 1
              if tries < MAX_FILE_UPLOAD_TRIES
                sleep rand(MIN_SLEEP_SEC..MAX_SLEEP_SEC)
                retry
              else
                puts "#{STAMP} ERROR while transferring asset #{asset_id} to Belk via SFTP, tried #{MAX_FILE_UPLOAD_TRIES} times but no success: #{e.message}"
              end
            end
          end
        end
        puts "#{STAMP} Sent #{count}/#{assets_to_send.length} assets to Belk FTP (elapsed time #{((Time.now - t) / 60).round(1)} min)"
      end
      puts "#{STAMP} Done transferring images, took #{((Time.now - t) / 60).round(1)} minutes"
    end

    def execute_asset_updates
      t = Time.now
      puts "#{STAMP} Updating #{sent_filenames_by_asset_id.length} assets to mark sent_to_belk = true"

      asset_source = products ? asset_by_id : unsent_asset_by_id
      count = 0

      Parallel.each(sent_filenames_by_asset_id, in_threads: NUM_THREADS_CRUD) do |asset_id, filenames|
        begin
          count += 1
          asset = asset_source[asset_id]
          image_metadata = Oj.load(asset['image_metadata'])
          filenames.each do |filename|
            meta_key, meta_hash = image_metadata.find do |meta_key, meta_hash|
              meta_hash['filename'] == filename
            end
            next unless meta_key
            image_metadata[meta_key]['sent_to_belk'] = Time.now.in_time_zone('America/New_York').strftime('%Y-%m-%d %l:%M %p %Z')
          end
          client.update_asset(asset_id, { 'image_metadata' => Oj.dump(image_metadata) })
          puts "#{STAMP} Updated #{count}/#{sent_filenames_by_asset_id.length} assets with metadata" if count % 200 == 0
        rescue Exception => e
          puts "#{STAMP} ERROR while updating asset metadata on asset #{asset_id}: #{e.message}\n#{e.backtrace.join("\n")}"
        end
      end

      puts "#{STAMP} Done updating asset metadata, took #{((Time.now - t) / 60).round(1)} minutes"
    end

    def assets_to_send
      @assets_to_send ||= begin
        # Determine where to load asset data from depending on the job
        asset_source = products ? asset_by_id : unsent_asset_by_id

        # Identify asset filename versions which need to be sent
        asset_source.map do |asset_id, asset|
          filenames_to_send = Oj.load(asset[PROPERTY_IMAGE_METADATA]).map do |meta_key, hash|
            hash['sent_to_belk'] == false ? hash['filename'] : nil
          end.compact
          if !filenames_to_send.empty?
            [asset_id, {
              asset_url: asset['salsify:url'],
              filenames: filenames_to_send
            }]
          end
        end.compact.to_h
      end
    end

    def asset_ids_by_sku_id
      @asset_ids_by_sku_id ||= products.map do |sku|
        [sku['salsify:id'], sku.select { |key, value|
          key.downcase.include?('imagepath')
        }.values.flatten.uniq]
      end.to_h
    end

    def asset_by_id
      @asset_by_id ||= begin
        t = Time.now
        asset_ids = asset_ids_by_sku_id.values.flatten.compact.uniq
        assets = asset_ids.length <= MAX_ASSETS_CRUD ? retrieve_assets_crud(asset_ids) : retrieve_assets_export
        a_by_id = assets.map { |asset| [asset['salsify:id'], asset] }.to_h
        puts "Retrieved #{a_by_id.length} Salsify assets in #{(Time.now - t).round(1)} sec"
        a_by_id
      end
    end

    def retrieve_assets_export
      puts "Retrieving assets from org #{org_id} via export..."
      response = client.create_export_run({
        "configuration": {
          "entity_type": "digital_asset",
          "format": "csv"
        }
      })
      completed_response = Salsify::Utils::Export.wait_until_complete(client, response).url
      csv = CSV.new(open(completed_response).read, headers: true)
      csv.to_a.map { |row| row.to_hash }
    end

    def retrieve_assets_crud(asset_ids)
      puts "Retrieving assets from org #{org_id} via crud in #{NUM_THREADS_CRUD} threads..."
      Parallel.map(asset_ids, in_threads: NUM_THREADS_CRUD) do |asset_id|
        client.asset(asset_id)
      end
    end

    def unsent_asset_by_id
      @unsent_asset_by_id ||= begin
        puts "#{STAMP} Filtering for unsent assets"
        t = Time.now
        ids = SalsifyFilter.new(client).filter_assets(
          filter_string: "='image_metadata':contains('\"sent_to_belk\":false')"
        ).map { |a| a['id'] }
        puts "#{STAMP} Found #{ids.length} unsent asset ids, retrieving via crud"
        count = 0
        result = Parallel.map(ids, in_threads: NUM_THREADS_CRUD) do |asset_id|
          begin
            count += 1
            asset = client.asset(asset_id).select { |key, value|
              ['salsify:id', 'salsify:url', 'salsify:name', 'image_metadata'].include?(key)
            }
            puts "#{STAMP} Retrieved #{count}/#{ids.length} assets" if count % 200 == 0
            [asset['salsify:id'], asset]
          rescue Exception => e
            puts "#{STAMP} WARNING error while retrieving asset #{asset_id}: #{e.message}"
            nil
          end
        end.compact.to_h
        puts "#{STAMP} Retrieved #{result.length} asset records, total retrieval time #{((Time.now - t) / 60).round(1)} minutes"
        result
      end
    end

    def download_asset(asset_url, local_path)
      IO.copy_stream(open(asset_url), local_path)
    end

    def with_sftp
      yield Net::SFTP.start(
        ENV.fetch('BELK_IMAGE_SFTP_HOST'),
        ENV.fetch('BELK_IMAGE_SFTP_USER'),
        password: ENV.fetch('BELK_IMAGE_SFTP_PASSWORD')
      )
    end

    def image_upload_path
      @image_upload_path ||= ENV.fetch('CARS_ENVIRONMENT') == 'production' ? BELK_IMAGE_UPLOAD_PATH_PROD : BELK_IMAGE_UPLOAD_PATH_QA
    end

    def org_id
      @org_id ||= ENV['CARS_ORG_ID'].to_i
    end

    def client
      @client ||= salsify_client(org_id: org_id)
    end

  end
end
