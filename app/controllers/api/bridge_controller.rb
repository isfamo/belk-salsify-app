class Api::BridgeController < ApplicationController

  NEWLINE = "\n".freeze
  PROPERTY_ID = 'salsify:id'.freeze
  PROPERTY_PARENT_PRODUCT = 'Parent Product'.freeze
  # They have ID vendorName (Vendor Name is the name) and also Vendor#
  #   they use those both and don't agree - seems Vendor# is more for groups
  # To not break it, just check # and if not there, then use the other.
  PROPERTY_COLOR_MASTER = 'Color Master?'.freeze
  PROPERTY_VENDOR_NUMBER = 'Vendor#'.freeze
  PROPERTY_STYLE_NUMBER = 'Style#'.freeze
  PROPERTY_GROUP_ORIN = 'Orin/Grouping #'.freeze
  PROPERTY_UPC = 'upc'.freeze
  PROPERTY_LONG_DESCRIPTION = 'Product Description'.freeze
  PROPERTY_OF_OR_SL = 'OForSL'.freeze
  PROPERTY_DISPLAY_NAME = 'Product Name'.freeze
  PROPERTY_COLOR_CODE = 'nrfColorCode'.freeze
  PROPERTY_COLOR_NAME = 'omniChannelColorDescription'.freeze
  PROPERTY_VENDOR_NAME = 'Vendor  Name'.freeze
  PROPERTY_SIZE_CODE = 'nrfSizeCode'.freeze
  PROPERTY_SIZE_DESC = 'omniSizeDesc'.freeze
  PROPERTY_ONLINE_FLAG = 'online_flag'.freeze

  def retrieve
    t = Time.now
    unless params['task_id']
      render status: 422, json: { error: 'No task_id param provided.' }
      return
    end

    task = RrdTaskId.find_by(id: params['task_id'])

    if task.nil?
      render status: 404, json: { error: "No matching record found for provided task_id #{params['task_id']}" }
      return
    end
    puts "$BRIDGE$ Found RrdTaskId record in #{(Time.now - t).round(1)} sec"

    begin
      puts "$BRIDGE$ Querying task ID #{params['task_id']}, product #{task.product_id}"
      # NOTE: We assume the task ID is on the parent product
      parent = client.product(task.product_id)
      skus = parse_skus(color_masters_for_parent_id(task.product_id))
      puts "$BRIDGE$ Found #{skus.length} color master skus"
      skus = [parent] if skus.empty?

      results = skus.map do |sku|
        key = "#{parent['salsify:id']}_#{sku[PROPERTY_COLOR_CODE]}"
        scene7_shot_types = sku.select do |property, value|
          property.downcase.include?('scene7')
        end.map do |property, value|
          match = property.match(/^.+-\ (.+)\ -.+$/)
          next unless match
          match[1]
        end.uniq.reject do |shot_type|
          [nil, ''].include?(shot_type)
        end

        if scene7_shot_types.empty?
          [
            bridge_json(
              parent: parent,
              sku: sku,
              vendor_num: parent[PROPERTY_ID][0..6],
              style_num: parent[PROPERTY_ID][7..-1]
            )
          ]
        else
          scene7_shot_types.map do |shot_type|
            main_img_pair = sku.find do |property, value|
              property.downcase.include?('scene7') &&
              property.downcase.include?('mainimage') &&
              property.downcase.include?('url') &&
              property.include?("- #{shot_type} -")
            end

            swatch_img_pair = sku.find do |property, value|
              property.downcase.include?('scene7') &&
              property.downcase.include?('swatchimage') &&
              property.downcase.include?('url') &&
              property.include?("- #{shot_type} -")
            end

            viewer_img_pair = sku.find do |property, value|
              property.downcase.include?('scene7') &&
              property.downcase.include?('viewerimage') &&
              property.downcase.include?('url') &&
              property.include?("- #{shot_type} -")
            end

            bridge_json(
              parent: parent,
              sku: sku,
              vendor_num: parent[PROPERTY_ID][0..6],
              style_num: parent[PROPERTY_ID][7..-1],
              shot: shot_type,
              main_url: main_img_pair ? main_img_pair.last : nil,
              swatch_url: swatch_img_pair ? swatch_img_pair.last : nil,
              viewer_url: viewer_img_pair ? viewer_img_pair.last : nil
            )
          end
        end
      end.flatten.compact
      puts "$BRIDGE$ Finished bridge query for task id #{params['task_id']} in #{(Time.now - t).round(1)} sec"

      render status: 200, json: results
    rescue RestClient::ResourceNotFound => e
      render status: 404, json: { error: "The queried task ID #{params['task_id']} is associated to product ID #{task.product_id} which was not found in the system." }
    rescue Exception => e
      render status: 500, json: { error: "Error occurred while retrieving task #{params['task_id']} from Salsify:\n#{e.message}\n#{e.backtrace.join(NEWLINE)}" }
    end
  end

  def bridge_json(parent:, sku:, vendor_num:, style_num:, shot: nil, main_url: nil, swatch_url: nil, viewer_url: nil)
    {
      'PRODUCTCODE' => parent[PROPERTY_ID],
      'PRODUCTNAME' => parent[PROPERTY_DISPLAY_NAME],
      'PARENT_PROD_CODE' => parent[PROPERTY_ID],
      'SKUCODE' => sku[PROPERTY_ID],
      'PRODUCT_PROD_CODE' => parent[PROPERTY_ID],
      'VENDOR_UPC' => sku[PROPERTY_UPC],
      'SKU_NAME' => sku[PROPERTY_DISPLAY_NAME],
      'SKU_DESCRIPTION' => sku[PROPERTY_LONG_DESCRIPTION] || parent[PROPERTY_LONG_DESCRIPTION],
      'STATUS_CD' => nil,
      'VENDORNAME' => parent[PROPERTY_VENDOR_NAME],
      'VENDORNUMBER' => vendor_num,
      'VENSTYLENUMBER' => style_num,
      'VENSTYLEDESCRIPTION' => parent[PROPERTY_LONG_DESCRIPTION],
      'COLOR_CODE' => sku[PROPERTY_COLOR_CODE],
      'COLOR_DESCRIPTION' => sku[PROPERTY_COLOR_NAME],
      'SIZE_CODE' => sku[PROPERTY_SIZE_CODE],
      'SIZE_DESCRIPTION' => sku[PROPERTY_SIZE_DESC],
      'BATCH_ID' => 'CARS',
      'CREATE_DT' => sku['salsify:created_at'],
      'MODIFY_DT' => sku['salsify:updated_at'],
      'WEBSTORE_SALE' => sku[PROPERTY_ONLINE_FLAG],
      'SET_IND' => nil,
      'IS_SET_BURSTABLE' => nil,
      'EXPECTED_SHIP_DT' => nil,
      'SENT_STATUS' => nil,
      'IMAGE_SHOT' => shot,
      'IMAGE_URL' => main_url,
      'SWATCH_URL' => swatch_url,
      'VIEWER_URL' => viewer_url
    }
  end

  def color_masters_for_parent_id(parent_id, page = 1)
    result = client.products_filtered_by(
      {
        PROPERTY_PARENT_PRODUCT => parent_id,
        PROPERTY_COLOR_MASTER => 'true'
      },
      selections: [
        PROPERTY_DISPLAY_NAME, PROPERTY_UPC, PROPERTY_LONG_DESCRIPTION, PROPERTY_VENDOR_NAME,
        PROPERTY_VENDOR_NUMBER, PROPERTY_STYLE_NUMBER, PROPERTY_COLOR_CODE, PROPERTY_COLOR_NAME,
        PROPERTY_SIZE_CODE, PROPERTY_SIZE_DESC, PROPERTY_ONLINE_FLAG, 'salsify:created_at', 'salsify:updated_at',
        scene_7_properties
      ].flatten.uniq,
      page: page
    )
    skus = result['products']
    if result['meta']['total_entries'] > (result['meta']['current_page'] * result['meta']['per_page'])
      skus + color_masters_for_parent_id(parent_id, page + 1)
    else
      skus
    end
  end

  def parse_skus(filtered_skus)
    filtered_skus.map do |sku|
      { 'salsify:id' => sku['id'] }.merge(
        sku['properties'].map do |property_hash|
          # Filter export gives property values using a different format, parse it
          [property_hash['id'], property_hash['values'].map { |value| value['id'] }]
        end.to_h.map do |key, value|
          # Reduce single length arrays to their one value
          [key, value.is_a?(Array) && value.length == 1 ? value.first : value]
        end.to_h
      )
    end.uniq do |sku|
      sku['salsify:id'] # Ensure all entries are unique by id
    end
  end

  def client
    @client ||= salsify_client(org_id: belk_org_id)
  end

  def belk_org_id
    @belk_org_id ||= ENV.fetch('CARS_ORG_ID')
  end

  def product_id_property
    @product_id_property ||= lazily_paginate(client: client, resource: :properties).find do |property|
      property['role'] == 'product_id'
    end['id']
  end

  def product_name_property
    @product_name_property ||= lazily_paginate(client: client, resource: :properties).find do |property|
      property['role'] == 'product_name'
    end['id']
  end

  def scene_7_properties
    @scene_7_properties ||= filter_properties(query: 'scene7 images').map do |property|
      property.id
    end.select do |property_id|
      property_id.downcase.include?('url')
    end
  end

  def filter_properties(query:, page: 1, per_page: 100)
    result = client.properties(query: query, page: page, per_page: per_page)
    if (page * per_page) < result.meta.total_entries
      result.properties.concat(filter_properties(query: query, page: page + 1, per_page: per_page))
    else
      result.properties
    end
  end

end
