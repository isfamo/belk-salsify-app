module ImageManagement
  class PipWorkflow
    include Muffin::SalsifyClient

    attr_reader :products

    def initialize(products)
      @products = products
    end

    def self.pip_workflow_completed(products)
      new(products).pip_workflow_completed
    end

    def pip_workflow_completed
      execute_style_updates
    end

    def execute_style_updates
      style_update_by_id.each do |style_id, update_hash|
        client.update_product(style_id, update_hash)
      end
    end

    def style_update_by_id
      @style_update_by_id ||= products.map do |product|
        [product['salsify:id'], style_update_hash(product)]
      end.to_h.reject do |product_id, change_hash|
        change_hash.empty?
      end
    end

    def style_update_hash(product)
      changes = {}
      changes[PROPERTY_PENDING_BASE_PUBLISH] = true if product[PROPERTY_COPY_APPROVAL_STATE] != true
      changes
    end

    def client
      @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID').to_i)
    end

  end
end
