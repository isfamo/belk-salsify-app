class ColorCodeUpdateJob < Struct.new(:products)
  include Muffin::SalsifyClient

  COLOR_MAPPING_JSON_LOCAL_PATH = './lib/cars_integration/cache/color_master_mapping_processed.json'.freeze
  COLOR_UPDATE_IMPORT_FILE_PATH = './tmp/cache/sku_color_update.csv'.freeze

  PROPERTY_COLOR_CODE = 'nrfColorCode'.freeze
  PROPERTY_REFINEMENT_COLOR = 'refinementColor'.freeze
  PROPERTY_COLOR_MASTER = 'Color Master?'.freeze

  MAX_TRIES = 3.freeze
  SLEEP_INTERVAL = 3.freeze

  def perform
    puts "$COLOR$ Color code update job queued for product IDs: #{updated_products.map { |product| product['salsify:id'] }.join(', ')}"
    init_dirs
    tries = 0

    begin
      sku_ids_to_add_to_list = []
      updated_products.each do |updated_product|
        next unless updated_product[PROPERTY_COLOR_CODE] &&
          updated_product[PROPERTY_COLOR_CODE].is_a?(String) &&
          updated_product[PROPERTY_COLOR_MASTER] == true

        new_color_code_int = updated_product[PROPERTY_COLOR_CODE].to_i

        # Determine info for the new color
        color_info_pair = color_mapping_hash.find do |color_id, color_hash|
          color_hash['color_code_begin'].to_i <= new_color_code_int &&
          color_hash['color_code_end'].to_i >= new_color_code_int
        end
        next unless color_info_pair
        # first is color id, second is hash
        color_info = color_info_pair.last

        # Update refinementColor on updated sku
        new_color_name = color_info['super_color_name']
        client.update_product(updated_product['salsify:id'], { PROPERTY_REFINEMENT_COLOR => new_color_name })
        sku_ids_to_add_to_list << updated_product['salsify:id']

        # Check if updated sku has a parent and siblings
        updated_product_parent_id = updated_product['salsify:parent_id']
        if updated_product_parent_id && skus_by_color_code_by_parent_id[updated_product_parent_id]
          sibling_by_id_by_color_code = skus_by_color_code_by_parent_id[updated_product_parent_id]

          # Check if this sku was moved to a color group which already has a master
          if sibling_by_id_by_color_code[updated_product[PROPERTY_COLOR_CODE]] &&
            sibling_by_id_by_color_code[updated_product[PROPERTY_COLOR_CODE]].any? { |sibling_id, sibling|
              sibling[PROPERTY_COLOR_MASTER] == true && sibling_id != updated_product['salsify:id']
            }
            # New color group already has a master, make the updated sku not a master
            puts "$COLOR$ #{updated_product['salsify:id']} - New color group #{updated_product[PROPERTY_COLOR_CODE]} already has a master, make the updated sku not a master"
            client.update_product(updated_product['salsify:id'], { PROPERTY_COLOR_MASTER => nil })
          end

          puts "$COLOR$ #{updated_product['salsify:id']} - Propagate color changes to old siblings"
          # Find sibling skus in a color group with no color master (old color which was changed)
          color_groups_with_master = []
          sibling_by_id_by_color_code.each do |color_code, sibling_by_id|
            color_groups_with_master << color_code if sibling_by_id.any? { |sibling_id, sibling| sibling[PROPERTY_COLOR_MASTER] }
          end

          # Update same color siblings with new color code and name
          same_color_sibling_by_id_pair = sibling_by_id_by_color_code.find do |color_code, sibling_by_id|
            !color_groups_with_master.include?(color_code)
          end
          next unless same_color_sibling_by_id_pair
          same_color_sibling_by_id = same_color_sibling_by_id_pair.last

          same_color_sibling_by_id.each do |sibling_id, sibling|
            next if sibling_id == updated_product['salsify:id']
            client.update_product(sibling_id, {
              PROPERTY_COLOR_CODE => updated_product[PROPERTY_COLOR_CODE],
              PROPERTY_REFINEMENT_COLOR => new_color_name
            })
            sku_ids_to_add_to_list << sibling_id
          end
        end
      end

      puts "$COLOR$ Done with color update job"
    rescue Errno::ECONNRESET, RestClient::InternalServerError, RestClient::ServiceUnavailable => e
      tries += 1
      if tries < MAX_TRIES
        sleep SLEEP_INTERVAL
        retry
      else
        puts "$COLOR$ ERROR in color code update job, failed #{MAX_TRIES} times, error: #{e.message}\n#{e.backtrace.join("\n")}"
        raise e
      end
    end
  end

  def init_dirs
    Dir.mkdir('./tmp') unless File.exists?('./tmp')
    Dir.mkdir('./tmp/cache') unless File.exists?('./tmp/cache')
  end

  def color_mapping_hash
    @color_mapping_hash ||= JSON.parse(File.read(COLOR_MAPPING_JSON_LOCAL_PATH))
  end

  def updated_products
    @updated_products ||= products.map { |param| param.to_unsafe_h }
  end

  def parent_ids
    @parent_ids ||= updated_products.map { |product| product['salsify:parent_id'] }.compact.uniq
  end

  def sku_ids_by_parent_id
    @sku_ids_by_parent_id ||= parent_ids.map do |parent_id|
      [parent_id, client.product_relatives(parent_id)['children'].map { |sku| sku['id'] }]
    end.to_h
  end

  def sku_by_id
    @sku_by_id ||= sku_ids_by_parent_id.values.flatten.uniq.compact.each_slice(100).map do |sku_id_batch|
      client.products(sku_id_batch)
    end.flatten.reject do |sku|
      sku.empty?
    end.map do |sku|
      [sku['salsify:id'], sku]
    end.to_h
  end

  def skus_by_color_code_by_parent_id
    @skus_by_color_code_by_parent_id ||= begin
      result = {}
      sku_by_id.each do |sku_id, sku|
        result[sku['salsify:parent_id']] = {} unless result[sku['salsify:parent_id']]
        result[sku['salsify:parent_id']][sku[PROPERTY_COLOR_CODE]] = {} unless result[sku['salsify:parent_id']][sku[PROPERTY_COLOR_CODE]]
        result[sku['salsify:parent_id']][sku[PROPERTY_COLOR_CODE]][sku_id] = sku
      end
      result
    end
  end

  def client
    @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
  end

end
