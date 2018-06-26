module Maintenance

  class UpdateProductImport

    ORIGINAL_JSON = 'tmp/original_product_import.json'.freeze
    UPDATED_JSON = 'tmp/updated_product_import.json'.freeze

    def self.run
      new.run
    end

    def run
      products.each do |product_hash|
        product = product_hash.to_h
        attribute_map.format_values(product)
        import.products.deep_merge!({ product_hash.product_id => product })
        product_keys.merge(product.keys)
      end

      header = Amadeus::Import::Header.new
      header.mode = :upsert
      header.version = '2'
      header.scope = [{ products: product_keys.to_a }]
      import.header = header

      File.open(UPDATED_JSON, 'w') { |f| f.write(import.serialize(indent: 2)) }
    end

    def product_keys
      @product_keys ||= Set.new
    end

    def attribute_map
      @attribute_map ||= Demandware::PIMAttributesMap.new
    end

    def products
      @products ||= original_export.products.select { |product| product.product_id.start_with?('04') }
    end

    def import
      @import ||= Amadeus::Import::JsonImport.new
    end

    def original_export
      @original_export ||= Amadeus::Export::JsonExport.new(json_export: Oj.load(strings))
    end

    def strings
      puts 'opening file...'
      string = ''
      File.open('tmp/product_import.json').each(nil, 250_000_000) do |chunk|
        string += chunk
      end
      puts 'finished opening and reading file...'
      string
    end

  end
end
