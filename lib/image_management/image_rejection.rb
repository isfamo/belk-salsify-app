require_rel '../helpers/salsify_filter.rb'
module ImageManagement
  class ImageRejection
    include Muffin::SalsifyClient
    include Helpers

    STAMP = '$IMAGE$'.freeze

    attr_reader :products

    def initialize(products)
      @products = products
    end

    def self.rejection_notes_updated(products)
      new(products).rejection_notes_updated
    end

    def self.image_spec_task_reopened(products)
      new(products).image_spec_task_reopened
    end

    def rejection_notes_updated
      # NOTE: We only care about groupings here. Only modify styles when Image Specialist Task Status is changed from Complete back to Open/ReOpen
      puts "#{STAMP} Processing #{products.length} groupings with PIP rejection notes updated"

      if rejected_grouping_ids.empty?
        puts "#{STAMP} No grouping products identified. Done!"
        return
      end

      Parallel.each(rejected_grouping_ids, in_threads: NUM_THREADS_CRUD) do |id|
        begin
          client.update_product(id, {
            PROPERTY_IMAGE_TASK_STATUS => IMAGE_TASK_STATUS_REOPENED,
            PROPERTY_IMAGE_TASK_COMPLETE => nil
          })
        rescue Exception => e
          puts "#{STAMP} ERROR while processing groupings rejected from PIP workflow for product #{id}: #{e.message}"
        end
      end
    end

    def image_spec_task_reopened
      # NOTE: We only care about skus with parent styles here. Groupings are handled by the `rejection_notes_updated` method.
      puts "#{STAMP} Processing #{products.length} skus with Image Specialist Task Status set to ReOpen"

      if rejected_sku_ids.empty?
        puts "#{STAMP} No reopened skus identified. Done!"
        return
      end

      Parallel.each(rejected_sku_ids, in_threads: NUM_THREADS_CRUD) do |id|
        begin
          client.update_product(id, { PROPERTY_IMAGE_TASK_COMPLETE => nil })
        rescue Exception => e
          puts "#{STAMP} ERROR while processing skus with image specialist task status reopened for sku #{id}: #{e.message}"
        end
      end
    end

    def rejected_grouping_ids
      @rejected_grouping_ids ||= products.select do |product|
        product[PROPERTY_GROUPING_TYPE]
      end.map do |product|
        product['salsify:id']
      end.uniq
    end

    def rejected_sku_ids
      @rejected_sku_ids ||= products.select do |product|
        product['salsify:parent_id']
      end.map do |product|
        product['salsify:id']
      end
    end

    def client
      @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID').to_i)
    end

  end
end
