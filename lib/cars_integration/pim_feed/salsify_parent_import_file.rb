module PIMFeed
  class SalsifyParentImportFile
    include Amadeus::Import
    include Constants

    attr_reader :json_import, :file_location

    def initialize(file_location)
      @json_import = JsonImport.new
      @file_location = file_location
    end

    def serialize
      add_header
      write_to_file
    end

    def add_header
      header = Header.new
      header.scope = [ { products: [ 'product_id' ] } ]
      header.version = '2'
      json_import.add_header(header)
    end

    def add_product(parent_id)
      json_import.products[parent_id] = { 'product_id' => parent_id }
    end

    def write_to_file
      File.open(file_location, 'w') { |f| f.write(json_import.serialize) }
    end

  end
end
