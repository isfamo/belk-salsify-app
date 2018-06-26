module Demandware

  class DirtyFamiliesHelper

    EMAIL_RECIPIENTS = ['lwheeler@salsify.com', 'Rahul_Gopinath@belk.com', 'Vinodh_SN@belk.com', 'Prasanna_Rangamani@belk.com', 'kgaughan@salsify.com'].freeze
    #EMAIL_RECIPIENTS = ['lwheeler@salsify.com'].freeze
    STAMP = '$DW RECORD$'.freeze
    MAX_TRIES_JSON_EXPORT = 3.freeze
    SLEEP_BETWEEN_EXPORT_RETRIES = 20.freeze
    LOG_INTERVAL_GROUPING_SKUS = 50.freeze

    attr_reader :start_datetime, :since_datetime, :to_datetime, :mode, :s3_bucket, :s3_folder, :s3_key, :s3_helper, :salsify_helper, :send_email_on_start

    def initialize(to_datetime = nil, since_datetime = nil, send_email_on_start = false)
      @start_datetime = DateTime.now.utc.to_s
      @to_datetime = to_datetime
      @since_datetime = since_datetime
      @mode = ENV.fetch('CARS_ENVIRONMENT') == 'production' ? :prod : :qa
      @s3_bucket = mode == :prod ? S3_BUCKET_PROD : S3_BUCKET_TEST
      @s3_folder = mode == :prod ? S3_KEY_UPDATED_PRODUCTS_JSON_PROD : S3_KEY_UPDATED_PRODUCTS_JSON_TEST
      @s3_key = File.join(s3_folder, FILENAME_UPDATED_PRODUCTS_JSON)
      @s3_helper = S3Helper.new
      @salsify_helper = SalsifyHelper.new
      @send_email_on_start = send_email_on_start
    end

    def self.num_products_updated_in_range(to_datetime: DateTime.now.utc.to_datetime, since_datetime:)
      new(to_datetime, since_datetime).num_products_updated_in_range
    end

    def self.record_dirty_families(to_datetime: DateTime.now.utc.to_datetime, since_datetime:, send_email_on_start: false)
      new(to_datetime, since_datetime, send_email_on_start).record_dirty_families
    end

    def self.retrieve_dirty_products_files_since(since:, to: DateTime.now.utc.to_datetime)
      new.retrieve_dirty_products_files_since(since: since, to: to)
    end

    def self.retrieve_latest_dirty_products_file
      new.retrieve_latest_dirty_products_file
    end

    def self.retrieve_specific_dirty_products_files(filenames)
      new.retrieve_specific_dirty_products_files(filenames)
    end

    def self.retrieve_dirty_products_files_containing_text(text)
      new.retrieve_dirty_products_files_containing_text(text)
    end

    def num_products_updated_in_range
      initial_check_updated_products_count
    end

    def record_dirty_families
      t1 = Thread.new { updated_product_by_id }
      t2 = Thread.new { exported_grouping_products }
      t1.join
      t2.join

      properties_for_full_export
      t = Time.now
      recorded_filepaths = create_and_upload_family_hashes
      puts "#{STAMP} Done recording dirty product families, total time: #{((Time.now - t) / 60).round(1)} mins"
      update_last_record_timestamp unless ENV['testing'] == 'true'
      recorded_filepaths.map { |path| path.split('/').last }
    end

    def retrieve_dirty_products_files_since(since:, to: nil)
      to = DateTime.now.utc.to_datetime if to.nil?
      puts "#{STAMP} Downloading updated product hashes uploaded between #{since.to_s} and #{to.to_s}"
      s3_helper.list_files_updated_between(bucket: s3_bucket, prefix: s3_folder, since: since, to: to).select do |object|
        object.key.include?('.json')
      end.sort_by do |object|
        object.last_modified
      end.map do |object|
        puts "#{STAMP} Downloading from S3: #{object.key}"
        filename = object.key.split('/').last
        filepath = File.join(LOCAL_PATH_UPDATED_PRODUCTS_JSON, filename)
        File.open(filepath, 'w') { |file| file.write(s3_helper.pull_from_s3(s3_bucket, object.key).body.read) }
        filepath
      end
    end

    def retrieve_latest_dirty_products_file
      latest_json_s3_key = s3_helper.list_files(s3_bucket, s3_folder).select do |object|
        object.key.include?('.json')
      end.sort_by do |object|
        object.last_modified
      end.last.key
      filename = latest_json_s3_key.split('/').last
      filepath = File.join(LOCAL_PATH_UPDATED_PRODUCTS_JSON, filename)
      File.open(filepath, 'w') { |file| file.write(s3_helper.pull_from_s3(s3_bucket, latest_json_s3_key).body.read) }
      filepath
    end

    def retrieve_specific_dirty_products_files(filenames)
      filenames.sort.map do |filename|
        filepath = File.join(LOCAL_PATH_UPDATED_PRODUCTS_JSON, filename)
        File.open(filepath, 'w') { |file| file.write(s3_helper.pull_from_s3(s3_bucket, File.join(s3_folder, filename)).body.read) }
        filepath
      end
    end

    def retrieve_dirty_products_files_containing_text(text)
      matching_s3_keys = s3_helper.list_files(s3_bucket, s3_folder).select do |object|
        object.key.include?('.json') && object.key.include?(text)
      end.sort_by do |object|
        object.last_modified
      end.map { |o| o.key }
      puts "#{STAMP} Downloading json files from S3"
      count = 0
      Parallel.map(matching_s3_keys, in_threads: num_threads_local_processing) do |s3_key|
        count += 1
        filename = s3_key.split('/').last
        filepath = File.join(LOCAL_PATH_UPDATED_PRODUCTS_JSON, filename)
        File.open(filepath, 'w') { |file| file.write(s3_helper.pull_from_s3(s3_bucket, s3_key).body.read) }
        puts "#{STAMP} Retrieved #{s3_key.split('/').last}"
        filepath
      end.sort
    end

    # Batch full_export_families into an array of hashes.
    # Each hash is keyed on parent ids and contains the full family as value.
    def batched_families
      @batched_families ||= full_export_families.each_slice(max_families_per_json).map { |array| array.to_h }
    end

    # Hash of parent_id => product_id => product_hash
    # The parent and all its children will be included under the parent_id
    def full_export_families
      @full_export_families ||= exported_products.group_by do |id, product|
        product['salsify:parent_id'] || product['salsify:id']
      end.map { |parent_id, array| [parent_id, array.to_h] }.to_h
    end

    def full_export_groupings
      @full_export_groupings ||= exported_products.select { |id, product| product['salsify:parent_id'].nil? && product[PROPERTY_GROUPING_TYPE] }
    end

    def exported_products
      @exported_products ||= begin
        return {} if export_configs.empty?
        count = 0
        t_start = Time.now
        results = {}
        num_threads = [num_threads_json_exports, export_configs.length].min

        Parallel.each(export_configs, in_threads: num_threads) do |export_config|
          tries = 0
          begin
            t_each = Time.now
            csv_export_string = salsify_helper.run_export(export_config)
            count += 1
            time_each = ((Time.now - t_each) / 60).round(1)
            time_total = ((Time.now - t_start) / 60).round(1)
            puts "#{STAMP} Finished family export (#{count}/#{export_configs.length}) (#{time_each} min this run) (#{time_total} min total)"
            results.merge!(salsify_helper.parse_product_by_id_from_csv_export(csv_export_string))
          rescue Exception => e
            puts "#{STAMP} ERROR while running json export: #{e.message}"
            if tries < MAX_TRIES_JSON_EXPORT
              tries += 1
              sleep SLEEP_BETWEEN_EXPORT_RETRIES
              retry
            else
              puts "#{STAMP} ERROR occurred #{MAX_TRIES_JSON_EXPORT} times, not retrying, message is: #{e.message}\n#{e.backtrace.join("\n")}"
            end
          end
        end
        results
      end
    end

    def export_configs
      @export_configs ||= begin
        parent_ids_for_filter.each_slice(json_export_max_ids_in_filter).to_a.map do |parent_id_batch|
          ids_string = "{'#{parent_id_batch.join('\',\'')}'}" # Turn parent_id_batch into "{'123','456','789'}"
          filter = "='#{PROPERTY_PRODUCT_ID}':#{ids_string}='#{PROPERTY_PARENT_PRODUCT}':#{ids_string}"
          salsify_helper.export_config(filter: filter, export_format: 'csv', properties: properties_for_full_export, compress: false, product_type: 'all')
        end
      end
    end

    def initial_check_updated_products_count
      @initial_check_updated_products_count ||= salsify_helper.count_products_matching_filter(filter_string: updated_products_filter_string)
    end

    # Export products (base and sku) modified between start_datetime and to_datetime
    def updated_product_by_id
      @updated_product_by_id ||= begin
        t = Time.now
        result = salsify_helper.parse_product_by_id_from_csv_export(
          salsify_helper.run_export(
            salsify_helper.export_config(filter: updated_products_filter_string, export_format: 'csv', properties: properties_for_updated_export)
          )
        ).select { |id, product| DateTime.parse(product['salsify:updated_at']) > since_datetime } # unmodified parents could come along

        puts "#{STAMP} Found #{result.length} modified products since #{since_datetime.to_s} (Export took #{((Time.now - t) / 60).round(1)} mins)"
        result
      end
    end

    def updated_grouping_child_lookup
      @updated_grouping_child_lookup ||= updated_product_by_id.select do |id, product|
        product[PROPERTY_GROUPING_TYPE] && (product[PROPERTY_CHILD_STYLES_OF_GROUP] || product[PROPERTY_CHILD_SKUS_OF_GROUP])
      end.map do |id, product|
        [id, [product[PROPERTY_CHILD_STYLES_OF_GROUP], product[PROPERTY_CHILD_SKUS_OF_GROUP]].flatten.compact]
      end.to_h
    end

    def updated_products_filter_string
      @updated_products_filter_string ||= "='salsify:updated_at':gt('#{since_datetime.to_s}')," +
                    "'salsify:updated_at':lt('#{to_datetime.to_s}')" +
                    ":product_type:all"
    end

    def parent_ids_for_filter
      @parent_ids_for_filter ||= [
        updated_product_by_id.map { |id, pr| pr['salsify:parent_id'] || id },
        affected_grouping_by_id.keys,
        grouping_child_style_ids,
        parent_ids_of_grouping_child_skus
      ].flatten.compact.uniq
    end

    # Need to query for sku children of affected groupings to get the parent style ids of those skus
    def parent_ids_of_grouping_child_skus
      @parent_ids_of_grouping_child_skus ||= begin
        count = 0
        total = grouping_child_sku_ids.each_slice(MAX_PRODUCTS_PER_CRUD).to_a.length
        t = Time.now
        puts "#{STAMP} Querying for parent style IDs of #{grouping_child_sku_ids.length} sku children of affected groupings, split into #{total} CRUD queries of #{MAX_PRODUCTS_PER_CRUD} IDs each."
        result = grouping_child_sku_ids.each_slice(MAX_PRODUCTS_PER_CRUD).map do |sku_id_batch|
          count += 1
          res = salsify_helper.salsify.products(sku_id_batch).map { |sku| sku['salsify:parent_id'] }
          puts "#{STAMP} Retrieving grouping child sku batches (#{count}/#{total}) (elapsed time #{((Time.now - t) / 60).round(1)} min)" if count % LOG_INTERVAL_GROUPING_SKUS == 0
          res
        end.flatten.compact.uniq
        puts "#{STAMP} Retrieved #{result.length} grouping child sku IDs in #{((Time.now - t) / 60).round(1)} minutes"
        result
      end
    end

    # Identify grouping products which would be affected by these updates
    def affected_grouping_by_id
      @affected_grouping_by_id ||= begin
        puts "#{STAMP} Determining affected grouping products (elapsed time so far #{((Time.now - start_datetime.to_time) / 60).round(1)} mins)"
        t = Time.now
        result = Parallel.map(
          exported_grouping_products.to_a.in_groups(num_threads_local_processing, false),
          in_threads: num_threads_local_processing
        ) do |grouping_product_batch|
          grouping_product_batch.select do |_, grouping_product|
            is_grouping_affected?(grouping_product)
          end.to_h
        end.reduce({}, :merge)
        puts "#{STAMP} Identified #{result.length} affected grouping products in #{((Time.now - t) / 60).round(1)} min"
        result
      end
    end

    # IDs of groupings which were updated or affected by an updated style/sku
    def relevant_grouping_ids
      @relevant_grouping_ids ||= [
        updated_product_by_id.select { |id, pr|
          pr['salsify:parent_id'].nil? && pr[PROPERTY_GROUPING_TYPE]
        }.keys,
        affected_grouping_by_id.keys
      ].flatten.compact.uniq
    end

    def grouping_child_style_ids
      @grouping_child_style_ids ||= relevant_grouping_ids.map do |id|
        updated_product_by_id[id] || affected_grouping_by_id[id]
      end.map do |grouping_hash|
        grouping_hash ? grouping_hash[PROPERTY_CHILD_STYLES_OF_GROUP] : nil
      end.flatten.compact.uniq
    end

    def grouping_child_sku_ids
      @grouping_child_sku_ids ||= relevant_grouping_ids.map do |id|
        updated_product_by_id[id] || affected_grouping_by_id[id]
      end.map do |grouping_hash|
        grouping_hash ? grouping_hash[PROPERTY_CHILD_SKUS_OF_GROUP] : nil
      end.flatten.compact.uniq
    end

    def exported_grouping_products
      @exported_grouping_products ||= begin
        puts "#{STAMP} Exporting grouping products to determine which would be affected by updated products"
        t = Time.now
        result = salsify_helper.parse_product_by_id_from_csv_export(
          salsify_helper.run_export(
            salsify_helper.export_config(
              filter: "='#{PROPERTY_GROUPING_TYPE}':*,'#{PROPERTY_CHILD_STYLES_OF_GROUP}':*='#{PROPERTY_GROUPING_TYPE}':*,'#{PROPERTY_CHILD_SKUS_OF_GROUP}':*",
              properties: properties_for_grouping_export,
              export_format: 'csv'
            )
          )
        )
        puts "#{STAMP} Retrieved #{result.length} grouping products  (Export took #{((Time.now - t) / 60).round(1)} mins)"
        result
      end
    end

    # Check if a grouping has any child styles/skus which are mentioned in updated_product_by_id,
    # or if there's a grouping which lists this grouping as a child
    def is_grouping_affected?(grouping_product)
      grouping_skus = [grouping_product[PROPERTY_CHILD_SKUS_OF_GROUP]].flatten
      grouping_styles = [grouping_product[PROPERTY_CHILD_STYLES_OF_GROUP]].flatten
      child_ids = [grouping_skus, grouping_styles].flatten.compact.uniq

      intersect?(child_ids, updated_and_parent_ids) ||
      updated_grouping_child_lookup.any? { |updated_grouping_id, child_ids|
        child_ids.include?(grouping_product['salsify:id'])
      }
    end

    def updated_and_parent_ids
      @updated_and_parent_ids ||= [
        updated_product_by_id.keys,
        updated_product_by_id.map { |id, product| product['salsify:parent_id'] }
      ].flatten.compact.uniq
    end

    def properties_for_full_export
      @properties_for_full_export ||= begin
        [
          DW_REQUIRED_PROPERTIES,
          dw_configured_attributes.map { |att| att['salsify:id'] },
          attributes.select { |att| att['salsify:id'].downcase.include?('scene7') }.map { |att| att['salsify:id'] },
          dictionary_attributes.map(&:id)
        ].flatten.compact.uniq
      end
    end

    def dw_configured_attributes
      @dw_configured_attributes ||= begin
        attributes.select do |attribute|
          attribute[DW_META_SOURCE_LEVEL] &&
          attribute[DW_META_XML_LEVEL] &&
          attribute[DW_META_XML_PATH]
        end
      end
    end

    def attributes
      @attributes ||= begin
        t = Time.now
        puts "#{STAMP} Exporting attributes from org #{ENV.fetch('CARS_ORG_ID')}"
        a = salsify_helper.export_attributes.map { |att|
          att.map { |key, val| [key.to_s, val.is_a?(Array) ? val.map { |v| v.to_s } : val.to_s] }.to_h
        }
        puts "#{STAMP} Retrieved org attributes in #{((Time.now - t) / 60).round(1)} min"
        a
      end
    end

    def dictionary_attributes
      @dictionary_attributes ||= begin
        tries = 0
        begin
          t = Time.now
          puts "#{STAMP} Retrieving data dictionary from Google Drive"
          a = data_dictionary.attributes
          puts "#{STAMP} Retrieved data dictionary in #{((Time.now - t) / 60).round(1)} min"
          a
        rescue Exception => e
          if tries < MAX_TRIES_DATA_DICT
            puts "#{STAMP} WARNING error while pulling data dictionary, sleeping and retrying: #{e.message}\n#{e.backtrace.join("\n")}"
            sleep SLEEP_RETRY_DATA_DICT
            tries += 1
            retry
          else
            puts "#{STAMP} ERROR while pulling data dictionary, failed #{MAX_TRIES_DATA_DICT} times, error is: #{e.message}\n#{e.backtrace.join("\n")}"
          end
        end
      end
    end

    def data_dictionary
      @data_dictionary ||= Enrichment::Dictionary.new
    end

    # Return true if array1 and array2 share any common elements EXCEPT nil
    def intersect?(array1, array2)
      !((array1 & array2) - [nil]).empty?
    end

    def create_and_upload_family_hashes
      if batched_families.empty? && full_export_groupings.empty?
        puts "#{STAMP} No changes to record between #{since_datetime.to_s} and #{to_datetime.to_s}, done!"
        return []
      end

      puts "#{STAMP} Writing #{batched_families.length} json files of modified products to disk, #{max_families_per_json} max families per file"
      recursive_init_dir(LOCAL_PATH_UPDATED_PRODUCTS_JSON)
      since_stamp = since_datetime.in_time_zone('America/New_York').strftime('%Y%m%d_%H%M%S_%Z')
      to_stamp = to_datetime.in_time_zone('America/New_York').strftime('%Y%m%d_%H%M%S_%Z')

      t = Time.now
      filepaths = batched_families.each_with_index.map do |family_batch, index|
        filename = FILENAME_UPDATED_PRODUCTS_JSON.gsub('.json', "_#{since_stamp}_#{to_stamp}_#{index}.json")
        product_by_id = family_batch.values.reduce({}, :merge).merge(full_export_groupings)
        local_filepath = File.join(LOCAL_PATH_UPDATED_PRODUCTS_JSON, filename)
        File.open(local_filepath, 'w') { |file| file.write(Oj.dump(product_by_id)) }
        puts "#{STAMP} Wrote modified product json file (#{(index + 1)}/#{batched_families.length})"
        local_filepath
      end
      puts "#{STAMP} Done writing modified product json files, took #{((Time.now - t) / 60).round(1)} minutes"

      if ENV['testing'] != 'true'
        puts "#{STAMP} Uploading #{filepaths.length} generated json files to S3"
        t = Time.now
        filepaths.each_with_index do |filepath, index|
          s3_helper.upload_resource_to_s3(s3_bucket, File.join(s3_folder, filepath.split('/').last), filepath)
          puts "#{STAMP} Uploaded #{filepath.split('/').last} (#{(index + 1)}/#{filepaths.length})"
        end
        puts "#{STAMP} Done uploading json files, took #{((Time.now - t) / 60).round(1)} minutes"
      end
      filepaths
    end

    def recursive_init_dir(path, level = 0)
      pieces = path.split('/')
      return if level >= pieces.length
      dir = pieces[0..level].join('/')
      Dir.mkdir(dir) unless File.exists?(dir)
      recursive_init_dir(path, level + 1)
    end

    def send_change_record_started_email(num_updated_products, datetime)
      RRDonnelley::Mailer.send_mail(
        recipients: EMAIL_RECIPIENTS,
        subject: "Started Belk Export of Updated Products",
        message: "<p>A Belk export of modified products and their product families has started.  " +
          "You will be notified when the Demandware xml generation is complete.</p>" +
          "<p># Modified Products: #{num_updated_products}</p>"+
          "<p>Timeframe: #{datetime.utc.to_s} - #{to_datetime.to_s}</p>"
      )
    end

    def num_threads_local_processing
      @num_threads_local_processing ||= ENV.fetch('DW_NUM_THREADS_LOCAL_PROCESSING').to_i
    end

    def num_threads_json_exports
      @num_threads_json_exports ||= ENV.fetch('DW_NUM_THREADS_JSON_EXPORTS').to_i
    end

    def json_export_max_ids_in_filter
      @json_export_max_ids_in_filter ||= ENV.fetch('DW_JSON_EXPORT_MAX_IDS_IN_FILTER').to_i
    end

    def timestamp_s3_key
      @timestamp_s3_key ||= mode == :prod ? S3_KEY_CHANGES_TIMESTAMP_PROD : S3_KEY_CHANGES_TIMESTAMP_TEST
    end

    def max_families_per_json
      @max_families_per_json ||= ENV.fetch('DW_MAX_FAMILIES_PER_JSON').to_i
    end

    def update_last_record_timestamp
      puts "#{STAMP} Updating last record timestamp to #{to_datetime.to_s}"
      s3_helper.upload_to_s3(
        s3_bucket,
        timestamp_s3_key,
        to_datetime.to_s
      )
    end

    def properties_for_updated_export
      [PROPERTY_PRODUCT_ID, PROPERTY_PARENT_PRODUCT, PROPERTY_GROUPING_TYPE, PROPERTY_CHILD_STYLES_OF_GROUP, PROPERTY_CHILD_SKUS_OF_GROUP, 'salsify:updated_at']
    end

    def properties_for_grouping_export
      [PROPERTY_PRODUCT_ID, PROPERTY_CHILD_STYLES_OF_GROUP, PROPERTY_CHILD_SKUS_OF_GROUP, 'salsify:updated_at']
    end

  end

end
