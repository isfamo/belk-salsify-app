module ImageManagement
  class SampleReq
    include Muffin::SalsifyClient
    include Helpers

    attr_reader :products

    def initialize(products)
      @products = products
    end

    def self.start_sample_req(products)
      new(products).start_sample_req
    end

    def start_sample_req
      execute_product_updates
    end

    def execute_product_updates
      t = Time.now
      puts "#{STAMP} Updating #{product_ids.length} products for started sample process"
      Parallel.each(product_ids, in_threads: NUM_THREADS_CRUD) do |product_id|
        client.update_product(product_id, product_updates)
      end
      puts "#{STAMP} Completed product updates in #{(Time.now - t).round(1)} seconds"
    end

    def product_updates
      { PROPERTY_IMAGE_TASK_STATUS => 'Open' }
    end

    def product_ids
      @product_ids ||= products.map { |product| product['salsify:id'] }
    end

    def client
      @client ||= salsify_client(org_id: ENV['CARS_ORG_ID'].to_i)
    end

  end
end
