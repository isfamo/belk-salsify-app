class Api::RrdController < ApplicationController
  protect_from_forgery prepend: true

  PROPERTY_VENDOR_NUMBER = 'Vendor#'.freeze
  PROPERTY_VENDOR_NAME = 'Vendor  Name'.freeze
  PROPERTY_DEPT_NUMBER = 'Dept#'.freeze
  PROPERTY_DEPT_NAME = 'Dept Description'.freeze
  PROPERTY_STYLE_NUMBER = 'Style#'.freeze
  PROPERTY_GROUP_ORIN = 'Orin/Grouping #'.freeze
  PROPERTY_COLOR_CODE = 'nrfColorCode'.freeze
  PROPERTY_COLOR_MASTER = 'Color Master?'.freeze
  PROPERTY_OF_OR_SL = 'OForSL'.freeze
  PROPERTY_DISPLAY_NAME = 'Product Name'.freeze
  PROPERTY_OMNI_BRAND = 'OmniChannel Brand'.freeze
  PROPERTY_SKU_IMAGES_UPDATED = 'sku_images_updated'.freeze
  PROPERTY_OMNI_COLOR = 'omniChannelColorDescription'.freeze
  PROPERTY_VENDOR_COLOR = 'vendorColorDescription'.freeze
  PROPERTY_IMAGE_METADATA = 'image_metadata'.freeze
  PROPERTY_TURN_IN_DATE = 'Turn-In Date'.freeze
  PROPERTY_SAMPLE_REQUESTED = 'Sample Sent to RRD'.freeze
  PROPERTY_RRD_TASK_ID = 'rrd_task_id'.freeze
  PROPERTY_PIP_WORKFLOW_STATUS = 'pip_workflow_status'.freeze
  PROPERTY_PIP_ALL_IMAGES_VERIFIED = 'PIP All Images Verified?'.freeze
  PROPERTY_PIP_IMAGE_APPROVED = 'PIP Image Approved?'.freeze
  PROPERTY_COMPLETION_DATE = 'Completion Date'.freeze
  PROPERTY_REOPENED_REASON = 'Task Reopened Message'.freeze
  TIMEZONE_EST = 'Eastern Time (US & Canada)'.freeze
  URL_SAMPLE_REQ_CREATED = 'https://94623f70.ngrok.io/sample_requests'.freeze
  NUM_THREADS = 4.freeze

  PARAMS_SYMBOLS = {
    '$HASH$' => '#',
    '$AMP$' => '&'
  }.freeze

  # POST /api/assets_deleted
  def assets_deleted
    params['digital_assets'].each do |asset|
      record_deleted_asset(asset)
    end
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in RrdController#assets_deleted:\n#{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/img_properties_updated
  def img_properties_updated
    Delayed::Job.enqueue(RrdImageMetadataJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in RrdController#img_properties_updated:\n#{e.message}\n#{e.backtrace.join("\n")}"
  end

  # GET /api/trigger_vendor_image_upload_job
  def trigger_vendor_image_upload_job
    Delayed::Job.enqueue(VendorImageUploadJob.new(Time.now))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in RrdController#trigger_vendor_image_upload_job:\n#{e.message}\n#{e.backtrace.join("\n")}"
    render status: 500, json: { 'error' => e.message }.to_json
  end

  # GET /api/trigger_vendor_image_delete_job
  def trigger_vendor_image_delete_job
    Delayed::Job.enqueue(VendorImageDeleteJob.new(Time.now))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in RrdController#trigger_vendor_image_delete_job:\n#{e.message}\n#{e.backtrace.join("\n")}"
    render status: 500, json: { 'error' => e.message }.to_json
  end

  # GET /api/trigger_vendor_image_response_pull
  def trigger_vendor_image_response_pull
    Delayed::Job.enqueue(VendorImageResponsePullJob.new(Time.now))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in RrdController#trigger_vendor_image_response_pull:\n#{e.message}\n#{e.backtrace.join("\n")}"
    render status: 500, json: { 'error' => e.message }.to_json
  end

  # GET /api/trigger_sample_request_job
  def trigger_sample_request_job
    Delayed::Job.enqueue(VendorImageSampleJob.new(Time.now))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in RrdController#trigger_sample_request_job:\n#{e.message}\n#{e.backtrace.join("\n")}"
    render status: 500, json: { 'error' => e.message }.to_json
  end

  # GET /api/trigger_hex_feed
  def trigger_hex_feed
    Delayed::Job.enqueue(HexFeedExportJob.new(Time.now))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in RrdController#trigger_hex_feed:\n#{e.message}\n#{e.backtrace.join("\n")}"
    render status: 500, json: { 'error' => e.message }.to_json
  end

  # GET /api/trigger_ads_feed
  def trigger_ads_feed
    Delayed::Job.enqueue(AdsFeedImportJob.new(Time.now))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in RrdController#trigger_ads_feed:\n#{e.message}\n#{e.backtrace.join("\n")}"
    render status: 500, json: { 'error' => e.message }.to_json
  end

  # POST /api/department_config_file_updated
  def department_config_file_updated
    Delayed::Job.enqueue(DepartmentConfigFileUpdateJob.new(JSON.parse(request.raw_post)['path']))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in RrdController#department_config_file_updated:\n#{e.message}\n#{e.backtrace.join("\n")}"
    render status: 500, json: { 'error' => e.message }.to_json
  end

  # GET /api/rrd_get_product
  def get_product
    product_id = params['product_id']
    if product_id.nil? || product_id == ''
      render status: 422, json: {
        error: 'No product code provided!'
      }
    else
      begin
        # Query Salsify for the parent product and child SKUs
        product = client.product(product_id)
        sku_ids = client.product_relatives(product_id)['children'].map { |sku| sku['id'] }

        # is it a grouping?
        grouping = sku_ids.empty? && product[PROPERTY_GROUP_ORIN]

        if sku_ids.empty? && !grouping
          msg = "No SKUs found for product code #{product_id}."
          if product['salsify:parent_id']
            msg += "  Did you mean its parent, #{product['salsify:parent_id']}?"
          end
          render status: 422, json: {
            error: msg
          }
        else
          # Limit the attributes returned in the payload to what is needed
          product.select! do |key, value|
            ['salsify:id', 'Product Name', 'ng_skus', PROPERTY_DISPLAY_NAME,
              PROPERTY_OF_OR_SL, PROPERTY_VENDOR_NUMBER, PROPERTY_VENDOR_NAME,
              PROPERTY_DEPT_NUMBER, PROPERTY_DEPT_NAME, PROPERTY_STYLE_NUMBER,
              PROPERTY_OMNI_BRAND].include?(key)
          end

          skus = grouping ? [] : sku_ids.each_slice(100).map { |id_batch| client.products(id_batch) }.flatten
          product['ng_skus'] = skus.select do |sku|
            sku[PROPERTY_COLOR_MASTER]
          end.map do |sku|
            sku.select do |key, value|
              ['salsify:id', PROPERTY_DISPLAY_NAME, PROPERTY_COLOR_MASTER, PROPERTY_COLOR_CODE, PROPERTY_OMNI_COLOR, PROPERTY_VENDOR_COLOR, PROPERTY_COMPLETION_DATE].include?(key)
            end
          end

          # Provide array of available colors
          product['ng_colors'] = product['ng_skus'].map { |sku|
            sku[PROPERTY_OMNI_COLOR] || sku[PROPERTY_VENDOR_COLOR]
          }.uniq.sort

          if grouping
            colors = [{
              'code' => '000',
              'name' => 'GROUPING',
              'completion_date' => nil
            }]
          else
            colors = product['ng_skus'].map do |sku|
              {
                'code' => ![nil, ''].include?(sku[PROPERTY_COLOR_CODE]) ? sku[PROPERTY_COLOR_CODE] : '',
                'name' => (sku[PROPERTY_VENDOR_COLOR] || sku[PROPERTY_OMNI_COLOR]),
                'completion_date' => sku[PROPERTY_COMPLETION_DATE] ? DateTime.parse(sku[PROPERTY_COMPLETION_DATE]) : nil
              }
            end.sort_by do |hash|
              hash['completion_date'] ? hash['completion_date'] : DateTime.new(10000, 1, 1)
            end.map do |hash|
              if hash['completion_date']
                hash.merge({ 'completion_date' => hash['completion_date'].strftime('%Y-%m-%d at %I:%M %p') })
              else
                hash
              end
            end
          end

          # Return json response
          render status: 200, json: {
            product: product,
            colors: colors,
            reqdColors: RrdRequestedSample.where(product_id: product_id).map { |req|
              [
                ![nil, ''].include?(req.color_id) ? req.color_id : '',
                {
                  of_or_sl: req.of_or_sl,
                  on_hand_or_from_vendor: req.on_hand_or_from_vendor,
                  sample_type: req.sample_type,
                  turn_in_date: req.turn_in_date,
                  must_be_returned: req.must_be_returned,
                  return_to: req.return_to,
                  return_notes: req.return_notes,
                  silhouette_required: req.silhouette_required,
                  instructions: req.instructions,
                  sent_to_rrd: req.sent_to_rrd,
                  completed_at: req.completed_at
                }
              ]
            }.to_h
          }
        end
      rescue RestClient::ResourceNotFound => e
        render status: 404, json: {
          error: 'No product found matching the provided product code.'
        }
      rescue Exception => e
        puts "$RRD CTRL$ ERROR while pulling data for product #{params['product_id']}: #{e.message}\n#{e.bactrace.join("\n")}"
        render status: 500, json: {
          error: "An error occurred while retrieving data for product code #{product_id}: #{e.message}"
        }
      end
    end
  end

  # POST /api/assign_new_task_id_to_parent
  def assign_new_task_id_to_parent
    product_ids = params['products'].map { |product| product['salsify:id'] }
    return if product_ids.empty?
    puts "$RRD CTRL$ RrdController#assign_new_task_id_to_parent triggered for ids: #{product_ids}"

    parent_ids = params['products'].map do |sku|
      if sku['salsify:parent_id']
        [sku['salsify:id'], sku['salsify:parent_id']]
      elsif sku[PROPERTY_GROUP_ORIN]
        [sku['salsify:id'], sku['salsify:id']]
      else
        [nil, nil]
      end
    end.to_h.values.uniq.reject do |id|
      [nil, ''].include?(id)
    end
    return if parent_ids.empty?

    parent_ids_to_reopen = parent_ids.each_slice(100).map do |parent_id_batch|
      client.products(parent_id_batch).select do |product|
        product[PROPERTY_PIP_ALL_IMAGES_VERIFIED]
      end.map do |product|
        product['salsify:id']
      end
    end.flatten.uniq

    # Remove reopened parent product ids from user-specific
    # queues so they go back to the assignment queue
    puts "$RRD CTRL$ Removing approved image products from user queues, sending back to assignment queue"
    if !parent_ids_to_reopen.empty?
      Parallel.each(query_lists('pip user list'), in_threads: NUM_THREADS) do |list|
        update_list(list_id: list['id'], removals: parent_ids_to_reopen)
      end
    end

    require_rel '../../../lib/rrd_integration/**/*.rb'
    # TODO: Should pull this product query out and bulkify it
    parent_ids.each do |product_id|
      product = client.product(product_id)
      task = RRDonnelley::RRDConnector.generate_task(product_id)
      time_est = DateTime.now.in_time_zone(TIMEZONE_EST)
      pip_status = pip_workflow_value(product)
      update_hash = {
        PROPERTY_RRD_TASK_ID => task.id,
        PROPERTY_SKU_IMAGES_UPDATED => true,
        PROPERTY_PIP_WORKFLOW_STATUS => pip_status
      }
      if product[PROPERTY_PIP_ALL_IMAGES_VERIFIED]
        update_hash.merge!({
          PROPERTY_REOPENED_REASON => "Task reopened on #{time_est.strftime('%Y-%m-%d')} at #{time_est.strftime('%l:%M %p %Z')} because Image Approved was set to Yes on child sku.",
          PROPERTY_PIP_ALL_IMAGES_VERIFIED => nil,
          PROPERTY_PIP_IMAGE_APPROVED => nil
        })
      end

      client.update_product(product_id, update_hash)
      puts "$RRD CTRL$ Done adding task ID"
    end
    render status: 200, json: ''
  rescue Exception => e
    puts "$RRD CTRL$ ERROR: Error in RrdController#assign_new_task_id_to_parent:\n#{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/assign_new_task_id_to_product
  def assign_new_task_id_to_product
    puts "$RRD CTRL$ RrdController#assign_new_task_id_to_product triggered for #{params['products'].length} skus (could share parents)"
    parent_ids = params['products'].map do |product|
      product['salsify:parent_id'] || product['salsify:id']
    end

    return if parent_ids.empty?

    parent_by_id = parent_ids.each_slice(100).map do |parent_id_batch|
      client.products(parent_id_batch).map do |product|
        [product['salsify:id'], product]
      end.to_h
    end.reduce({}, :merge)

    # parent_by_id = params['products'].select do |product|
    #   product['salsify:parent_id'].nil?
    # end.map do |product|
    #   [product['salsify:id'], product]
    # end.to_h
    # return if parent_by_id.empty?
    puts "$RRD CTRL$ Processing #{parent_by_id.length} styles"
    require_rel '../../../lib/rrd_integration/**/*.rb'

    parent_ids_to_reopen = parent_by_id.select do |parent_id, parent|
      parent[PROPERTY_PIP_ALL_IMAGES_VERIFIED]
    end.keys

    # Remove reopened parent product ids from user-specific
    # queues so they go back to the assignment queue
    puts "$RRD CTRL$ Removing approved image products from user queues, sending back to assignment queue"
    if !parent_ids_to_reopen.empty?
      Parallel.each(query_lists('pip user list'), in_threads: NUM_THREADS) do |list|
        update_list(list_id: list['id'], removals: parent_ids_to_reopen)
      end
    end

    parent_by_id.each do |parent_id, parent|
      task = RRDonnelley::RRDConnector.generate_task(parent_id)
      time_est = DateTime.now.in_time_zone(TIMEZONE_EST)
      pip_status = pip_workflow_value(parent)
      update_hash = {
        PROPERTY_RRD_TASK_ID => task.id,
        PROPERTY_SKU_IMAGES_UPDATED => true,
        PROPERTY_PIP_WORKFLOW_STATUS => pip_status
      }
      if parent[PROPERTY_PIP_ALL_IMAGES_VERIFIED]
        update_hash.merge!({
          PROPERTY_REOPENED_REASON => "Task reopened on #{time_est.strftime('%Y-%m-%d')} at #{time_est.strftime('%l:%M %p %Z')} because PIP Image Approved? was set to Yes, and product had no RRD Image ID yet.",
          PROPERTY_PIP_ALL_IMAGES_VERIFIED => nil,
          PROPERTY_PIP_IMAGE_APPROVED => nil
        })
      end
      client.update_product(parent_id, update_hash)
      puts "$RRD CTRL$ Done adding task ID"
    end
    render status: 200, json: ''
  rescue Exception => e
    puts "$RRD CTRL$ ERROR: Error in RrdController#assign_new_task_id_to_product:\n#{e.message}\n#{e.backtrace.join("\n")}"
  end

  def pip_workflow_value(product)
    # Open if it is not anything
    return 'Open' unless product[PROPERTY_PIP_WORKFLOW_STATUS]
    # Re-open if it was closed
    return 'Re-open' if product[PROPERTY_PIP_WORKFLOW_STATUS] == 'Closed'
    # this last one is essentially an else - in this case, if it isn't these other two, just set it to what it is now
    return product[PROPERTY_PIP_WORKFLOW_STATUS]
  end

  # POST /api/rrd_submit_requests
  def submit_requests
    puts "Forwarding sample req creation"
    payload = Oj.load(params['requests']).first
    RestClient::Request.execute(
      method: :post,
      url: URL_SAMPLE_REQ_CREATED,
      payload: payload.to_json,
      headers: {
        content_type: :json,
        accept: :json
      }
    )
    render status: 200

    # requests = params['requests']
    # if requests.nil? || requests == ''
    #   render status: 422, json: {
    #     error: 'No sample requests provided'
    #   }
    # else
    #   created_reqs = [JSON.parse(clean_params(requests))].flatten.map do |request|
    #     existing_req = RrdRequestedSample.find_by(
    #       product_id: request['product_id'],
    #       color_id: request['color_id']
    #     )
    #     if existing_req.nil?
    #       req = RrdRequestedSample.new(
    #         product_id: request['product_id'],
    #         color_id: request['color_id'],
    #         color_name: request['color_name'],
    #         of_or_sl: request['of_or_sl'],
    #         on_hand_or_from_vendor: request['on_hand_or_from_vendor'],
    #         sample_type: request['sample_type'],
    #         turn_in_date: [nil, ''].include?(request['turn_in_date']) ? nil : request['turn_in_date'],
    #         must_be_returned: request['must_be_returned'],
    #         return_to: request['return_to'],
    #         return_notes: request['return_notes'],
    #         silhouette_required: request['silhouette_required'],
    #         instructions: [nil, ''].include?(request['instructions']) ? nil : request['instructions'],
    #         completed_at: nil,
    #         sent_to_rrd: false
    #       )
    #       req.save!
    #       {
    #         'id': req.id,
    #         'product_id': req.product_id,
    #         'color_id': req.color_id,
    #         'turn_in_date': req.turn_in_date
    #       }
    #     elsif existing_req.sent_to_rrd != true
    #       existing_req.of_or_sl = request['of_or_sl']
    #       existing_req.on_hand_or_from_vendor = request['on_hand_or_from_vendor']
    #       existing_req.sample_type = request['sample_type']
    #       existing_req.turn_in_date = [nil, ''].include?(request['turn_in_date']) ? nil : request['turn_in_date']
    #       existing_req.must_be_returned = request['must_be_returned']
    #       existing_req.return_to = request['return_to']
    #       existing_req.return_notes = request['return_notes']
    #       existing_req.silhouette_required = request['silhouette_required']
    #       existing_req.instructions = [nil, ''].include?(request['instructions']) ? nil : request['instructions']
    #       existing_req.save!
    #       {
    #         'id': existing_req.id,
    #         'product_id': existing_req.product_id,
    #         'color_id': existing_req.color_id,
    #         'turn_in_date': existing_req.turn_in_date
    #       }
    #     end
    #   end.compact
    #   if created_reqs.empty?
    #     render status: 422, json: {
    #       error: 'No requests were created.'
    #     }
    #   else
    #     render status: 200, json: { created_reqs: created_reqs }
    #   end
    # end
  rescue Exception => e
    render status: 500, json: { error: "Internal server error: #{e.message}\n\nDetails:\n#{e.backtrace.join("\n")}" }
  end

  def fetch_unsent_sample_requests
    unsent_sample_reqs = RrdRequestedSample.where('sent_to_rrd != ?', true)
    render json: unsent_sample_reqs
  end

  def clean_params(text)
    result = text
    PARAMS_SYMBOLS.each { |key, value| result.gsub!(key, value) }
    result
  end

  def client
    @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
  end

  def record_deleted_asset(asset)
    return if [nil, ''].include?(asset[PROPERTY_IMAGE_METADATA])
    begin
      image_metadata = JSON.parse(asset[PROPERTY_IMAGE_METADATA])
      image_metadata.each do |key, hash|
        del_img = RrdDeletedImage.new(
          file_name: hash['filename'],
          rrd_image_id: hash['rrd_image_id']
        )
        del_img.save!
      end
    rescue JSON::ParserError

    end
  end

  def query_lists(query, entity_type = 'product', page = 1, per_page = 50)
    result = client.lists(entity_type, query: query, page: page, per_page: per_page)
    if (page * per_page) < result['meta']['total_entries']
      result['lists'].concat(query_lists(query, entity_type, page, per_page))
    else
      result['lists']
    end
  end

  def update_list(list_id:, additions: [], removals: [])
    return if additions.empty? && removals.empty?
    client.update_list(
      list_id,
      {
        additions: { member_external_ids: additions },
        removals: { member_external_ids: removals }
      }
    )
  end

end
