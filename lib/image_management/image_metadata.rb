module ImageManagement
  class ImageMetadata
    include Muffin::SalsifyClient
    include Helpers

    attr_reader :products

    def initialize(products)
      @products = products
      @count = 0
    end

    def self.process_metadata(products)
      new(products).process_metadata
    end

    def process_metadata
      puts "#{STAMP} Processing metadata for #{products.length} skus"

      asset_ids_by_sku_id.each do |sku_id, asset_ids|
        process_sku_and_assets(sku_id, asset_ids)
      end

      execute_asset_updates
      execute_product_updates
      execute_list_updates
    end

    # Handle image metadata updates and style updates for this sku and its assets
    def process_sku_and_assets(sku_id, asset_ids)
      @count += 1
      sku = sku_by_id[sku_id]
      parent = sku['salsify:parent_id'] ? style_by_id[sku['salsify:parent_id']] : sku
      parent_id = parent['salsify:id']

      # Don't reprocess this style/color if we've already processed it
      return if flagged_colors_by_parent_id[parent_id] && flagged_colors_by_parent_id[parent_id][sku[PROPERTY_COLOR_CODE]]

      # Mark that we've processed this style/color
      flagged_colors_by_parent_id[parent_id] ||= {}
      flagged_colors_by_parent_id[parent_id][sku[PROPERTY_COLOR_CODE]] = true

      puts "#{STAMP} Processing image metadata on #{sku_id} (#{@count}/#{asset_ids_by_sku_id.length})"
      metadata_changed = nil
      asset_ids.each do |asset_id|
        result = process_metadata_for_asset(asset_id, sku, parent)
        metadata_changed = true if result
      end

      # Mark parent/sku as long as >=1 assets are getting metadata updated
      return unless metadata_changed
      if parent
        product_updates_by_id[parent['salsify:id']] = { PROPERTY_SKU_IMAGES_UPDATED => true }
        product_updates_by_id[sku_id] = {
          PROPERTY_IMAGE_TASK_STATUS => 'Open',
          PROPERTY_IMAGE_TASK_COMPLETE => nil
        }
      else
        product_updates_by_id[sku_id] = {
          PROPERTY_SKU_IMAGES_UPDATED => true,
          PROPERTY_IMAGE_TASK_STATUS => 'Open',
          PROPERTY_IMAGE_TASK_COMPLETE => nil
        }
      end
    end

    # Check if this asset's metadata already includes info about this style/color.
    # If not, add it. If so, move on.
    # Add pending changes to asset_updates_by_id.
    def process_metadata_for_asset(asset_id, sku, parent)
      asset = asset_by_id[asset_id]
      if [nil, ''].include?(asset[PROPERTY_IMAGE_METADATA])
        image_metadata = {}
      else
        image_metadata = JSON.parse(asset[PROPERTY_IMAGE_METADATA])
      end

      key = json_key(parent, sku)
      shot_type = find_shot_type(sku, asset)
      file_type = asset['salsify:format']
      if shot_type.nil? || file_type.nil?
        puts "#{STAMP} Skipping asset #{asset_id} because of missing shot type or file type, shot type = #{shot_type}, file type = #{file_type}"
        return
      end

      filename = image_filename(parent, sku, shot_type, file_type)
      if image_metadata[key] && image_metadata[key]['filename'] == filename
        puts "#{STAMP} Skipping asset #{asset_id} because key #{key} already exists with identical filename #{filename}"
        return
      end

      asset_updates_by_id[asset_id] = {
        PROPERTY_IMAGE_METADATA => image_metadata.merge({
          key => {
            'filename' => image_filename(parent, sku, shot_type, file_type),
            'sent_to_belk' => false
          }
        }).to_json
      }

      return true
    rescue JSON::ParserError => e
      puts "#{STAMP} Error while generating metadata: #{e.message}\n#{e.backtrace}"
    end

    def json_key(style, sku)
      # Key of the image metadata hash is parentID_colorCode
      # Or use sku ID for grouping products as they don't have parents
      style && sku[PROPERTY_COLOR_CODE] ? "#{style['salsify:id']}_#{sku[PROPERTY_COLOR_CODE]}" : "#{sku['salsify:id']}_000"
    end

    def execute_asset_updates
      t = Time.now
      puts "#{STAMP} Updating #{asset_updates_by_id.length} assets with image metadata..."
      asset_updates_by_id.each do |asset_id, update_hash|
        client.update_asset(asset_id, update_hash)
      end
      puts "#{STAMP} Done updating #{asset_updates_by_id.length} assets, took #{((Time.now - t) / 60).round(1)} minutes"
    end

    def execute_product_updates
      t = Time.now
      puts "#{STAMP} Updating #{product_updates_by_id.length} products based on updated assets..."
      product_updates_by_id.each do |product_id, update_hash|
        client.update_product(product_id, update_hash)
      end
      puts "#{STAMP} Done updating #{product_updates_by_id.length} products, took #{((Time.now - t) / 60).round(1)} minutes"
    end

    def execute_list_updates
      t = Time.now
      list_ids = query_lists('pip user list').map { |list| list['id'] }
      puts "#{STAMP} Removing reopened products from #{list_ids.length} PIP user lists so they go back to assignment queue, took #{(Time.now - t).round(1)} seconds to query lists"
      t = Time.now
      Parallel.each(list_ids, in_threads: NUM_THREADS_CRUD) do |list_id|
        begin
          update_list(list_id: list_id, removals: product_updates_by_id.keys)
        rescue Exception => e
          puts "#{STAMP} ERROR while updating list #{list_id} to remove #{product_updates_by_id.length} products from list, moving on but error is: #{e.message}"
        end
      end
      puts "#{STAMP} Done updating #{list_ids.length} PIP user lists to move reopened products back to assignment queue, took #{((Time.now - t) / 60).round(1)} minutes to update lists"
    end

    def sku_by_id
      @sku_by_id ||= products.map do |sku|
        sku.is_a?(Hash) ? [sku['salsify:id'], sku] : [sku['salsify:id'], sku.to_unsafe_h]
      end.to_h
    end

    def sku_parent_ids
      @sku_parent_ids ||= sku_by_id.values.map do |sku|
        sku['salsify:parent_id']
      end.compact.uniq
    end

    def style_by_id
      @style_by_id ||= sku_parent_ids.each_slice(MAX_PRODUCTS_PER_CRUD).map do |parent_id_batch|
        client.products(parent_id_batch).map do |style|
          [style['salsify:id'], style.to_h]
        end.to_h
      end.reduce({}, :merge)
    end

    def asset_ids_by_sku_id
      @asset_ids_by_sku_id ||= products.map do |sku|
        [sku['salsify:id'], sku.select { |key, value|
          key.downcase.include?('imagepath')
        }.values.flatten.uniq]
      end.to_h
    end

    def flagged_colors_by_parent_id
      @flagged_colors_by_parent_id ||= {}
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

    def asset_updates_by_id
      @asset_updates_by_id ||= {}
    end

    def product_updates_by_id
      @product_updates_by_id ||= {}
    end

    def org_id
      @org_id ||= ENV['CARS_ORG_ID'].to_i
    end

    def client
      @client ||= salsify_client(org_id: org_id)
    end

    def find_shot_type(sku, asset)
      prop_value_pair = sku.find do |key, value|
        (value.is_a?(String) && value == asset['salsify:id']) ||
        (value.is_a?(Array) && value.include?(asset['salsify:id']))
      end
      return nil unless prop_value_pair
      match = prop_value_pair.first.match(/^.+-\ (.+)\ -.+$/)
      match ? match[1] : nil
    end

    def image_filename(parent, sku, shot_type, file_type)
      if [nil, ''].include?(sku[PROPERTY_COLOR_CODE])
        "#{sku['salsify:id'][0..6]}_" +
        "#{sku['salsify:id'][7..-1]}_" +
        "#{shot_type.strip}_" +
        "000.#{file_type}"
      else
        "#{parent['salsify:id'][0..6]}_" +
        "#{parent['salsify:id'][7..-1]}_" +
        "#{shot_type.strip}_" +
        "#{sku[PROPERTY_COLOR_CODE].strip}.#{file_type}"
      end
    end

  end
end
