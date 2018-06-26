module PIMFeed
  class XMLParser

    attr_reader :files, :attribute_map, :mode

    IPH_DESIGNATION_FILE_LOCATION = 'lib/cars_integration/cache/iph.xlsx'.freeze

    def initialize(files, attribute_map, mode)
      @files = files
      @attribute_map = attribute_map
      @mode = mode
    end

    def products
      parse_xml do |product|
        yield XMLParser::Product.new(product, attribute_map, existing_products, iph_designation, mode)
      end
    end

    def existing_products
      @existing_products ||= mode == :delta ? ImportProductMetadata.run(skus) : {}
    end

    def iph_designation
      @iph_designation ||= iph_designation_file.each(headers: true, clean: true).drop(1).map do |row|
        [ row['IPH'], row['Shot Type'] ]
      end.compact.to_h
    end

    def iph_designation_file
      Roo::Spreadsheet.open(IPH_DESIGNATION_FILE_LOCATION)
    end

    def skus
      sku_container = []
      parse_xml do |product|
        xml_product = XMLParser::Product.new(product)
        sku_container << xml_product.product_id
      end
      sku_container.uniq
    end

    def parse_xml(&block)
      files.each do |file|
        Nokogiri::XML::Reader(File.open(file)).each do |node|
          if node.name == 'product' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            product = Nokogiri::XML(node.outer_xml).children.first
            block.call(product)
          end
        end
      end
    end

    class Product
      include Constants

      BASE_ATTRIBUTES = %w(display-name upc short-description long-description online-flag available-flag
        searchable-flag tax-class-id brand pinterest-enabled-flag facebook-enabled-flag ean unit
        min-order-quantity step-quantity completion-date sitemap-included-flag online-to online-from
        pet-source).freeze

      def initialize(node, attribute_map = [], existing_products = [], iph_designation = {}, mode = :delta)
        @node = node
        @attribute_map = attribute_map
        @existing_products = existing_products
        @iph_designation = iph_designation
        @mode = mode
      end

      def product_id
        attributes['product-id'].value.to_s
      end

      def upc
        at('upc').try(:content)
      end

      def is_master?
        at('custom-attribute[@attribute-id=isMaster]').try(:content).try(:strip) == 'true'
      end

      def item_status
        status = at('Item_status').try(:text)
        status ? status : 'Initialized'
      end

      def grouping?
        !!grouping_type
      end

      def sku?
        upc.present? && !is_master? || product_id.start_with?('04')
      end

      def style?
        upc.blank? && is_master?
      end

      def serialize
        Serialize.run(self, @attribute_map, @mode)
      end

      def image_attributes
        @image_attributes ||= Images.construct(at('images'))
      end

      def scene_7_images?
        @scene_7_images ||= image_attributes.keys.any? do |attribute|
          attribute.include?('Scene7') && attribute.include?('mainImage')
        end
      end

      def of_or_sl
        @iph_designation[iph_category] ? { 'OForSL' => @iph_designation[iph_category] } : {}
      end

      def grouping_type
        @grouping_type ||= at('custom-attribute[@attribute-id=groupingType]').try(:content).try(:strip)
      end

      def iph_category
        custom_attributes['iphCategory']
      end

      def grouping_attributes
        search('product-set-products/product-set-product').each_with_object(
          Hash.new { |h, k| h[k] = Set.new }
        ) do |node, hash|
          hash[node.at('type').text.downcase.pluralize] << node.at('product-id').text
        end.map { |attribute, value| [ attribute, value.to_a ] }.to_h
      end

      def existing_parent_id?
        !!existing_product['salsify:parent_id']
      end

      def color_master
        existing_product['Color Master?']
      end

      def all_images
        existing_product['All Images'].present? ? existing_product['All Images'] : ' '
      end

      def full_feed_color_master
        true if at('Color_Master').try(:text) == 'true'
      end

      def image_workflow_status
        if @mode == :full
          'Completed'
        else
          if existing_product['ImageAssetSource']
            existing_product['ImageAssetSource']
          else
            scene_7_images? ? 'Completed' : 'Initiated'
          end
        end
      end

      # XXX only for full feed
      def default_task_id
        RrdTaskId.find_or_create_by(product_id: product_id).id
      end

      # XXX only for full feed
      def copy_approval_state
        true if custom_attributes['productCopyText'].present?
      end

      # XXX only for full feed
      def pip_workflow_status
        'Closed'
      end

      def pim_nrf_color_code
        existing_product['pim_nrfColorCode'] || custom_attributes['nrfColorCode']
      end

      def existing_product
        @existing_product ||= @existing_products[product_id] || {}
      end

      def existing_product?
        existing_product.present?
      end

      def base_attributes
        BASE_ATTRIBUTES.map do |tag|
          text = at(tag).try(:text)
          [ tag, Nokogiri::HTML(text).text ] if text.present?
        end.compact.to_h.merge('product_id' => product_id).merge('Item_status' => item_status)
      end

      def custom_attributes
        @custom_attributes ||= search('custom-attributes/custom-attribute').map do |element|
          next unless element.attributes['attribute-id'] || element.children
          key = element.attributes['attribute-id'].try(:value)
          next unless key
          text = extract_xml_text(element)
          value = case text
          when 'No'
            false
          when 'Yes'
            true
          else
            text
          end
          [ key, value ]
        end.compact.to_h.tap do |attributes|
          attributes[COLOR_CODE_CLONE] = attributes[COLOR_CODE]
          if existing_product[OMNI_CHANNEL_COLOR]
            attributes[OMNI_CHANNEL_COLOR] = existing_product[OMNI_CHANNEL_COLOR]
          else
            attributes[OMNI_CHANNEL_COLOR] = attributes[VENDOR_COLOR]
          end
          attributes[EXISTING_PRODUCT] = true if existing_product.present?
          attributes.delete(HEX_COLOR)
          populate_attributes_to_ignore(attributes)
        end
      end

      def parent_id
        at('parent-id').try(:content) unless existing_parent_id?
      end

      def parent_id_clone
        at('parent-id').try(:content)
      end

      def populate_attributes_to_ignore(attributes)
        ATTRIBUTES_TO_IGNORE.each do |attribute|
          xml_attribute = @attribute_map.salsify_map[attribute]['XML Name']
          attributes[xml_attribute] = existing_product[attribute] if existing_product[attribute]
        end
      end

      def extract_xml_text(element)
        if element.elements.count > 1
          element.elements.map { |sub_element| sub_element.text.strip }
        else
          element.text.strip
        end
      end

      def method_missing(method_sym, *arguments, &block)
        @node.send(method_sym, *arguments, &block)
      end

      class Images

        SCENE_7_IMAGE_ATTRIBUTES = [ 'mainImage', 'swatchImage', 'viewerImage' ].freeze
        VENDOR_PROVIDED_IMAGE_ATTRIBUTES = [ 'imageName', 'shotType', 'vendorUploadedImageName', 'imagePath' ].freeze
        URL_ATTRIBUTES = [ 'mainImage', 'swatchImage', 'viewerImage', 'imagePath' ].freeze
        HTML_ATTRIBUTES = [ 'mainImage', 'imagePath' ].freeze
        VENDOR_IMAGE = 'Vendor Images'.freeze
        SCENE_7_IMAGE = 'Scene7 Images'.freeze

        attr_reader :node

        def initialize(node)
          @node = node
        end

        def self.construct(node)
          new(node).construct
        end

        def construct
          return {} unless node
          image_attributes
        end

        def image_attributes
          scene_7_attributes.merge(vendor_provided_images)
        end

        def vendor_provided_images
          node.search('vendorProvidedImages').flat_map do |image|
            shot_type = image.at('shotType').try(:text)
            next unless shot_type.present?
            VENDOR_PROVIDED_IMAGE_ATTRIBUTES.flat_map do |tag|
              value = attribute_value(image, tag) ?
                attribute_value(image, tag) : element_value(image, tag)
              build_attribute(VENDOR_IMAGE, shot_type, tag, value)
            end
          end.compact.to_h
        end

        def scene_7_attributes
          node.search('scene7Image').flat_map do |image|
            shot_type = image.at('shotType').try(:text)
            next unless shot_type.present?
            SCENE_7_IMAGE_ATTRIBUTES.flat_map do |tag|
              value = attribute_value(image, tag) ?
                attribute_value(image, tag) : element_value(image, tag)
              build_attribute(SCENE_7_IMAGE, shot_type, tag, value)
            end
          end.compact.to_h
        end

        def build_attribute(image_type, shot_type, tag, value)
          if URL_ATTRIBUTES.include?(tag) && HTML_ATTRIBUTES.include?(tag)
            [
              [ "#{image_type} - #{shot_type} - #{tag} URL", value ],
              [ "#{image_type} - #{shot_type} - #{tag}", html(value) ]
            ]
          elsif URL_ATTRIBUTES.include?(tag)
            [ [ "#{image_type} - #{shot_type} - #{tag} URL", value ] ]
          else
            [ [ "#{image_type} - #{shot_type} - #{tag}", value ] ]
          end
        end

        def html(value)
          # This doesn't need both height and width, or else it will squash the images if they don't have the aspect ratio
          #   provided - so we only need to provide one or the other. Given these tend to be in portrait and not landscape,
          #   providing the height as the limit will then make the browser scale the width correctly and not squish images.
          "<img src=\"#{value}\" height=\"250\" />"
        end

        def element_value(element, tag)
          element.at(tag).try(:text)
        end

        def attribute_value(element, tag)
          element.at(tag).attr('path')
        end

      end

      class Serialize
        include Constants

        attr_reader :product, :attribute_map, :mode

        def initialize(product, attribute_map, mode)
          @product = product
          @attribute_map = attribute_map
          @mode = mode
        end

        def self.run(product, attribute_map, mode)
          new(product, attribute_map, mode).run
        end

        def run
          build_product
          format_values
        end

        def build_product
          mode == :full ? build_full_feed_product : build_delta_feed_product
        end

        def build_delta_feed_product
          if product.grouping?
            attributes.merge!(product.grouping_attributes)
            attributes.merge!(product.image_attributes)
            attributes['ImageAssetSource'] = product.image_workflow_status if product.image_workflow_status
          elsif product.style?
            attributes
          elsif product.sku?
            attributes.merge!(product.image_attributes)
            attributes['salsify:parent_id'] = product.parent_id if product.parent_id
            attributes['parent_id_clone'] = product.parent_id_clone
            attributes['ImageAssetSource'] = product.image_workflow_status if product.image_workflow_status
            attributes[GXS_DATA_RETRIEVED] = false unless product.existing_product?
            attributes['pim_nrfColorCode'] = product.pim_nrf_color_code
            attributes['new_sku'] = 'true' unless product.existing_product?
            attributes['color_master_removed'] = 'true' if product.item_status == 'Delete'
          else
            attributes
          end
          if product.existing_product?
            attributes[GXS_DATA_RETRIEVED] = product.existing_product[GXS_DATA_RETRIEVED]
          end
          attributes.compact!
        end

        def build_full_feed_product
          if product.grouping?
            attributes.merge!(product.grouping_attributes)
            attributes.merge!(product.image_attributes)
            attributes['Copy Approval State'] = product.copy_approval_state
            attributes['ImageAssetSource'] = product.image_workflow_status
            attributes['rrd_task_id'] = product.default_task_id
            attributes['pip_workflow_status'] = product.pip_workflow_status
          elsif product.style?
            attributes
            attributes['Copy Approval State'] = product.copy_approval_state
            attributes['rrd_task_id'] = product.default_task_id
            attributes['pip_workflow_status'] = product.pip_workflow_status
          elsif product.sku?
            attributes.merge!(product.image_attributes)
            attributes['salsify:parent_id'] = product.parent_id
            attributes['ImageAssetSource'] = product.image_workflow_status
            attributes['pim_nrfColorCode'] = product.pim_nrf_color_code
          else
            attributes
          end
          attributes.compact!
          attributes['Full Feed Import'] = true # XXX ONLY FOR FULL FEED!
        end

        def format_values
          attribute_map.format_values(attributes)
        end

        def attributes
          @attributes ||= {}.
            merge!(product.base_attributes).
            merge!(product.custom_attributes).
            merge!(product.of_or_sl)
        end

      end

    end
  end
end
