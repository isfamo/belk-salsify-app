module NewProductWorkflow
  class Worker

    include Muffin::SalsifyClient

    attr_reader :new_products

    PRODUCT_ID_PROPERTY = 'product_id'.freeze
    GROUPINGS_PROPERTY = 'Included in Groupings'.freeze
    CHILD_PROPERTIES = ['skus', "SKU's", 'Child Styles'].freeze
    ORG_ID = ENV.fetch('CARS_ORG_ID')

    def initialize(new_products)
      @new_products = new_products
    end

    def self.run(new_products)
      new(new_products).run
    end

    def run
      new_products.each do |product|
        old_id = product['product_id']
        puts "Product:"
        product.each do |k,v|
          puts "#{k}: #{v}"
        end
        new_id = generate_grouping(product)
        puts "New Product ID:"
        puts new_id
        update_product_id(old_id, new_id)
        update_included_in_grouping_links(old_id, new_id)
      end
    end
    
    def generate_grouping(product)
      if product['vendorNumber'].present?
        puts "Vendor number present"
        new_id = "#{product['vendorNumber']}#{GroupingId.last.sequence}"
      else
        puts "Vendor number not present"
        new_id = "9999999#{GroupingId.last.sequence}"
      end
      GroupingId.increment
      new_id
    end

    def update_product_id(old_id, new_id)
      puts "Updating product id for product: #{old_id} to: #{new_id}"
      begin
        client.update_product(old_id, { PRODUCT_ID_PROPERTY => new_id })
      rescue RestClient::ResourceNotFound
        puts "ERROR: No product with ID #{old_id} found in org #{ORG_ID}"
      rescue
        puts "Error with updating product"
      end
    end

    def update_included_in_grouping_links(old_id, new_id)
      begin
        product = client.product(new_id)
        skus = []
        puts "Trying child product properties..."
        CHILD_PROPERTIES.each do |prop|
          puts "Trying #{prop}"
          skus << product[prop] if product[prop].present?
        end
        skus.flatten!
      rescue
        puts "Duplicate Webhook"
      end
      puts "Evaluating if we need to update grouped products..."
      begin
        if skus.present?
          puts "Child products: #{skus}"
          skus.each do |sku|
            puts "Child: #{sku}"
            groupings = client.product(sku)[GROUPINGS_PROPERTY]
            puts "Groupings: #{groupings}"
            if groupings.class == Hashie::Array
              groupings.map! do |link|
                link.gsub(old_id, new_id)
              end
            else
              groupings.gsub!(old_id, new_id)
            end
            puts "New Groupings: #{groupings}"
            client.update_product(sku, { GROUPINGS_PROPERTY => groupings })
          end
          puts "Updated Skus"
        else
          puts "No SKUs to update"
        end
      rescue => e 
          puts "Error updating grouped SKU's: #{e}"
      end
    end
  
    def client
      @client ||= salsify_client(org_id: ORG_ID)
    end

  end
end