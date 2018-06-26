module ImageManagement
  class ImageTask
    include Muffin::SalsifyClient
    include Helpers

    STAMP = '$IMAGE$'.freeze

    # TODO: Use new property instead of PROPERTY_RRD_TASK_ID?

    attr_reader :products

    def initialize(products)
      @products = products
    end

    def self.handle_task_complete(products)
      new(products).handle_task_complete
    end

    def handle_task_complete
      execute_product_updates
      execute_list_updates
    end

    def execute_product_updates
      t = Time.now
      puts "#{STAMP} Updating #{task_completed_updates_by_id.length} products based on completed image specialist workflow"
      task_completed_updates_by_id.each do |product_id, update_hash|
        client.update_product(product_id, update_hash)
      end
      puts "#{STAMP} Done updating #{task_completed_updates_by_id.length} products, took #{(Time.now - t).round(1)} seconds"
    end

    def execute_list_updates
      t = Time.now
      puts "#{STAMP} Removing reopened products from #{pip_list_ids.length} PIP user lists so they go back to assignment queue"
      Parallel.each(pip_list_ids, in_threads: NUM_THREADS_CRUD) do |list_id|
        update_list(list_id: list_id, removals: list_removal_product_ids)
      end
      puts "#{STAMP} Done updating #{pip_list_ids.length} PIP user lists to move reopened products back to assignment queue, took #{(Time.now - t).round(1)} seconds to update lists"
    end

    def task_completed_updates_by_id
      @task_completed_updates_by_id ||= products.select do |product|
        product[PROPERTY_IMAGE_TASK_STATUS] == IMAGE_TASK_STATUS_COMPLETE
      end.map do |product|
        if product['salsify:parent_id']
          sku_change = { PROPERTY_IMAGE_TASK_COMPLETE => true }

          parent = parent_by_id[product['salsify:parent_id']]
          parent_change = {
            PROPERTY_RRD_TASK_ID => get_task_id(product['salsify:parent_id']),
            PROPERTY_PIP_ALL_IMAGES_VERIFIED => nil,
            PROPERTY_PIP_IMAGE_APPROVED => nil,
            PROPERTY_SKU_IMAGES_UPDATED => true,
            PROPERTY_PIP_WORKFLOW_STATUS => pip_workflow_status(parent)
          }

          if parent[PROPERTY_PIP_ALL_IMAGES_VERIFIED] || parent[PROPERTY_PIP_IMAGE_APPROVED]
            parent_change[PROPERTY_REOPENED_REASON] = pip_message(msg_template: PIP_TASK_MESSAGE_IMG_SPEC_COMPLETE)
          end

          [
            [product['salsify:id'], sku_change],
            [product['salsify:parent_id'], parent_change]
          ]
        else
          [
            [product['salsify:id'], {
              PROPERTY_IMAGE_TASK_COMPLETE => true,
              PROPERTY_RRD_TASK_ID => get_task_id(product['salsify:id']),
              PROPERTY_PIP_ALL_IMAGES_VERIFIED => nil,
              PROPERTY_PIP_IMAGE_APPROVED => nil,
              PROPERTY_IMAGE_TASK_MESSAGE => 'Set task ID on this sku because no parent style available.',
              PROPERTY_SKU_IMAGES_UPDATED => true,
              PROPERTY_PIP_WORKFLOW_STATUS => pip_workflow_status(product)
            }]
          ]
        end
      end.flatten(1).to_h
    end

    def pip_workflow_status(product)
      if product[PROPERTY_PIP_WORKFLOW_STATUS].nil?
        PIP_WORKFLOW_STATUS_OPEN
      elsif product[PROPERTY_PIP_WORKFLOW_STATUS] == PIP_WORKFLOW_STATUS_CLOSED
        PIP_WORKFLOW_STATUS_REOPEN
      else
        product[PROPERTY_PIP_WORKFLOW_STATUS]
      end
    end

    def list_removal_product_ids
      @list_removal_product_ids ||= products.map do |product|
        product['salsify:parent_id'] ? product['salsify:parent_id'] : product['salsify:id']
      end.uniq
    end

    def pip_list_ids
      @pip_list_ids ||= begin
        t = Time.now
        puts "#{STAMP} Querying PIP user lists"
        ids = query_lists('pip user list').map { |list| list['id'] }
        puts "#{STAMP} Retrieved #{ids.length} PIP user lists in #{(Time.now - t).round(1)} seconds"
        ids
      end
    end

    def parent_by_id
      @parent_by_id ||= begin
        parent_ids = products.map { |pr| pr['salsify:parent_id'] }.compact.uniq
        parent_ids.each_slice(MAX_PRODUCTS_PER_CRUD).map do |parent_id_batch|
          client.products(parent_id_batch)
        end.flatten.map do |parent|
          [parent['salsify:id'], parent]
        end.to_h
      end
    end

    def get_task_id(product_id)
      existing_task_id = existing_task_id_by_product_id[product_id]
      return existing_task_id.id if existing_task_id
      puts "#{STAMP} Creating task for product #{product_id}"
      task_id = RrdTaskId.create(product_id: product_id)
      existing_task_id_by_product_id[product_id] = task_id
      task_id.id
    end

    # Query existing task ids for this set of products and group them by product id
    def existing_task_id_by_product_id
      @existing_task_id_by_product_id ||= RrdTaskId.where(
        product_id: [
          products.map { |s| s['salsify:id'] },
          parent_by_id.keys
        ].flatten.uniq.compact
      ).map { |task_id| [task_id.product_id, task_id] }.to_h
    end

    def client
      @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID').to_i)
    end

    def pip_message(msg_template:, product_id: '')
      msg_template.gsub(
        '{{datetime}}',
        DateTime.now.in_time_zone(TIMEZONE_EST).strftime('%Y-%m-%d %l:%M %p %Z')
      ).gsub(
        '{{product_id}}',
        product_id
      )
    end

  end
end
