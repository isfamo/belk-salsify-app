class IlSkusConverted
  include Muffin::SalsifyClient

  STAMP = '$SKU_IL$'.freeze
  MAX_IDS_PER_CRUD = 100.freeze
  MAX_IDS_PER_FILTER = 20.freeze
  MAX_TRIES = 3.freeze
  NUM_THREADS_CRUD = 4.freeze

  PROPERTY_COLOR_MASTER = 'Color Master?'.freeze
  PROPERTY_GXS_DATA_CHECKED = 'GXS Data Retrieved'.freeze
  PROPERTY_DIGITAL_CONTENT_REQUIRED = 'digital_content_required'.freeze
  PROPERTY_IL_ELIGIBLE = 'il_eligible'.freeze
  PROPERTY_SWITCH_IL_TO_NORMAL = 'Switch IL to Normal'.freeze
  PROPERTY_NRF_COLOR_CODE = 'nrfColorCode'.freeze
  PROPERTY_PARENT_PRODUCT_ID = 'Parent Product'.freeze

  def initialize
  end

  def self.process_converted_il_skus
    new.process_converted_il_skus
  end

  def process_converted_il_skus
    puts "#{STAMP} Processing converted Il => normal skus, re-evaluating color masters"
    evaluate_color_masters
    apply_flags
    run_updates
    puts "#{STAMP} Done!"
  end

  def evaluate_color_masters
    all_skus_by_style_id.each do |style_id, skus|
      ColorMasters.evaluate_color_masters(
        style_by_id[style_id],
        skus.map do |sku|
          if sku[PROPERTY_SWITCH_IL_TO_NORMAL]
            # Ensure we treat this as a normal sku before evaluating
            # color masters, it will be once we run the update!
            sku.merge({ PROPERTY_IL_ELIGIBLE => 'false', PROPERTY_DIGITAL_CONTENT_REQUIRED => 'Y' })
          else
            sku
          end
        end
      ).each do |product_id, change_hash|
        updates_by_product_id[product_id] ||= {}
        updates_by_product_id[product_id].merge!(change_hash)
      end
    end
  end

  def apply_flags
    converted_skus_by_parent_id.each do |style_id, skus|
      skus.each do |sku|
        updates_by_product_id[sku['salsify:id']] ||= {}
        updates_by_product_id[sku['salsify:id']].merge!({
          PROPERTY_GXS_DATA_CHECKED => false,
          PROPERTY_DIGITAL_CONTENT_REQUIRED => 'Y',
          PROPERTY_IL_ELIGIBLE => 'false',
          PROPERTY_SWITCH_IL_TO_NORMAL => nil
        })
      end
    end
  end

  def run_updates
    puts "#{STAMP} Applying updates to #{updates_by_product_id.length} products, #{NUM_THREADS_CRUD} threads in parallel"
    Parallel.each(updates_by_product_id, in_threads: NUM_THREADS_CRUD) do |product_id, update_hash|
      puts "#{STAMP} Updating product #{product_id} with data: #{update_hash.to_json}"
      tries = 0
      begin
        client.update_product(product_id, update_hash)
      rescue Exception => e
        tries += 1
        if tries < MAX_TRIES
          sleep 3
          retry
        else
          puts "#{STAMP} ERROR while trying to update product #{product_id}, failed #{MAX_TRIES} times!"
        end
      end
    end
  end

  def all_skus_by_style_id
    @all_skus_by_style_id ||= all_sku_ids.each_slice(MAX_IDS_PER_CRUD).map do |sku_id_batch|
      client.products(sku_id_batch)
    end.flatten.uniq do |sku|
      sku['salsify:id']
    end.group_by do |sku|
      sku[PROPERTY_PARENT_PRODUCT_ID]
    end
  end

  def all_sku_ids
    @all_sku_ids ||= converted_skus_by_parent_id.keys.compact.each_slice(MAX_IDS_PER_FILTER).map do |style_id_batch|
      filter.find_children(parent_ids: style_id_batch)
    end.flatten.map do |partial_sku|
      partial_sku['salsify:id']
    end.uniq
  end

  def converted_skus_by_parent_id
    @converted_skus_by_parent_id ||= sku_ids_from_converted_skus_list.each_slice(MAX_IDS_PER_CRUD).map do |id_batch|
      client.products(id_batch)
    end.flatten.group_by do |sku|
      sku['salsify:parent_id']
    end
  end

  def sku_ids_from_converted_skus_list
    @sku_ids_from_converted_skus_list ||= begin
      puts "#{STAMP} Retrieving skus from converted skus list #{ENV.fetch('LIST_ID_IL_SKUS_TO_CONVERT')}"
      sku_ids = get_product_ids_on_list(ENV.fetch('LIST_ID_IL_SKUS_TO_CONVERT').to_i)
      puts "#{STAMP} Found #{sku_ids.length} products on converted skus list"
      sku_ids
    end
  end

  def get_product_ids_on_list(list_id, page = 1)
    result = client.products_on_list(list_id, page: page)
    if (result['meta']['total_entries'] > (page * result['meta']['per_page']))
      [result['products'].map { |pr| pr['id'] }, get_product_ids_on_list(list_id, page + 1)].flatten.uniq
    else
      result['products'].map { |pr| pr['id'] }
    end
  end

  def style_by_id
    @style_by_id ||= converted_skus_by_parent_id.keys.compact.each_slice(MAX_IDS_PER_CRUD).map do |style_id_batch|
      client.products(style_id_batch)
    end.flatten.map { |style| [style['salsify:id'], style] }.to_h
  end

  def updates_by_product_id
    @updates_by_product_id ||= {}
  end

  def filter
    @filter ||= SalsifyFilter.new(client)
  end

  def client
    @client ||= salsify_client(org_id: org_id)
  end

  def org_id
    @org_id ||= ENV.fetch('CARS_ORG_ID').to_i
  end

end
