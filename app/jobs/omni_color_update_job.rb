class OmniColorUpdateJob < Struct.new(:products)
  include Muffin::SalsifyClient

  PROPERTY_COLOR_CODE = 'nrfColorCode'.freeze
  PROPERTY_OMNI_COLOR = 'omniChannelColorDescription'.freeze
  PROPERTY_COLOR_MASTER = 'Color Master?'.freeze
  PROPERTY_PARENT_PRODUCT = 'Parent Product'.freeze

  def perform
    tries = 0
    puts "$OMNI COLOR UPDATE$ Omni color update job queued for product IDs: #{updated_color_masters.map { |product| product['salsify:id'] }.join(', ')}"

    updated_color_masters.each do |updated_product|
      next unless skus_by_color_code_by_parent_id[updated_product[PROPERTY_PARENT_PRODUCT]]
      # Find sibling skus with same color code
      same_color_siblings = skus_by_color_code_by_parent_id[updated_product[PROPERTY_PARENT_PRODUCT]][updated_product[PROPERTY_COLOR_CODE]]
      next unless same_color_siblings
      same_color_siblings.each do |sibling|
        next if sibling['salsify:id'] == updated_product['salsify:id'] || sibling[PROPERTY_COLOR_MASTER]
        client.update_product(sibling['salsify:id'], { PROPERTY_OMNI_COLOR => updated_product[PROPERTY_OMNI_COLOR] })
      end
    end
    puts "$OMNI COLOR UPDATE$ Done with color update job"
  rescue Errno::ECONNRESET, OpenSSL::SSL::SSLError, RestClient::RequestTimeout, Net::HTTPServerException => e
    if tries < 3
      tries += 1
      sleep 5
      retry
    else
      puts "$OMNI COLOR UPDATE$ Failed 3 times, error is #{e.class}, raising exception"
      raise e
    end
  end

  def updated_color_masters
    @updated_color_masters ||= products.map do |param|
      param.to_unsafe_h
    end.select do |product|
      product[PROPERTY_COLOR_MASTER] && product[PROPERTY_COLOR_CODE] && product[PROPERTY_PARENT_PRODUCT]
    end
  end

  def parent_ids
    @parent_ids ||= updated_color_masters.map { |product| product['salsify:parent_id'] }.compact.uniq
  end

  def skus_by_color_code_by_parent_id
    @skus_by_color_code_by_parent_id ||= begin
      filter_products(
        filter: filter_string,
        properties: [PROPERTY_PARENT_PRODUCT, PROPERTY_COLOR_CODE, PROPERTY_COLOR_MASTER]
      ).group_by do |product|
        parent_property = product.properties.find do |property|
          property['id'] == PROPERTY_PARENT_PRODUCT
        end
        if parent_property
          parent_property['values'].first['id']
        else
          nil
        end
      end.map do |parent_id, skus|
        [
          parent_id,
          skus.map { |sku|
            # Turn weird filter api hash into regular property => value hash
            { 'salsify:id' => sku['id'] }.merge(
              sku.properties.map { |prop|
                values = prop['values'].map { |v| v['id'] }
                [prop['id'], values.length > 1 ? values : values.first]
              }.to_h
            )
          }.group_by { |sku| sku[PROPERTY_COLOR_CODE] }
        ]
      end.to_h
    end
  end

  def filter_string
    @filter_string ||= "='#{PROPERTY_PARENT_PRODUCT}':{#{parent_ids.map { |parent_id| "'#{parent_id}'" }.join(',')}}:product_type:leaf"
  end

  def filter_products(filter:, properties:, page: 1, per_page: 100)
    result = client.products_filtered_by(filter: filter, selections: properties, page: page, per_page: per_page)
    if (page * per_page) < result.meta.total_entries
      result.products.concat(filter_products(filter: filter, properties: properties, page: page + 1, per_page: per_page))
    else
      result.products
    end
  end

  def client
    @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
  end

end
