class SetDefaultSkuJob < Struct.new(:products)
  include Muffin::SalsifyClient

  DEFAULT_SKU_IMPORT_FILE_PATH = './tmp/cache/default_sku_update.csv'.freeze
  DEFAULT_SKU_IMPORT_ID = 181428.freeze

  PROPERTY_IS_DEFAULT_SKU = 'Is Default SKU?'.freeze
  PROPERTY_DEFAULT_SKU_CODE = 'Default_SKU_Code'.freeze

  def perform
    puts "Default sku update job queued for #{updated_products.count} products -- product IDs: #{updated_products.map { |product| product['salsify:id'] }.join(', ')}"
    init_dirs
    updated_products.each do |updated_product|
      parent_id = updated_product['salsify:parent_id']
      next unless parent_id
      client.update_product(parent_id, { PROPERTY_DEFAULT_SKU_CODE => updated_product['salsify:id'] })
      sku_ids_by_parent_id[parent_id].each do |sku_id|
        next if sku_id == updated_product['salsify:id']
        client.update_product(sku_id, { PROPERTY_IS_DEFAULT_SKU => false })
      end
    end
    puts "Done with default sku update job"
  end

  def init_dirs
    Dir.mkdir('./tmp') unless File.exists?('./tmp')
    Dir.mkdir('./tmp/cache') unless File.exists?('./tmp/cache')
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

  def client
    @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
  end

end
