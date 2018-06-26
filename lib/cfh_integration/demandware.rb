module Demandware
  class XMLGenerator
    attr_reader :xml, :output_file, :date, :cached_grouping_ids, :custom_cma_date

    def initialize(output_file, date = Date.today, custom_cma_date = nil)
      @output_file = output_file
      @date = date
      @custom_cma_date = custom_cma_date
      @xml = Builder::XmlMarkup.new(indent: 2)
      @cached_grouping_ids = {}
    end

    def serialize_color_codes(skus, products)
      write_to_xml {
        document('belk-master-catalog') {
          skus.each { |sku|
            @xml.tag!('product', 'product-id' => sku['PRODUCT_ID']) {
              @xml.tag!('custom-attributes') {
                @xml.tag!('custom-attribute', sku['NRFCOLORCODE'], 'attribute-id' => 'nrfColorCode')
                @xml.tag!('custom-attribute', sku['OMNICOLORDESCRIPTION'], 'attribute-id' => 'omniChannelColorDescription')
                @xml.tag!('custom-attribute', 'attribute-id' => 'refinementColor') {
                  sku.to_h.slice(*ProcessColorCodeFeed::SUPER_COLOR_ATTRIBUTES).values.reject { |value| !value.present? }.each { |super_color|
                    @xml.tag!('value', super_color.downcase)
                  }
                }
              }
            }
          }
          products.grouped_variants.each { |parent, _skus|
            missing_color = _skus.any? { |sku| !sku.omniChannelColorDescription }
            missing_size = _skus.any? { |sku| !sku.omniSizeDesc }
            next if missing_color || missing_size
            @xml.tag!('product', 'product-id' => parent.id) {
              @xml.tag!('variations') {
                @xml.tag!('attributes') {
                  serialize_colors(_skus)
                  serialize_sizes(_skus)
                }
              }
            }
          }
        }
      }
    end

    def serialize_colors(skus)
      @xml.tag!('variation-attribute', 'attribute-id' => 'color', 'variation-attribute-id' => 'color') {
        @xml.tag!('display-name', 'color')
        @xml.tag!('variation-attribute-values') {
          skus.map do |sku|
            next unless sku.color && sku.omniChannelColorDescription
            { 'color' => sku.color, 'description' => sku.omniChannelColorDescription }
          end.uniq.compact { |sku| sku['color'] }.uniq.each { |sku|
            @xml.tag!('variation-attribute-value', 'value' => sku['color']) {
              @xml.tag!('display-value', sku['description'] )
            }
          }
        }
      }
    end

    def serialize_sizes(skus)
      @xml.tag!('variation-attribute', 'attribute-id' => 'size', 'variation-attribute-id' => 'size') {
        @xml.tag!('display-name', 'size')
        @xml.tag!('variation-attribute-values') {
          skus.map do |sku|
            next unless sku.size && sku.omniSizeDesc
            { 'size' => sku.size, 'description' => sku.omniSizeDesc }
          end.uniq.compact.each { |sku|
            @xml.tag!('variation-attribute-value', 'value' => sku['size']) {
              @xml.tag!('display-value', sku['description'] )
            }
          }
        }
      }
    end

    def serialize_inventory(parents)
      write_to_xml {
        document('belk-master-catalog') {
          parents.each { |parent|
            @xml.tag!('product', 'product-id' => parent.product_id) {
              @xml.tag!('custom-attributes') {
                @xml.tag!('custom-attribute', parent.first_inventory_date.strftime("%Y-%m-%d"), 'attribute-id' => 'inventoryAvailDate')
              }
            }
          }
        }
      }
    end

    def create_online_flag_categories(categories)
      write_to_xml {
        document('belk-storefront-catalog') {
          categories.each do |category|
            @xml.tag!('category', 'category-id' => category.product_id) {
              @xml.tag!('online-flag', category['online-flag'])
            }
          end
        }
      }
    end

    def create_from_grouped_skus(products, parents, regular_price_skus, skus_to_include)
      puts 'getting all_events'
      start_time = Time.now
      all_events = products.map do |sku, events|
        [ sku, events, CMAEvent.active_for_sku(custom_cma_date || date + 1.day, events) ]
      end
      puts "#{all_events.count} all_events calculated in #{(Time.now - start_time) / 60} minutes"

      puts 'writing XML'
      start_time = Time.now
      write_to_xml {
        document('belk-master-catalog') {
          all_events.each do |sku, events, future_events|
            next unless events.present? || future_events.present?
            cma_events_xml_representation(sku, events, future_events)
          end
          parents.each do |parent_id, events|
            next unless parent_id.present?
            parent_cma_events_xml_representation(parent_id, events)
          end
          regular_price_skus.each do |sku|
            regular_price_xml_representation(sku)
          end
        }
      }
      puts "xml generated in #{(Time.now - start_time) / 60} minutes"
    end

    def create_from_category_tree(tree)
      all_nodes = prepare_tree(tree)
      write_to_xml {
        document('belk-storefront-catalog') {
          all_nodes.each do |node|
            tree_node_xml_representation(node)
          end
        }
      }
    end

    private

    def prepare_tree(tree)
      # Collect all Nodes
      nodes = tree.root.map do |node|
        next if node.skip_from_xml?
        node
      end.compact

      # Sort all Nodes
      nodes.sort! { |x,y| x.node_type <=> y.node_type }
    end

    def tree_node_xml_representation(node)
      if node.category?
        if node.removed?
          @xml.tag!('category', 'category-id' => node.name, 'mode' => 'delete')
        else
          @xml.tag!('category', 'category-id' => node.name) {
            @xml.tag!('display-name', node.content[:name], 'xml:lang' => 'x-default') if node.content[:name].presence
            %w(online-flag).each do |property|
              value = node.content.stringify_keys[property].to_s
              if value.present?
                # always set online-catalog to false
                node.name == 'offline-category' ? @xml.tag!(property, 'false') : @xml.tag!(property, value)
              end
            end
            if node.parent
              @xml.tag!('parent', node.parent.name) if node.parent.name.presence
            end
            # serialize showInMenu
            @xml.tag!('custom-attributes') {
              @xml.tag!('custom-attribute', !!node.content[:show_in_menu].present?, 'attribute-id' => 'showInMenu')
            }
          }
        end
      elsif node.product?
        to_include = []
        if node.content[:grouping_condition] == 'Only'
          dedup_groupings(node) { append_groupings(to_include, node) }
        elsif node.content[:grouping_condition] == 'Exclude'
          to_include.push node.name
        else
          to_include.push node.name
          dedup_groupings(node) { append_groupings(to_include, node) }
        end

        to_include.flatten.compact.each do |value|
          if node.removed?
            @xml.tag!('category-assignment', 'category-id' => node.content[:parent_sid], 'product-id' => value, 'mode' => 'delete')
          else
            @xml.tag!('category-assignment', 'category-id' => node.content[:parent_sid], 'product-id' => value) {
              @xml.tag!('primary-flag', true) if node.parent.content[:is_primary_category]
              @xml.tag!('online-from', node.parent.content[:online_from]) if node.parent.content[:online_from]
              @xml.tag!('online-to', node.parent.content[:online_to]) if node.parent.content[:online_to]
            }
          end
        end
      end
    end

    def append_groupings(to_include, node)
      if node.content[:groupings] && !cached_grouping_ids[node.content[:parent_sid]].include?(node.content[:groupings])
        if node.removed?
          to_include.push node.content[:groupings] if !Groupings.persisted?(node.content)
        else
          to_include.push node.content[:groupings]
        end
      end
    end

    def dedup_groupings(node, &block)
      cached_grouping_ids[node.content[:parent_sid]] ||= Set.new
      block.call
      cached_grouping_ids[node.content[:parent_sid]] << node.content[:groupings]
    end

    def cma_events_xml_representation(sku, events, future_events)
      @xml.tag!('product', 'product-id' => sku) {
        @xml.tag!('custom-attributes') {
          @xml.tag!('custom-attribute', 'attribute-id' => 'eventCodeID') {
            if events.present?
              values = []
              current_events = events.reject { |event| event.ended_on?(date) }
              current_events.each do |event|
                values << event.event_id
                values << event.adevent if event.adevent != 'NONEVENT'
              end
              values.uniq.each { |val| @xml.value(val) }
            else
              @xml.value
            end
          }
          @xml.tag!('custom-attribute', 'attribute-id' => 'currentEventCodeID') {
            values = []
            future_events.each do |event|
              values << event.event_id
              values << event.adevent if event.adevent != 'NONEVENT'
            end
            future_events.present? ? values.uniq.each { |val| @xml.value(val) } : @xml.value
          }
        }
      }
    end

    def parent_cma_events_xml_representation(parent_id, events)
      @xml.tag!('product', 'product-id' => parent_id) {
        @xml.tag!('custom-attributes') {
          @xml.tag!('custom-attribute', 'attribute-id' => 'bonusEventCodeID') {
            if events.present?
              current_events = events.reject do |event|
                event.ended_on?(date) || !event.adevent.include?('BB') || event.adevent == 'NONEVENT'
              end
              values = current_events.map(&:adevent)
              values.uniq.each { |val| @xml.value(val) }
            else
              @xml.value
            end
          }
        }
      }
    end

    def regular_price_xml_representation(sku)
      @xml.tag!('product', 'product-id' => sku.sku_code) {
        @xml.tag!('custom-attributes') {
          @xml.tag!('custom-attribute', sku.regular_price, 'attribute-id' => 'regularPrice')
        }
      }
    end

    def write_to_xml
      File.open(output_file, 'wb') do |file|
        file.write(yield)
      end
    end

    def document(catalog_id, &body)
      @xml.catalog(
        'xmlns' => 'http://www.demandware.com/xml/impex/catalog/2006-10-31',
        'catalog-id' => catalog_id, &body)
    end
  end

  class XMLParser
    attr_reader :input_files

    EXCEPT_ATTRIBUTE_KEYS = [:'salsify:digital_assets']

    def initialize(input_files)
      input_files.each do |file|
        raise MissingXMLFile, "missing #{file} for xml parser" unless File.exists?(file)
      end
      @input_files = input_files
    end

    def inventory_skus
      xml = Nokogiri::XML(File.open(input_files.first)).remove_namespaces!
      date = Date.today
      xml.xpath('//record').map do |sku|
        next unless sku.at('allocation')
        {
          product_id: sku.at('@product-id').value,
          inventory: sku.at('allocation').content,
          inventory_reset_date: date.strftime('%Y-%m-%d')
        }
      end.compact
    end

    def inventory_sku_ids
      inventory_skus.map { |sku| sku[:product_id] }
    end

    def skus
      skus_container = []
      per_product do |product|
        next unless product.variant?
        skus_container << product.product_id
      end
      skus_container.uniq
    end

    def style_map
      style_container = Hash.new { |h,k| h[k] = Set.new }
      per_product do |product|
        next unless product.style?
        product.variant_ids.each { |id| style_container[product.product_id] << id }
      end
      style_container
    end

    def all_to_json(file)
      attr_map = PIMAttributesMap.new
      import = Amadeus::Import::JsonImport.new

      product_keys = Set.new

      per_product do |product_hash|
        product = product_hash.to_json
        attr_map.format_values(product)
        append_digital_asset(import, product.delete(:"salsify:digital_assets"))
        import.products.deep_merge!({ product[:product_id] => product })
        product_keys.merge(product.keys)
      end

      product_keys.subtract(EXCEPT_ATTRIBUTE_KEYS)
      # this attributes does not appear to ever get used?
      product_keys.to_a.each do |pk|
        attrib = Amadeus::Import::Attribute.new
        attrib.id = attrib.name = pk
        attrib.data_type = attr_map.data_type(pk)
        import.add_attribute(attrib)
      end

      header = Amadeus::Import::Header.new
      header.mode = :upsert
      header.version = '2'
      header.scope = [ :attributes, :digital_assets, { products: product_keys.to_a }]
      import.header = header

      File.open(file, 'w') { |f| f.write(import.serialize(indent: 0)) }
    end

    def append_digital_asset(import, digital_assets)
      return unless digital_assets.present?
      digital_assets.each do |digital_asset|
        asset = Amadeus::Import::DigitalAsset.new
        asset.url = digital_asset['salsify:id']
        import.add_digital_asset(asset)
      end
    end

    def variants_to_json(file)
      import = Amadeus::Import::JsonImport.new

      per_product do |product|
        if product.parent?
          product.variants.each do |variant|
            import.products.deep_merge!({ variant[:product_id] => variant })
          end
        end
      end

      header = Amadeus::Import::Header.new
      header.mode = :upsert
      header.scope = [ { products: [ 'product_id', 'salsify:parent_id' ] } ]
      import.header = header

      File.open(file, 'w') { |f| f.write(import.serialize(indent: 0)) }
    end

    def sku?(product_id)
      product_id.start_with?('04') # designates a SKU
    end

    def product_sets_to_json(file)
      import = Amadeus::Import::JsonImport.new

      per_product do |product|
        if product.product?
          # bubble up groupings to the parent level
          product.groupings.each do |grouping|
            grouping[:product_id] = sku_to_parent_mapping[grouping[:product_id]] if sku?(grouping[:product_id])
            import.products.merge!({ grouping[:product_id] => grouping })
          end
        end
      end

      attrib = Amadeus::Import::Attribute.new
      attrib.id = :Groupings
      attrib.name = :Groupings
      import.add_attribute(attrib)

      header = Amadeus::Import::Header.new
      header.mode = :upsert
      header.scope = [:attributes, {:products => [:product_id, :Groupings]}]
      import.header = header

      File.open(file, 'w') { |f| f.write(import.serialize(indent: 0)) }
    end

    def write_object(file, object, comma)
      file.write(",") if comma
      file.write(JSON.pretty_generate(object))
    end

    def products
      result = []
      per_product do |product|
        result << product
      end
      result
    end

    private

    def per_product
      each_file do |file|
        Nokogiri::XML::Reader(file).each do |node|
          if node.name == 'product' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            product = Nokogiri::XML(node.outer_xml).children.first
            yield XMLParser::XMLProduct.new(product)
          end
        end
      end
    end

    def sku_to_parent_mapping
      @sku_to_parent_mapping ||= begin
        hash = {}
        per_product do |product|
          next unless product.parent?
          next unless product.variants.present?
          parent_id = product.variants.first[:'salsify:parent_id']
          product.variants.each { |variant| hash[variant[:product_id]] = parent_id }
        end
        hash
      end
    end

    def each_file
      return enum_for(:each_file) unless block_given?

      input_files.each do |file|
        File.open(file) do |descriptor|
          yield descriptor
        end
      end
    end

    def create_tmp_file
      Tempfile.new('products')
    end
  end

  class PIMAttributesMap
    attr_reader :attribute_map

    def initialize
      return @attribute_map if defined?(@attribute_map)
      @attribute_map ||= {}

      csv = CustomCSV::Wrapper.new('lib/cfh_integration/cache/PIM_Attribute_list.csv')
      csv.foreach do |row|
        @attribute_map[row[:attribute_name].to_sym] = row.to_hash.except(:attribute_name)
      end
      @attribute_map
    end

    def data_type(key)
      key = key.to_sym
      type = @attribute_map.fetch(key, {}).fetch(:type, nil)
      case
        when ['string', 'set-of-string'].include?(type)
          'string'
        when [:images, :swatch_images].include?(key)
          'digital_asset'
        when type == 'int'
          'number'
        when type
          type
        when [:'salsify:digital_assets'].include?(key)
          'array'
        else
          'string'
      end
    end

    def format_values(object)
      object.each do |k, v|
        object[k] = case data_type(k)
          when 'string'
            v.to_s
          when 'number'
            v.to_s.match('\.') ? Float(v) : Integer(v) rescue v.to_s
          when 'date'
            Date.strptime(v, '%Y-%m-%d').to_s rescue v
          else
            v
          end
      end
    end
  end

  class XMLParser
    class XMLProduct
      BELK_PREFIX = 'http://belk.scene7.com'.freeze

      TAGS = %w(display_name upc short_description long_description online_flag available_flag
        searchable_flag tax_class_id brand pinterest_enabled_flag facebook_enabled_flag ean unit
        min_order_quantity step_quantity).deep_freeze

      def initialize(xml_element)
        @element = xml_element
        @json = {}
      end

      def color_code
        @element.at('custom-attribute[@attribute-id="nrfColorCode"]').try(:content)
      end

      # Details about these three methods - pim_to_salsify_sample/readme.md
      def product?
        product_set_products.present?
      end

      def style?
        variant_ids.present?
      end

      def variant?
        upc.present? && il_eligible.to_s != 'true'
      end

      def parent?
        empty_upc? || (upc.present? && il_eligible == 'true')
      end

      def variant_ids
        search('variants/variant').map { |variant| variant.attributes['product-id'].value }.uniq
      end

      def to_json
        @json[:product_id] = product_id

        @json.merge!(tags)
        @json.merge!(custom_attributes)
        @json.merge!(images)

        @json
      end

      def groupings
        grouping_ids = search('product-set-products/product-set-product') \
          .map{ |x| x.attributes['product-id'].value } \
          .uniq

        grouping_ids.map do |group_pid|
          new_product = {}
          new_product[:product_id] = group_pid
          new_product[:Groupings] = product_id
          new_product
        end
      end

      def variants
        variants_ids = search('variants/variant') \
          .map{ |x| x.attributes['product-id'].value } \
          .uniq

        variants_ids.map do |variant|
          object = {}
          object[:product_id] = variant
          object[:'salsify:parent_id'] = product_id
          object
        end
      end

      def product_id
        attributes['product-id'].value.to_s
      end

      private

      def images
        imageURL = parse_images('imageURL')
        swatch = parse_images('swatch')

        result = {}
        result.merge!({images: imageURL}) unless imageURL.empty?
        result.merge!({swatch_images: swatch}) unless swatch.empty?

        merged = imageURL + swatch
        if merged.present?
          merged = merged.map{|x| {'salsify:id' => x, 'salsify:url' => x}}
          result.merge!({'salsify:digital_assets': merged})
        end
        result
      end

      def tags
        TAGS.map do |tag|
          text = at(format_tag(tag)).try(:text)
          [ tag.to_sym, text ] if text.present?
        end.compact.to_h
      end

      def custom_attributes
        search('custom-attributes/custom-attribute').map do |elem|
          next unless elem.attributes['attribute-id'] || elem.children
          key = elem.attributes['attribute-id'].value.to_sym
          text = elem.children.text.strip
          value = case text
          when 'No' then false
          when 'Yes' then true
            else text
          end
          [key, value]
        end.compact.to_h
      end

      def method_missing(method_sym, *arguments, &block)
        @element.send(method_sym, *arguments, &block)
      end

      def product_set_products
        at('product-set-products')
      end

      def upc
        at('upc').try(:content)
      end

      def empty_upc?
        upc.blank?
      end

      def il_eligible
        at("custom-attributes/custom-attribute[@attribute-id='il_eligible']").try(:content)
      end

      def format_tag(tag)
        tag.gsub('_', '-')
      end

      def parse_images(view_type)
        search("images//image-group[@view-type='#{view_type}']//image") \
        .map { |tag| tag.attributes['path'].value} \
        .map { |link| BELK_PREFIX + link}
      end
    end
  end

  class Groupings < Struct.new(:node)
    include Muffin::SalsifyClient

    def self.persisted?(node)
      new(node).persisted?
    end

    def persisted?
      return unless list_id && product_id
      puts "looking up grouping #{product_id}..."
      skus.try(:count) || 0 >= 1
    end

    def skus
      salsify_client(org_id: 3562).products(filter_params).products
    rescue
      puts "ERROR occured looking up #{product_id} from #{list_id}..."
    end

    def filter_params
      {
        filter: "='Groupings':'#{product_id}',list:#{list_id}:product_type:root",
        list_id: list_id
      }
    end

    def product_id
      node[:groupings]
    end

    def list_id
      node[:list_id]
    end

  end

  class MissingXMLFile < StandardError; end
end
