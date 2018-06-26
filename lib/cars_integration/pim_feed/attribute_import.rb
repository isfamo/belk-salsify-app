module PIMFeed
  class AttributeImport
    include Muffin::SalsifyClient

    FILE_LOCATION = 'lib/cars_integration/output/attribute_import.json'.freeze
    IMPORT_ID = 145458

    def self.run
      new.run
    end

    def run
      build_import
      run_salsify_import
    end

    def build_import
      SalsifyImport.generate(attribute_map)
    end

    def attribute_map
      PIMFeed::Attributes.new
    end

    def run_salsify_import
      Salsify::Utils::Import.start_import_with_new_file(salsify_client(org_id: ENV.fetch('CARS_ORG_ID')), IMPORT_ID, FILE_LOCATION)
    end

    class SalsifyImport
      include Amadeus::Import

      attr_reader :json_import, :attribute_map

      def initialize(attribute_map)
        @json_import = JsonImport.new
        @attribute_map = attribute_map
      end

      def self.generate(attribute_map)
        new(attribute_map).generate
      end

      def generate
        add_header
        add_attributes
        serialize
      end

      def add_header
        header = Header.new
        header.scope = [ :attributes ]
        header.version = '2'
        json_import.add_header(header)
      end

      def add_attributes
        attribute_map.xml_map.each { |_, attribute| build_attribute(attribute) }
      end

      def build_attribute(attribute)
        amadeus_attribute = Attribute.new
        amadeus_attribute.id = attribute['Salsify ID']
        amadeus_attribute.name = attribute['Salsify Display Name']
        amadeus_attribute.data_type = attribute_map.data_type(attribute['XML Name'])
        amadeus_attribute.attribute_group = attribute['Attribute Group']
        json_import.add_attribute(amadeus_attribute)
      end

      def serialize
        File.open(AttributeImport::FILE_LOCATION, 'w') { |f| f.write(json_import.serialize) }
      end

    end

  end
end
