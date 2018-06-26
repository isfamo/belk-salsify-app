require 'json'

LAST_SENT_TO_PIM = 'Last Sent to PIM'.freeze
GENERAL_ERROR = 'Salsify-to-PIM - Error'.freeze
IMAGE_NAME_TYPES = %w(A B C D E F G H I J SW)

# If you only want to run the StyleColor or something, then put that in here - whatever ones you want it to check.
WHICH_TYPES = ['Image']
# checks: Group, Group Special, Style, Image
# (Image is StyleColor)

# # QA
# PIM_API_USER='salsify_int'
# PIM_API_PASS='ESBInt@Salsify'
# PIM_API_HOST_URL='https://services-merch-int.belk.com/ItemUpdateService'
# # PROD

PIM_API_USER='salsify_prod'.freeze
PIM_API_PASS='ESBProd@Salsify'.freeze
PIM_API_HOST_URL='https://services-merch.belk.com/ItemUpdateService'.freeze

# task :test_webhook do
#   include Muffin::SalsifyClient
#
#   Hashie.logger = Logger.new(nil)
#
#   #products = lazily_paginate("value_map={ 'omniSizeDesc' : 'One Size' }", resource: :products_filtered_by, client: salsify_client(org_id: 5787)).map
#   lazily_paginate({ 'omniSizeDesc' => 'One Size' }, resource: :products_filtered_by, client: salsify_client(org_id: 5787)).each do |product|
#     puts product
#   end
# end
#
# task :process_batch_log do
#   content_keep = ''
#   File.foreach('batch_log.txt').with_index do |line, line_num|
#    #puts "#{line_num}: #{line}"
#    content_keep.concat(line) if line.downcase.include?('fail') || line.downcase.include?('error')
#   end
#   File.write('only_errors.txt', content_keep)
# end


task test_s2p: :environment do
  # NOTE: in this version, it doesn't check payloads of webhooks, so it will send anything that matches
  # TODO: could add in functionality to tell it which things to allow checking, so can say only send StyleColor as an example

  include Muffin::SalsifyClient

  Hashie.logger = Logger.new(nil)


  def perform(product)
    triggered_something = false
    begin
      # Iterate the products - webhook likely will only have one at a time, but just in case, iterate them.
      # For each one, see if has each case, and then do the work of each - in theroy could have multiple cases true.
      #
      # In initial testing, this worked without the groupingType part, but for the Group, it requires that, and it specifically notes the Style
      #   should not have that.
      events_triggered = []

      # Group
      if product['Copy Approval State'] &&
        product['PIP Image Approved?'] &&
        product['Copy Approval State'] == true &&
        product['PIP Image Approved?'] == true &&
        product['groupingType'] &&
        WHICH_TYPES.include?('Group')

        puts "$SALSIFY TO PIM$ Triggering a Group"
        process_group(product)
        events_triggered << 'Group'
        triggered_something = true
      end

      # Group Special
      if product['Copy Approval State'] &&
        product['Copy Approval State'] == true &&
        product['groupingType'] == 'CPG' &&
        WHICH_TYPES.include?('Group Special')

        puts "$SALSIFY TO PIM$ Triggering a Special Group (CPG only)"
        process_group_special(product)
        events_triggered << 'Special Group'
        triggered_something = true
      end

      # Style
      if product['Copy Approval State'] &&
        product['Copy Approval State'] == true &&
        !product['groupingType'] &&
        WHICH_TYPES.include?('Style')

        puts "$SALSIFY TO PIM$ Triggering a Style"
        process_style(product)
        events_triggered << 'Style'
        triggered_something = true
      end

      # Image
      if product['PIP Image Approved?'] &&
        product['PIP Image Approved?'] == true &&
        !product['groupingType'] &&
        WHICH_TYPES.include?('Image')

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
        which_fields << 'Scene7 Images - A - mainImage URL' unless product['Scene7 Images - A - mainImage URL']
        err_msg = "Required fields missing on product ID (#{product['salsify:id']}) (Fields: #{which_fields.join(', ')}) - (#{DateTime.now.in_time_zone('Eastern Time (US & Canada)')})"
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
      org_id: 5787
    ).save!
  end

  def client
    # Purposely not using the ENV here so I don't accidentally send to the wrong place.
    #
    # 5787 - Prod
    @client ||= salsify_client(org_id: 5787)
    # 5041 - QA
    #@client ||= salsify_client(org_id: 5041)
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


  # ---- MAIN(ish) ----
  product_ids = %w|21008363488 2902606ESTRAVELTIME 58006851YRU0010 210093164391 2100931814191 2100931841191 2100931853191 2604859G37151 2100642B91193P 3202380T20856 2100203453200 21010042045 2100533540412 2601060ZR507 58006851YRU0686 58006851YRU0692 58006851YRU0738 58006851YRU0739 58006851YRU0761 58006851YRU0507 32054651276391 32054651675861 2900011D5596S1 2601215DB127 2604859K24815 2604859G44815 32033401277279 290006612753 2601244MDX4712 2900516JSMANDALAYE 2601060R343 2900627PALOMA 58006851YRU0535 260036852348 2600556BK5074HU 2602714SL7323 5800408BE3162PL 2100931855290 8100617NGT1US 7100531A080416GYNDE 180374705JKEMZA 18038857286509 7101038842712376C 7101038842982369 710103885145060 290063740T8BRXA2A 58006851YRU0009 210093165191 2100931848191 21010041306 710103844432153 2601347106771 58006851YRU0676 58006851YRU0699 2100559SP0515 8100515CU30 58006851YRU0747 32054651411601 5805815BK710955EG 2900784MAPOINTE 2900784MACRETE 2900784MAEVIE 2602569106446 2900627CLASSIC 21008363439 920065744003 920065744004 26014601986296 2600719BK974718 5400359SUKT2A 18038191289445 320046845FM107 7601603171401 32033401301585 8100593EP81035 5900054A0100432 710103885145063 5900297CH007A01 76039461956013 2900649LKEMMIE 21002080018108 5900093L28503 58006851YRU0767 58006851YRU0749 58006851YRU0741 58006851YRU0476 2100559SS0715 2900758ROBBY 2900681SBELSA 48002581258777 2900240CARRSON 3901074703317 3203419SPGC 58006851YRU0658 58006851YRU0641 3901074700150 920065744002 2601244MNB70070 5803586BB713623R 320027661BK42X022 710103886156071 710103884272010 7101038842712345A 7101038861542320 7101038842981827 710103885145043|

  product_ids.each do |product_id|
    begin
      product = client.product(product_id)
      perform(product)
    rescue => e
      puts "NOPE - product_id: #{product_id}: #{e}"
    end
  end

end
