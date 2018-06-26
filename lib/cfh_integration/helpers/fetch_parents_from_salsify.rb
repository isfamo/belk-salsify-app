class FetchParentsFromSalsify
  include Muffin::SalsifyClient

  PARENT_TO_VARIANT_INCREMENTAL_LIST_ID = 49935
  PARENT_TO_VARIANT_ON_DEMAND_LIST_ID = 50298

  attr_reader :mode, :skus

  def initialize(skus = nil)
    @mode = skus ? :on_demand : :full
    @skus = skus
  end

  def self.run(skus = nil)
    new(skus).run
  end

  def run
    puts "fetching parent products from Salsify in #{mode} mode..."
    return if mode == :on_demand && skus.empty?
    products.each do |parent, variants|
      parent = create_parent(parent)
      variants.each { |variant| create_variant(variant, parent) }
      parent.save!
    end
  end

  def create_parent(parent)
    ParentProduct.find_or_create_by(product_id: parent['product_id'])
  end

  def create_variant(variant, parent)
    _sku = Sku.find_or_create_by(product_id: variant['product_id'])
    _sku.update_attributes(parent_id: parent['product_id'], parent_product_id: parent['id'])
  end

  def products
    Amadeus::Export::JsonExport.new(json_export: json_export, performance_mode: true).grouped_variants
  end

  def json_export
    puts 'replacing list...'
    replace_list(PARENT_TO_VARIANT_ON_DEMAND_LIST_ID, skus) if mode == :on_demand
    puts 'exporting products...'
    export_run = salsify_client.create_export_run(export_filter)
    response = Salsify::Utils::Export.wait_until_complete(salsify_client, export_run)
    puts 'export finished, upserting products...'
    JSON.parse(open(response.url).read)
  end

  def export_filter
    {
      'configuration': {
        'filter': "=list:#{ mode == :on_demand ? PARENT_TO_VARIANT_ON_DEMAND_LIST_ID : PARENT_TO_VARIANT_INCREMENTAL_LIST_ID}",
        'properties': '\'product_id\'',
        'include_all_columns': false,
        'entity_type': 'product',
        'format': 'json'
      }
    }
  end

end
