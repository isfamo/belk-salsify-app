module PIMFeed
  class SalsifyImportFile
    include Amadeus::Import
    include Constants

    DIGITAL_ASSETS = [
      'mainImage',
      'swatchImage',
      'viewerImage',
      'imagePath'
    ].freeze
    DIGITAL_ASSET_ATTRIBUTES = DIGITAL_ASSETS + [
      'shotType',
      'imageName',
      'vendorUploadedImageName'
    ].freeze
    ATTRIBUTES_TO_IGNORE = [
      COLOR_MASTER,
      COLOR_CODE_CLONE,
      EXISTING_PRODUCT,
      'parent_id_clone'
    ].freeze

    attr_reader :json_import, :attribute_map, :file_location, :mode

    def initialize(attribute_map, file_location, mode)
      @json_import = JsonImport.new
      @attribute_map = attribute_map
      @file_location = file_location
      @mode = mode
    end

    def serialize
      # add_color_master_attributes
      # define_color_master_skus
      # add_images_to_style
      add_header
      # add_global_attributes
      add_digital_asset_attributes
      add_attribute_values
      write_to_file
    end

    def define_color_master_skus
      DefineColorMasterSkus.run(json_import.products) if mode == :delta
    end

    def add_images_to_style
      AddImagesToStyle.run(json_import.products)
    end

    def add_color_master_attributes
      attributes.add(COLOR_MASTER).add(ALL_IMAGES)
    end

    def add_header
      header = Header.new
      header.scope = [
        # :attributes,
        :attribute_values,
        { products: 'dynamic' }
      ]
      header.version = '2'
      json_import.add_header(header)
    end

    def add_global_attributes
      (global_attributes - [ PARENT_ID, COLOR_CODE_CLONE ]).each do |attribute|
        amadeus_attribute = Attribute.new
        amadeus_attribute.id = attribute
        amadeus_attribute.name = attribute_name(attribute)
        amadeus_attribute.data_type = data_type(attribute)
        amadeus_attribute.attribute_group = attribute_group(attribute)
        json_import.add_attribute(amadeus_attribute)
      end
    end

    def add_digital_asset_attributes
      asset_attributes.each do |attribute|
        amadeus_attribute = Attribute.new
        amadeus_attribute.id = amadeus_attribute.name = attribute
        amadeus_attribute.data_type = attribute.include?('URL') ? 'link' : 'html'
        amadeus_attribute.attribute_group = attribute_group(attribute)
        json_import.add_attribute(amadeus_attribute)
      end
    end

    def add_attribute_values
      json_import.products.values.each do |product|
        enumerations = product.slice(*enumerated_attributes)
        enumerations.each do |attribute, values|
          Array.wrap(values).compact.each do |value|
            next unless value.present?
            attribute_value = AttributeValue.new
            attribute_value.id = attribute_value.name = value
            attribute_value.attribute_id = attribute
            json_import.add_attribute_value(attribute_value)
          end
        end
      end
    end

    def enumerated_attributes
      attribute_map.salsify_map.keys.select do |attribute|
        data_type(attribute) == 'enumerated'
      end
    end

    def attribute_name(attribute)
      attribute_map.attribute_name(attribute)
    end

    def data_type(attribute)
      attribute_map.data_type(attribute)
    end

    def attribute_group(attribute)
      digital_asset_attribute?(attribute) ? image_attribute_group(attribute) :
        attribute_map.attribute_group(attribute)
    end

    def image_attribute_group(attribute)
      attribute.split('-', 3).first(2).map(&:strip).join(' ')
    end

    def digital_asset_attribute?(attribute)
      DIGITAL_ASSET_ATTRIBUTES.any? { |asset_attribute| attribute.to_s.include?(asset_attribute) }
    end

    def add_product(product)
      json_import.products[product['product_id']] = product.keys.map do |attribute|
        next if ATTRIBUTES_TO_IGNORE.include?(attribute)
        salsify_attribute_name = attribute_map.xml_map[attribute].try(:[], 'Salsify ID')
        attributes.add(salsify_attribute_name || attribute)
        [ salsify_attribute_name || attribute, product.delete(attribute) ]
      end.compact.to_h
    end

    def global_attributes
      attributes - asset_attributes
    end

    def asset_attributes
      @asset_attributes ||= attributes.select do |attribute|
        DIGITAL_ASSETS.any? { |asset_attribute| attribute.include?(asset_attribute) }
      end
    end

    def attributes
      @attributes ||= Set.new
    end

    def write_to_file
      File.open(file_location, 'w') { |f| f.write(json_import.serialize) }
    end

    class DefineColorMasterSkus < Struct.new(:products)
      include Constants

      def self.run(products)
        new(products).run
      end

      def run
        grouped_skus.each do |parent, skus|
          next unless parent
          grouped_skus = skus.group_by { |sku| sku[COLOR_CODE_CLONE] }
          grouped_skus.each do |color, color_skus|
            next unless color
            next unless color_skus.any? { |sku| sku[EXISTING_PRODUCT].nil? }
            color_skus.first[COLOR_MASTER] = true if !color_skus.any? { |sku| !!sku[COLOR_MASTER] }
          end
        end
      end

      def grouped_skus
        skus.group_by { |sku| sku['parent_id_clone'] }
      end

      def skus
        products.values.select { |product| !!product[PARENT_ID] }
      end

    end

    #
    # AddImagesToStyle expecting this format
    # {
    #   '1234' => {
    #     'product_id' => '1234',
    #     'nrfColorCode' => '000'
    #   }
    # }
    #

    class AddImagesToStyle < Struct.new(:products)
      include Constants

      def self.run(products)
        new(products).run
      end

      def run
        coalese_styles
        coalese_groupings
      end

      def coalese_styles
        grouped_products.each do |parent_id, skus|
          if parent_id.nil?
            # `skus` is the list of parentless products (styles).
            # If any of them have no skus, empty All Images property.
            skus.select do |parentless_product|
              grouped_products[parentless_product['salsify:id']].nil?
            end.each do |parentless_skuless_product|
              parentless_skuless_product[ALL_IMAGES] = construct_html([])
            end
          else
            parent = products[parent_id]
            color_masters = color_masters(skus)
            next unless parent &&
              skus.any? { |sku| sku[EXISTING_PRODUCT].nil? } &&
              color_masters.present?
            parent[ALL_IMAGES] = construct_html(color_masters)
            skus.each { |sku| sku[ALL_IMAGES] = ' ' }
          end
        end
      end

      def coalese_groupings
        groupings.each do |grouping|
          # Construct All Images html, but don't apply if empty
          all_imgs_html = construct_html(Array.wrap(grouping))
          grouping[ALL_IMAGES] = all_imgs_html if all_imgs_html
        end
      end

      def construct_html(skus)
        html_rows = compute_images(skus)
        if !skus.empty? && html_rows && !html_rows.empty?
          '<div id="wrapper" style="text-align: center;">' + html_rows.join('\'') + '</div>'
        else
          '<div id="wrapper" style="text-align: center;">No Images</div>'
        end
      end

      def compute_images(skus)
        skus.flat_map do |sku|
          images(sku).flat_map do |shot_type, image_array|
            urls = image_array.flatten.select { |element| element ? element.include?('http') : false }
            next unless urls.present?
            html = '<div class="row">'
            urls.map do |url|
              html += "<div class=\"column\" style=\"display:inline-block;\"><div class=\"container\"><img src=\"#{url}\" height=\"#{IMG_HEIGHT}px\"><p><a href=\"#{url}\">#{link_text(sku, shot_type)}</a></p></div></div>"
            end
            html += '</div>'
          end
        end
      end

      def images(sku)
        sku.select do |property, _|
          property.include?('mainImage URL') || property.include?('swatchImage URL')
        end.group_by { |property, _| property.split('-', 3).second } # grouping by shot type
      end

      def link_text(sku, shot_type)
        color_description = sku[OMNI_COLOR] || sku[VENDOR_COLOR]
        text = "#{sku[COLOR_CODE]}_#{shot_type.strip}"
        text += "_#{color_description}" if color_description
        text
      end

      def color_masters(skus)
        skus.select { |sku| sku[COLOR_MASTER] }
      end

      def grouped_products
        @grouped_products ||= products.values.group_by { |product| product[PARENT_ID] }
      end

      def groupings
        products.values.select { |product| product[GROUPING_TYPE] }
      end

    end

  end
end
