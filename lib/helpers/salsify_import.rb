class SalsifyImport

  attr_reader :product_hashes, :client, :import_id, :product_id_property, :import_filepath

  def initialize(product_hashes, client, import_id, product_id_property, import_filepath)
    @product_hashes = product_hashes
    @client = client
    @product_id_property = product_id_property
    @import_filepath = import_filepath
    @import_id = import_id ? import_id : generate_import_id
    Dirs.recursive_init_dir(import_filepath.split('/')[0..-2].join('/'))
  end

  def self.import_products(product_hashes, client, import_id, product_id_property, import_filepath)
    new(product_hashes, client, import_id, product_id_property, import_filepath).import_products
  end

  def import_products
    write_import_file
    run_import
  end

  def write_import_file
    File.open(import_filepath, 'w') do |file|
      file.write(json_import.serialize)
    end
  end

  def run_import
    Salsify::Utils::Import.start_import_with_new_file(
      client,
      import_id,
      import_filepath,
      wait_until_complete: true
    )
  end

  def import_filename
    @import_filename ||= import_filepath.split('/').last
  end

  def json_import
    @json_import ||= begin
      import = Amadeus::Import::JsonImport.new
      import.add_header(header)
      product_hashes.each do |product_hash|
        import.products[product_hash[product_id_property]] = product_hash
      end
      import
    end
  end

  def header
    @header ||= begin
      header = Amadeus::Import::Header.new
      header.scope = [{ products: 'dynamic' }]
      header.mode = :upsert
      header.version = "2"
      header
    end
  end

  def generate_import_id
    client.create_import(
      {
        import_format: {
          type: 'json_import_format'
        },
        import_source: {
          file: import_filename,
          type: 'upload_import_source',
          upload_path: client.get_upload_mount['form_data']['key']
        }
      }
    )['id']
  end

end
