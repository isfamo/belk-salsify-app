class SalsifyFilter

  PROPERTY_PARENT_PRODUCT_ID = 'Parent Product'.freeze

  attr_reader :client

  def initialize(client)
    @client = client
  end

  def filter(filter_hash: nil, filter_string: nil, selections: nil)
    filter_products(
      filter_hash: filter_hash,
      filter_string: filter_string,
      selections: selections
    ).map { |filter_hash| parse_filter_hash(filter_hash) }
  end

  def find_children(parent_ids:, selections: [PROPERTY_PARENT_PRODUCT_ID])
    filter = "='#{PROPERTY_PARENT_PRODUCT_ID}':{#{[parent_ids].flatten.uniq.map { |id| "'#{id}'"}.join(',')}}"
    puts "Finding children using filter: #{filter}"
    filter_products(
      filter_string: filter,
      selections: selections
    ).map { |filter_hash| parse_filter_hash(filter_hash) }
  end

  def filter_products(filter_hash: nil, filter_string: nil, selections: nil, per_page: 100, page: 1)
    if selections
      result = client.products_filtered_by(filter_hash, filter: filter_string, selections: selections, per_page: per_page, page: page)
    else
      result = client.products_filtered_by(filter_hash, filter: filter_string, per_page: per_page, page: page)
    end
    products = result['products']
    if result['meta']['total_entries'] > (result['meta']['current_page'] * result['meta']['per_page'])
      products + filter_products(filter_hash: filter_hash, filter_string: filter_string, selections: selections, per_page: per_page, page: (page + 1))
    else
      products
    end
  end

  def filter_assets(filter_hash: nil, filter_string: nil, per_page: 100, page: 1)
    result = client.assets_filtered_by(filter_hash, filter: filter_string, selections: ['image_metadata'], per_page: per_page, page: page)
    assets = result['digital_assets']
    if result['meta']['total_entries'] > (result['meta']['current_page'] * result['meta']['per_page'])
      assets + filter_assets(filter_hash: filter_hash, filter_string: filter_string, per_page: per_page, page: (page + 1))
    else
      assets
    end
  end

  def parse_filter_hash(hash)
    { 'salsify:id' => hash['id'] }.merge(
      hash['properties'].map { |prop_hash|
        values = prop_hash['values'].map { |val| val['id'] }
        [prop_hash['id'], values.length > 1 ? values : values.first]
      }.to_h
    )
  end

end
