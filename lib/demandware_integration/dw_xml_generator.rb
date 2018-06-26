module Demandware

  class DwXmlGenerator

    XMLNS_DW_CATALOG = 'http://www.demandware.com/xml/impex/catalog/2006-10-31'.freeze
    DEFAULT_MAX_ITEMS_PER_XML_FILE = 100.freeze
    LOG_INTERVAL_XML_PRODUCT = 10000.freeze
    STAMP = '$DW XML GENERATE$'.freeze

    attr_reader :dw_products, :options

    def initialize(dw_products, options)
      @dw_products = dw_products
      @options = options
    end

    def self.build_xml(dw_products, options = {})
      new(dw_products, options).build_xml
    end

    def build_xml
      return nil if dw_products.empty?
      t = Time.now
      batch_count = 0
      batches = dw_products.each_slice(max_items_per_file).to_a
      total_batches = batches.length
      puts "#{STAMP} Building xml strings, splitting into #{total_batches} xml files, #{batches.flatten.length} total products"

      result = batches.map do |dw_product_batch|
        batch_count += 1
        xml = Builder::XmlMarkup.new(indent: 2)
        xml.instruct!(:xml, encoding: 'UTF-8')
        xml.tag!('catalog', 'xmlns' => XMLNS_DW_CATALOG, 'catalog-id' => catalog_id) do |catalog|
          count = 0
          total_products = dw_product_batch.length
          dw_product_batch.each do |dw_product|
            count += 1
            puts "#{STAMP} BUILDING XML: BATCH #{batch_count}/#{total_batches} | PRODUCT #{count}/#{total_products} | #{((Time.now - t) / 60).round(1)} MIN" if count % LOG_INTERVAL_XML_PRODUCT == 0
            build_dw_product_xml!(dw_product, catalog)
          end
        end
        xml.target!
      end
      puts "#{STAMP} Built #{result.length} xml strings in #{((Time.now - t) / 60).round(1)} minutes"
      result
    end

    def build_dw_product_xml!(dw_product, xml_tag)
      meta = dw_product.delete('meta')
      apply_xml(sort_tags(dw_product), xml_tag)
    end

    def sort_tags(dw_product)
      {
        'product' => DW_XML_FIRST_LEVEL_ORDER.map { |xml_item|
          next unless dw_product['product'].keys.include?(xml_item)
          [xml_item, dw_product['product'][xml_item]]
        }.compact.to_h.merge(
          dw_product['product'].select { |key, value|
            key.include?('xml-attribute') || key == 'xml-value'
          }
        )
      }
    end

    def apply_xml(hash, xml_tag)
      hash.each do |key, value|
        if key.start_with?('xml-attribute') || key.start_with?('xml-value')
          next
        elsif value.is_a?(Hash)
          # value is a hash either with a single
          # child value, or with more xml tags inside
          if !value['xml-value'].nil?
            xml_tag.tag!(key, parse_xml_attributes(value), value['xml-value'])
          elsif child_tag_names(value).empty?
            xml_tag.tag!(key, parse_xml_attributes(value))
          else
            xml_tag.tag!(key, parse_xml_attributes(value)) do |child_tag|
              apply_xml(value, child_tag)
            end
          end
        elsif value.is_a?(Array)
          # value is an array of child tags with the
          # same name, with 'key' being the tag name
          value.each do |child_hash|
            # child_hash is a hash either with a single
            # child value, or with more xml tags inside
            if !child_hash['xml-value'].nil?
              xml_tag.tag!(key, parse_xml_attributes(child_hash), child_hash['xml-value'])
            elsif child_tag_names(child_hash).empty?
              xml_tag.tag!(key, parse_xml_attributes(child_hash))
            else
              xml_tag.tag!(key, parse_xml_attributes(child_hash)) do |child_tag|
                apply_xml(child_hash, child_tag)
              end
            end
          end
        else
          # value is a single child value of
          # the tag with 'key' as its name
          xml_tag.tag!(key, value)
        end
      end
    end

    # Parse out key-value pairs from the hash whose key is like "xml-attribute:somevalue"
    # Returns a hash like { "somevalue" => "12345" }
    def parse_xml_attributes(hash)
      hash.select do |key, value|
        key.start_with?('xml-attribute')
      end.map do |key, value|
        [key.partition(':').last, value]
      end.to_h
    end

    def child_tag_names(hash)
      hash.reject do |key, value|
        key.start_with?('xml-attribute') || key.start_with?('xml-value')
      end.keys
    end

    def max_items_per_file
      @max_items_per_file ||= ENV['DW_MAX_ITEMS_PER_XML_FILE'] ? ENV['DW_MAX_ITEMS_PER_XML_FILE'].to_i : DEFAULT_MAX_ITEMS_PER_XML_FILE
    end

    def catalog_id
      @catalog_id ||= begin
        if options[:mode].nil? || options[:mode] == XML_MODE_MASTER
          DW_CATALOG_ID_MASTER
        elsif options[:mode] == XML_MODE_LIMITED
          DW_CATALOG_ID_LIMITED
        end
      end
    end

  end

end
