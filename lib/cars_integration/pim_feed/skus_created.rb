class SkusCreated
  include Muffin::SalsifyClient

  STAMP = '$SKU$'.freeze
  MAX_IDS_PER_CRUD = 100.freeze
  MAX_IDS_PER_FILTER = 20.freeze
  MAX_TRIES = 3.freeze
  NUM_THREADS_CRUD = 4.freeze
  SLEEP_BEFORE_REQUERY = 10.freeze

  PROPERTY_ALL_IMAGES = 'All Images'.freeze
  PROPERTY_COLOR_MASTER = 'Color Master?'.freeze
  PROPERTY_NEW_SKU = 'new_sku'.freeze
  PROPERTY_NRF_COLOR_CODE = 'nrfColorCode'.freeze
  PROPERTY_PARENT_PRODUCT_ID = 'Parent Product'.freeze

  def self.process_new_skus
    new.process_new_skus
  end

  def process_new_skus
    puts "#{STAMP} Processing new skus, re-evaluating color masters and All Images"
    evaluate_color_masters
    calculate_all_images
    apply_flags
    run_updates
    puts "#{STAMP} Done!"
  end

  def evaluate_color_masters
    all_skus_by_style_id.each do |style_id, skus|
      ColorMasters.evaluate_color_masters(
        style_by_id[style_id],
        skus
      ).each do |product_id, change_hash|
        updates_by_product_id[product_id] ||= {}
        updates_by_product_id[product_id].merge!(change_hash)
      end
    end
  end

  def calculate_all_images
    all_skus_by_style_id.each do |style_id, skus|
      style = style_by_id[style_id]
      family_by_id = skus.map do |sku|
        [sku['salsify:id'], sku]
      end.to_h.merge({ style_id => style })
      PIMFeed::SalsifyImportFile::AddImagesToStyle.run(family_by_id)
      updates_by_product_id[style_id] ||= {}
      updates_by_product_id[style_id][PROPERTY_ALL_IMAGES] = family_by_id[style_id][PROPERTY_ALL_IMAGES]
      skus.each do |sku|
        updates_by_product_id[sku['salsify:id']] ||= {}
        updates_by_product_id[sku['salsify:id']][PROPERTY_ALL_IMAGES] = ' '
      end
    end
  end

  def apply_flags
    new_skus_by_parent_id.each do |style_id, skus|
      skus.each do |sku|
        updates_by_product_id[sku['salsify:id']] ||= {}
        updates_by_product_id[sku['salsify:id']][PROPERTY_NEW_SKU] = nil
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
    @all_sku_ids ||= new_skus_by_parent_id.keys.compact.each_slice(MAX_IDS_PER_FILTER).map do |style_id_batch|
      filter.find_children(parent_ids: style_id_batch)
    end.flatten.map do |partial_sku|
      partial_sku['salsify:id']
    end.uniq
  end

  def new_skus_by_parent_id
    @new_skus_by_parent_id ||= sku_ids_from_new_skus_list.each_slice(MAX_IDS_PER_CRUD).map do |id_batch|
      client.products(id_batch)
    end.flatten.group_by do |sku|
      sku['salsify:parent_id']
    end
  end

  def sku_ids_from_new_skus_list
    @sku_ids_from_new_skus_list ||= begin
      puts "#{STAMP} Retrieving skus from new skus list #{ENV.fetch('LIST_ID_NEW_SKUS')}"
      sku_ids = get_product_ids_on_list(ENV.fetch('LIST_ID_NEW_SKUS').to_i)
      puts "#{STAMP} Found #{sku_ids.length} products on new skus list"
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
    @style_by_id ||= new_skus_by_parent_id.keys.compact.each_slice(MAX_IDS_PER_CRUD).map do |style_id_batch|
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
