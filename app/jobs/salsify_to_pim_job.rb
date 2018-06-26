class SalsifyToPimJob < Struct.new(:payload_alert_name, :products)
  include Muffin::SalsifyClient

  #Hashie.logger = Logger.new(nil)

  PIM_API_USER = ENV['PIM_API_USER']
  PIM_API_PASS = ENV['PIM_API_PASS']
  PIM_API_HOST_URL = ENV['PIM_API_URL']

  LAST_SENT_TO_PIM = 'Last Sent to PIM'.freeze
  GENERAL_ERROR = 'Salsify-to-PIM - Error'.freeze
  IMAGE_NAME_TYPES = %w(A B C D E F G H I J SW)

  # NOTE: it used to just check "if product[salsify_attribute]" but that will fail on No (false) values coming out of the system.

  # TODO: probably want to update Last Sent to PIM and then whether it was Copy or Images (separate attributes) - although the logging/reporting may be enough (Excel level)

  def perform
    puts "$SALSIFY TO PIM$ Salsify to PIM job queued for products #{products.map { |product| product['salsify:id'] }.join(', ')}..."
    triggered_something = false
    begin
      # Iterate the products - webhook likely will only have one at a time, but just in case, iterate them (as it is possible that it will batch them if they trigger in a similar period).
      # For each one, see if has each case, and then do the work of each - in theroy could have multiple cases true.
      #
      # In initial testing, this worked without the groupingType part, but for the Group, it requires that, and it specifically notes the Style
      #   should not have that.
      events_triggered = []
      products.each do |product|
        # Breaking these out explicitly
        # The Style and the StyleColor should come from specific triggers, as it seems they can set each othoer off otherwise.
        # The group one shouldn't need that, as it can come from only group driven things.

        # Group
        if product['Copy Approval State'] &&
          product['PIP Image Approved?'] &&
          product['Copy Approval State'] == true &&
          product['PIP Image Approved?'] == true &&
          product['groupingType']

          puts "$SALSIFY TO PIM$ Triggering a Group"
          process_group(product)
          events_triggered << 'Group'
          triggered_something = true
        end

        # Group Special
        if product['Copy Approval State'] &&
          product['Copy Approval State'] == true &&
          product['groupingType'] == 'CPG'

          puts "$SALSIFY TO PIM$ Triggering a Special Group (CPG only)"
          process_group_special(product)
          events_triggered << 'Special Group'
          triggered_something = true
        end

        # Style
        if product['Copy Approval State'] &&
          product['Copy Approval State'] == true &&
          !product['groupingType'] &&
          payload_alert_name != 'Salsify-to-PIM StyleColor - Base'

          puts "$SALSIFY TO PIM$ Triggering a Style"
          process_style(product)
          events_triggered << 'Style'
          triggered_something = true
        end

        # Image
        if product['PIP Image Approved?'] &&
          product['PIP Image Approved?'] == true &&
          !product['groupingType'] &&
          payload_alert_name != 'Salsify-to-PIM (copy approved, in place on list)' &&
          payload_alert_name != 'Salsify-to-PIM (copy approved)'

          puts "$SALSIFY TO PIM$ Triggering a StyleColor"
          process_style_color(product)
          events_triggered << 'StyleColor'
          triggered_something = true
        end

        puts "$SALSIFY TO PIM$ All events triggered in this run (base product id #{product['salsify:id']}): #{events_triggered.uniq}"

        unless triggered_something
          err_msg = "Failed to trigger anything in the Salsify-to-PIM code for product id #{product['salsify:id']}. (#{DateTime.now.in_time_zone('Eastern Time (US & Canada)')})"
          puts "$SALSIFY TO PIM$ #{err_msg}"
          client.update_product(product['salsify:id'], { GENERAL_ERROR => err_msg })
        end
      end
    rescue Exception => e
      puts "$SALSIFY TO PIM$ ERROR while running Salsify to PIM job: #{e.message}\n#{e.backtrace.join("\n")}"
    end
  end

  def process_style(product)
    pim_to_salsify_mappings = {
      'Copy_Product_Name' => 'Product Copy Name',
      'Product_Copy_Text' => 'Product Copy Text',
      'Copy_Line_1' => 'Copy_Line_1',
      'Copy_Line_2' => 'Copy_Line_2',
      'Copy_Line_3' => 'Copy_Line_3',
      'Copy_Line_4' => 'Copy_Line_4',
      'Copy_Line_5' => 'Copy_Line_5',
      'Copy_Material' => 'Copy Material',
      'Copy_Care' => 'Copy Care',
      'Copy_Country_Of_Origin' => 'Country of Origin',
      'Copy_Exclusive' => 'Exclusive',
      'Copy_Import_Domestic' => 'Import/Domestic',
      'Copy_CAProp65_Compliant' => 'CAProp65_Compliant', # they have changed this several tiems and then again in the move to prod
      'Default_SKU_Code' => 'Default_SKU_Code'
    }

    unless product['Product Copy Name'] && product['Product Copy Text']
      which_fields = []
      which_fields << 'Product Copy Name' unless product['Product Copy Name']
      which_fields << 'Product Copy Text' unless product['Product Copy Text']
      err_msg = "Required fields missing on product ID (#{product['salsify:id']}) (Fields: #{which_fields.join(', ')}) - (#{DateTime.now.in_time_zone('Eastern Time (US & Canada)')})"
      puts "$SALSIFY TO PIM$ !ERROR! Style:Copy !ERROR! #{err_msg}"

      client.update_product(product['salsify:id'], { GENERAL_ERROR => err_msg })
      update_report_status(product['salsify:id'],  product['Orin/Grouping #'], err_msg, 'Style:Copy')
      return
    end

    json_payload = {}
    json_payload['carId'] = product['Orin/Grouping #']
    json_payload['recordType'] = 'Style'
    json_payload['messageInfo'] = 'Copy'
    json_payload['list'] = []
    pim_to_salsify_mappings.each do |pim_attribute, salsify_attribute|
      json_payload['list'] << { 'attributeName' => pim_attribute, 'attributeValue' => product[salsify_attribute] } unless product[salsify_attribute].nil?
    end

    puts "$SALSIFY TO PIM$ Style:Copy - sending over (#{product['salsify:id']}) json_payload: (#{json_payload.to_json})"
    res = JSON.parse(RestClient::Request.execute method: :post, url: PIM_API_HOST_URL, user: PIM_API_USER, password: PIM_API_PASS, payload: json_payload.to_json, verify_ssl: false, proxy: ENV['PROXIMO_URL'], headers: {'Content-Type' => 'application/json'})
    puts "$SALSIFY TO PIM$ Style:Copy - Salsify Product ID (that triggered webhook): #{product['salsify:id']} Response: #{res}"
    err_attr = 'Salsify-to-PIM - Style:Copy - Error'
    client.update_product(product['salsify:id'], { err_attr => "#{res['status']}: #{res['description']}" }) if res['status'].downcase.include?('fail')
    client.update_product(product['salsify:id'], { err_attr => nil, GENERAL_ERROR => nil, LAST_SENT_TO_PIM => DateTime.now.in_time_zone('Eastern Time (US & Canada)').to_s } ) if res['status'].downcase.include?('success')
    update_report_status(product['salsify:id'],  product['Orin/Grouping #'], "#{res['status']}: #{res['description']}", 'Style:Copy')
  end

  def process_group_special(product)
    pim_to_salsify_mappings = {
      'Copy_Product_Name' => 'Product Copy Name',
      'Product_Copy_Text' => 'Product Copy Text',
      'Copy_Line_1' => 'Copy_Line_1',
      'Copy_Line_2' => 'Copy_Line_2',
      'Copy_Line_3' => 'Copy_Line_3',
      'Copy_Line_4' => 'Copy_Line_4',
      'Copy_Line_5' => 'Copy_Line_5',
      'Copy_Material' => 'Copy Material',
      'Copy_Care' => 'Copy Care',
      'Copy_Country_Of_Origin' => 'Country of Origin',
      'Copy_Exclusive' => 'Exclusive',
      'Copy_Import_Domestic' => 'Import/Domestic',
      'Copy_CAProp65_Compliant' => 'CAProp65_Compliant',
      'Default_SKU_Code' => 'Default_SKU_Code'
      # This one doesn't have image data - it is grouping CPG at a copy level
    }

    unless product['Product Copy Name'] && product['Product Copy Text']
      which_fields = []
      which_fields << 'Product Copy Name' unless product['Product Copy Name']
      which_fields << 'Product Copy Text' unless product['Product Copy Text']
      err_msg = "Required fields missing on product ID (#{product['salsify:id']}) (Fields: #{which_fields.join(', ')}) - (#{DateTime.now.in_time_zone('Eastern Time (US & Canada)')})"
      puts "$SALSIFY TO PIM$ !ERROR! (Special)Group:Both !ERROR! #{err_msg}"

      client.update_product(product['salsify:id'], { GENERAL_ERROR => err_msg })
      update_report_status(product['salsify:id'],  product['Orin/Grouping #'], err_msg, 'Group:Both (Special - CPG)')
      return
    end

    json_payload = {}
    json_payload['carId'] = product['Orin/Grouping #']
    json_payload['recordType'] = 'Group'
    json_payload['messageInfo'] = 'Both'
    json_payload['list'] = []
    pim_to_salsify_mappings.each do |pim_attribute, salsify_attribute|
      json_payload['list'] << { 'attributeName' => pim_attribute, 'attributeValue' => product[salsify_attribute] } unless product[salsify_attribute].nil?
    end

    puts "$SALSIFY TO PIM$ (Special)Group:Both - sending over (#{product['salsify:id']}) json_payload: (#{json_payload.to_json})"
    res = JSON.parse(RestClient::Request.execute method: :post, url: PIM_API_HOST_URL, user: PIM_API_USER, password: PIM_API_PASS, payload: json_payload.to_json, verify_ssl: false, proxy: ENV['PROXIMO_URL'], headers: {'Content-Type' => 'application/json'})
    puts "$SALSIFY TO PIM$ (Special)Group:Both - Salsify Product ID (that triggered webhook): #{product['salsify:id']} Response: #{res}"
    err_attr = 'Salsify-to-PIM - (Special)Group:Both - Error'
    client.update_product(product['salsify:id'], { err_attr => "#{res['status']}: #{res['description']}" }) if res['status'].downcase.include?('fail')
    client.update_product(product['salsify:id'], { err_attr => nil, GENERAL_ERROR => nil, LAST_SENT_TO_PIM => DateTime.now.in_time_zone('Eastern Time (US & Canada)').to_s  }) if res['status'].downcase.include?('success')
    update_report_status(product['salsify:id'],  product['Orin/Grouping #'], "#{res['status']}: #{res['description']}", 'Group:Both (Special - CPG)')
  end

  def process_group(product)
    pim_to_salsify_mappings = {
      'Copy_Product_Name' => 'Product Copy Name',
      'Product_Copy_Text' => 'Product Copy Text',
      'Copy_Line_1' => 'Copy_Line_1',
      'Copy_Line_2' => 'Copy_Line_2',
      'Copy_Line_3' => 'Copy_Line_3',
      'Copy_Line_4' => 'Copy_Line_4',
      'Copy_Line_5' => 'Copy_Line_5',
      'Copy_Material' => 'Copy Material',
      'Copy_Care' => 'Copy Care',
      'Copy_Country_Of_Origin' => 'Country of Origin',
      'Copy_Exclusive' => 'Exclusive',
      'Copy_Import_Domestic' => 'Import/Domestic',
      'Copy_CAProp65_Compliant' => 'CAProp65_Compliant',
      'Default_SKU_Code' => 'Default_SKU_Code',
    }
    # Could add an additional loop where the Image/Swatch/Viewer are in an array and we put those in (and downcase as needed) - but this is fine for now
    IMAGE_NAME_TYPES.each do |name_type|
      # e.g.:
      #   'Scene7_ImageURL|~|A' => 'Scene7 Images - A - mainImage URL',
      #   'Scene7_SwatchURL|~|A' => 'Scene7 Images - A - swatchImage URL',
      #   'Scene7_ViewerURL|~|A' => 'Scene7 Images - A - viewerImage URL',
      pim_to_salsify_mappings["Scene7_ImageURL|~|#{name_type}"] = "Scene7 Images - #{name_type} - mainImage URL"
      pim_to_salsify_mappings["Scene7_SwatchURL|~|#{name_type}"] = "Scene7 Images - #{name_type} - swatchImage URL"
      pim_to_salsify_mappings["Scene7_ViewerURL|~|#{name_type}"] = "Scene7 Images - #{name_type} - viewerImage URL"
    end

    unless product['Product Copy Name'] && product['Product Copy Text'] && product['Scene7 Images - A - mainImage URL']
      which_fields = []
      which_fields << 'Product Copy Name' unless product['Product Copy Name']
      which_fields << 'Product Copy Text' unless product['Product Copy Text']
      which_fields << 'Scene7 Images - A - mainImage URL' unless product['Scene7 Images - A - mainImage URL']
      err_msg = "Required fields missing on product ID (#{product['salsify:id']}) (Fields: #{which_fields.join(', ')}) - (#{DateTime.now.in_time_zone('Eastern Time (US & Canada)')})"
      puts "$SALSIFY TO PIM$ !ERROR! Group:Both !ERROR! #{err_msg}"

      client.update_product(product['salsify:id'], { GENERAL_ERROR => err_msg })
      update_report_status(product['salsify:id'], product['Orin/Grouping #'], err_msg, 'Group:Both')
      return
    end

    json_payload = {}
    json_payload['carId'] = product['Orin/Grouping #']
    json_payload['recordType'] = 'Group'
    json_payload['messageInfo'] = 'Both'
    json_payload['list'] = []
    pim_to_salsify_mappings.each do |pim_attribute, salsify_attribute|
      json_payload['list'] << { 'attributeName' => pim_attribute, 'attributeValue' => product[salsify_attribute] } unless product[salsify_attribute].nil?
    end

    puts "$SALSIFY TO PIM$ Group:Both - sending over (#{product['salsify:id']}) json_payload: (#{json_payload.to_json})"
    res = JSON.parse(RestClient::Request.execute method: :post, url: PIM_API_HOST_URL, user: PIM_API_USER, password: PIM_API_PASS, payload: json_payload.to_json, verify_ssl: false, proxy: ENV['PROXIMO_URL'], headers: {'Content-Type' => 'application/json'})
    puts "$SALSIFY TO PIM$ Group:Both - Salsify Product ID (that triggered webhook): #{product['salsify:id']} Response: #{res}"
    err_attr = 'Salsify-to-PIM - Group:Both - Error'
    client.update_product(product['salsify:id'], { err_attr => "#{res['status']}: #{res['description']}" }) if res['status'].downcase.include?('fail')
    client.update_product(product['salsify:id'], { err_attr => nil, GENERAL_ERROR => nil, LAST_SENT_TO_PIM => DateTime.now.in_time_zone('Eastern Time (US & Canada)').to_s  }) if res['status'].downcase.include?('success')
    update_report_status(product['salsify:id'], product['Orin/Grouping #'], "#{res['status']}: #{res['description']}", 'Group:Both')
  end

  def process_style_color(product)
    # This gets triggered on a base - needs to then get all of its children. For each child looks to see if Color Master? for each color, then each of
    #   those get sent in the API payload to the Belk PIM

    pim_to_salsify_mappings = {}
    # Could add an additional loop where the Image/Swatch/Viewer are in an array and we put those in (and downcase as needed) - but this is fine for now
    IMAGE_NAME_TYPES.each do |name_type|
      # e.g.:
      #   'Scene7_ImageURL|~|A' => 'Scene7 Images - A - mainImage URL',
      #   'Scene7_SwatchURL|~|A' => 'Scene7 Images - A - swatchImage URL',
      #   'Scene7_ViewerURL|~|A' => 'Scene7 Images - A - viewerImage URL',
      pim_to_salsify_mappings["Scene7_ImageURL|~|#{name_type}"] = "Scene7 Images - #{name_type} - mainImage URL"
      pim_to_salsify_mappings["Scene7_SwatchURL|~|#{name_type}"] = "Scene7 Images - #{name_type} - swatchImage URL"
      pim_to_salsify_mappings["Scene7_ViewerURL|~|#{name_type}"] = "Scene7 Images - #{name_type} - viewerImage URL"
    end

    sku_ids = filter_products(
      filter_hash: { 'Parent Product' => product['salsify:id'] }
    ).map { |sib| sib['id'] }

    unless sku_ids.length > 0
      err_msg = "Product ID (#{product['salsify:id']}) has no children to look at for Scene 7 images - (#{DateTime.now.in_time_zone('Eastern Time (US & Canada)')})"
      puts "$SALSIFY TO PIM$ !ERROR! StyleColor:Image !ERROR! #{err_msg}"

      client.update_product(product['salsify:id'], { GENERAL_ERROR => err_msg })
      update_report_status(product['salsify:id'], -1, err_msg, 'StyleColor:Image')
      return
    end

    colors_used = {}

    sku_by_id = sku_ids.each_slice(100).map do |sku_id_batch|
      client.products(sku_id_batch)
    end.flatten.map do |sku|
      [sku['salsify:id'], sku]
    end.to_h

    sku_ids.each do |sku_id|
      sibling = sku_by_id[sku_id]
      next if !sibling['Color Master?'] || colors_used[sibling['nrfColorCode']]
      colors_used[sibling['nrfColorCode']] = 42 # value here doesn't matter, so I guess this should really be a set, but hey - 42!
# TODO - add code here to track if no color master was found and at the very least raise that to the logs if not all the way to the sku
      json_payload = {}
      # the child should have the Orin/Grouping #, inherited from the parent, but since we have the parent anyway, just grab it from there
      color_code = sibling['pim_nrfColorCode'] ? sibling['pim_nrfColorCode'] : sibling['nrfColorCode']
      car_id = "#{product['Orin/Grouping #']}#{color_code}"
      json_payload['carId'] = car_id
      json_payload['recordType'] = 'StyleColor'
      json_payload['messageInfo'] = 'Image'
      json_payload['list'] = []

      unless sibling['Scene7 Images - A - mainImage URL']
        which_fields = []
        which_fields << 'Scene7 Images - A - mainImage URL' unless sibling['Scene7 Images - A - mainImage URL']
        err_msg = "Required fields missing on product ID (#{sibling['salsify:id']}) (Fields: #{which_fields.join(', ')}) - (#{DateTime.now.in_time_zone('Eastern Time (US & Canada)')})"
        puts "$SALSIFY TO PIM$ !ERROR! StyleColor:Image !ERROR! #{err_msg}"

        client.update_product(sibling['salsify:id'], { GENERAL_ERROR => err_msg })
        update_report_status(sibling['salsify:id'], car_id, err_msg, 'StyleColor:Image')
        next
      end

      # Per Belk, don't send Default_SKU_Code as part of StyleColor PIM feed.
      pim_to_salsify_mappings.each do |pim_attribute, salsify_attribute|
        json_payload['list'] << { 'attributeName' => pim_attribute, 'attributeValue' => sibling[salsify_attribute] } unless sibling[salsify_attribute].nil?
      end
      puts "$SALSIFY TO PIM$ StyleColor:Image - sending over (PRODUCT ID: #{sibling['salsify:id']}) json_payload: (#{json_payload.to_json})"
      res = JSON.parse(RestClient::Request.execute method: :post, url: PIM_API_HOST_URL, user: PIM_API_USER, password: PIM_API_PASS, proxy: ENV['PROXIMO_URL'], payload: json_payload.to_json, verify_ssl: false, headers: {'Content-Type' => 'application/json'})
      puts "$SALSIFY TO PIM$ StyleColor:Image - Salsify Product ID (that triggered webhook): #{product['salsify:id']} Response: #{res}"
      err_attr = 'Salsify-to-PIM - StyleColor:Image - Error'
      client.update_product(sibling['salsify:id'], { err_attr => "#{res['status']}: #{res['description']}" }) if res['status'].downcase.include?('fail')
      client.update_product(sibling['salsify:id'], { err_attr => nil, GENERAL_ERROR => nil, LAST_SENT_TO_PIM => DateTime.now.in_time_zone('Eastern Time (US & Canada)').to_s  }) if res['status'].downcase.include?('success')
      update_report_status(sibling['salsify:id'], car_id, "#{res['status']}: #{res['description']}", 'StyleColor:Image')
    end
  end

  def update_report_status(product_id, car_id, status, type)
    # product_id : text (Salsify product id)
    # car_id : text (thing we send Belk that is different depending on which thing above creates it)
    # status :  text (comes from the Belk API usually, but could be our code saying couldn't find in Salsify or something)
    # type : text (which type it is, Group, Image, etc)
    # dtstamp : datetime (when it was written)

    # Not yet ready for prod
    SalsifyToPimLog.new(
      product_id: product_id,
      car_id: car_id,
      status: status,
      push_type: type,
      dtstamp: DateTime.now.strftime('%Y-%m-%d %H:%M:%S'),
      org_id: ENV.fetch('CARS_ORG_ID').to_i
    ).save!
  end

  def client
    @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
  end

  def filter_products(filter_hash: nil, filter_string: nil, selections: nil, per_page: 100, page: 1)
    if selections
      result = client.products_filtered_by(filter_hash, filter: filter_string, selections: selections, per_page: per_page, page: page)
    else
      result = client.products_filtered_by(filter_hash, filter: filter_string, per_page: per_page, page: page)
    end
    if (page * per_page) < result['meta']['total_entries']
      result['products'].concat(filter_products(filter_hash: filter_hash, filter_string: filter_string, selections: selections, per_page: per_page, page: (page + 1)))
    else
      result['products']
    end
  end

end
