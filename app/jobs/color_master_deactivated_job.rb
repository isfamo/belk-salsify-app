class ColorMasterDeactivatedJob < Struct.new(:products)
  include Muffin::SalsifyClient

  STAMP = '$SKU$'.freeze
  MAX_IDS_PER_CRUD = 100.freeze
  MAX_IDS_PER_FILTER = 20.freeze
  NUM_THREADS_CRUD = 4.freeze

  PROPERTY_PARENT_PRODUCT_ID = 'Parent Product'.freeze

  def perform
    puts "#{STAMP} ColorMasterDeactivatedJob started for #{products.length} products"
    evaluate_color_masters
    run_updates
    puts "#{STAMP} Done with ColorMasterDeactivatedJob!"
  rescue Exception => e
    puts "#{STAMP} ERROR in ColorMasterDeactivatedJob: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def evaluate_color_masters
    skus_by_style_id.each do |style_id, skus|
      ColorMasters.evaluate_color_masters(
        style_by_id[style_id],
        skus
      ).each do |product_id, change_hash|
        updates_by_product_id[product_id] ||= {}
        updates_by_product_id[product_id].merge!(change_hash)
      end
    end
  end

  def run_updates
    puts "#{STAMP} Applying updates to #{updates_by_product_id.length} products, #{NUM_THREADS_CRUD} threads in parallel"
    Parallel.each(updates_by_product_id, in_threads: NUM_THREADS_CRUD) do |product_id, update_hash|
      client.update_product(product_id, update_hash)
    end
  end

  def skus_by_style_id
    @skus_by_style_id ||= sku_ids.each_slice(MAX_IDS_PER_CRUD).map do |sku_id_batch|
      client.products(sku_id_batch)
    end.flatten.uniq do |sku|
      sku['salsify:id']
    end.group_by do |sku|
      sku[PROPERTY_PARENT_PRODUCT_ID]
    end
  end

  def sku_ids
    @sku_ids ||= updated_products_by_parent_id.keys.compact.each_slice(MAX_IDS_PER_FILTER).map do |style_id_batch|
      filter.find_children(parent_ids: style_id_batch)
    end.flatten.map do |partial_sku|
      partial_sku['salsify:id']
    end.uniq
  end

  def updated_products_by_parent_id
    @updated_products_by_parent_id ||= products.group_by do |product|
      product['salsify:parent_id']
    end
  end

  def style_by_id
    @style_by_id ||= updated_products_by_parent_id.keys.compact.each_slice(MAX_IDS_PER_CRUD).map do |style_id_batch|
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
