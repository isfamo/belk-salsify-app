module Enrichment
  class SetLookupAttributesJob
    include Muffin::SalsifyClient
    include PIMFeed::Constants

    PROPERTIES_TO_EXPORT = [
      PARENT_ID, PRODUCT_ID, COLOR_CODE, SIZE_CODE, DEPT, CLASS, VENDOR_NUMBER
    ].freeze
    NUM_THREADS_CRUD = 4

    attr_reader :initial_products

    def initialize(initial_products = nil)
      @initial_products = initial_products
    end

    def dictionary
      @dictionary ||= Dictionary.new
    end

    def perform
      puts "$ENRICHMENT ATTRIBUTES$ updating attributes on #{products.map(&:id)}..."
      Parallel.each(products, in_threads: NUM_THREADS_CRUD) do |product|
        enrichment_attributes(product).each do |attribute, value|
          next if value_exists?(product, attribute)
          begin
            # puts "$ENRICHMENT ATTRIBUTES$ updating #{product.id} attribute #{attribute} with value #{value || 'nil'}..."
            client.update_product(product.id, { attribute => value })
          rescue => error
            puts "$ENRICHMENT ATTRIBUTES$ unable to update #{product.id} with attribute #{attribute} and value #{value || 'nil'}..."
            puts "$ENRICHMENT ATTRIBUTES$ error updating #{product.id} with error: #{error.message}..."
            client.update_product(product.id, { attribute => nil })
          end
        end
      end
    end

    def value_exists?(product, attribute)
      client.product(product.id)[attribute]
    rescue
    end

    def products
      @products ||= if initial_products
        puts '$ENRICHMENT ATTRIBUTES$ running initial lookup attributes job...'
        initial_products.map! { |attributes| Product.new(attributes) }
      else
        puts '$ENRICHMENT ATTRIBUTES$ running subsequent lookup attributes job...'
        lists.flat_map do |list_id, mode|
          subsequent_products(list_id, mode).map! { |attributes| Product.new(attributes) }
        end
      end
    end

    def enrichment_attributes(product)
      if product.sku?
        {
          OMNI_SIZE => dictionary.omni_size(product.dept, product.nrf_size_code),
          REFINEMENT_SIZE => dictionary.refinement_size(product.dept, product.nrf_size_code),
          REFINEMENT_SUB_SIZE => dictionary.refinement_sub_size(product.dept, product.nrf_size_code),
          # OMNI_CHANNEL_COLOR => dictionary.omni_color(product.nrf_color_code),
          REFINEMENT_COLOR => dictionary.refinement_color(product.nrf_color_code),
        }
      elsif product.style?
        {
          IPH_CATEGORY => dictionary.dept_iph(product.dept, product.class),
          OMNI_CHANNEL_BRAND => dictionary.omni_brand(product.vendor_number)
        }
      end
    end

    def client
      salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
    end

    def subsequent_products(list_id, mode)
      run_response = client.create_export_run(export_run_body(list_id, mode))
      completed_response = Salsify::Utils::Export.wait_until_complete(client, run_response)
      json_export = JSON.parse(open(completed_response.url).read)
      Amadeus::Export::JsonExport.new(json_export: json_export, performance_mode: true).merged_products.map(&:to_h)
    end

    def export_run_body(list_id, mode)
      {
        configuration: {
          entity_type: :product,
          properties: "'#{PROPERTIES_TO_EXPORT.join('\',\'')}'",
          include_all_columns: false,
          format: :json,
          filter: "=list:#{list_id}:product_type:#{mode}"
        }
      }
    end

    def lists
      [
        [ ENV.fetch('ENRICHMENT_RULE_STYLE_REVIEW_LIST_ID'), :root ],
        [ ENV.fetch('ENRICHMENT_RULE_SKU_REVIEW_LIST_ID'), :all ]
      ]
    end

    class Product < Struct.new(:attributes)
      include PIMFeed::Constants

      def sku?
        attributes['product_id'].start_with?('04')
      end

      def style?
        !sku?
      end

      def id
        attributes.fetch(PRODUCT_ID, '')
      end

      def nrf_color_code
        attributes.fetch(COLOR_CODE, '')
      end

      def nrf_size_code
        attributes.fetch(SIZE_CODE, '')
      end

      def dept
        attributes.fetch(DEPT, '')
      end

      def class
        attributes.fetch(CLASS, '')
      end

      def vendor_number
        attributes.fetch(VENDOR_NUMBER, '')
      end

    end

  end
end
