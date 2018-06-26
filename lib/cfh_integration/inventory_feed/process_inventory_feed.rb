require './lib/cfh_integration/demandware'

class ProcessInventoryFeed
  include FTPClients
  include UnzipFile
  include Muffin::SalsifyClient
  include JobStatusHelper

  REMOTE_PATH = 'Belk/Prod/Inventory'.freeze
  EXTRACT_DIR = 'tmp'.freeze
  REMOTE_UPLOAD_PATH = '/upload'.freeze
  SALSIFY_IMPORT_FILE_LOCATION = 'lib/cfh_integration/output/inventory_import.json'.freeze
  SALSIFY_IMPORT_ID = 117442
  ORG_ID = 3562

  attr_reader :extracted_file

  def initialize
    job_status.update(title: :inventory)
  end

  def self.run
    new.run
  end

  def run
    begin
      puts "downloading file path #{remote_filepath}..."
      salsify_ftp.download(remote_filepath, input_filepath)
      job_status.update(activity: 'Importing feed')
      unzip_file(tar: false)
      populate_missing_parents
      puts 'generating xml...'
      job_status.update(activity: 'Generating XML')
      generate_xml
      gzip_xml
      puts "uploading file to #{upload_remote_filepath}..."
      job_status.update(activity: 'Uploading XML')
      belk_ftp.upload(gz_tmp_file, upload_remote_filepath)
      gz_tmp_file.open
      salsify_ftp.upload(gz_tmp_file, upload_remote_filepath)
      salsify_ftp.remove(remote_filepath)
      send_notification_email if ENV.fetch('RAILS_ENV') != 'development'
      puts 'generating salsify import...'
      generate_salsify_import
      puts 'running salsify import...'
      run_salsify_import
    rescue => error
      job_status.error = error.message
      send_notification_email(error: error) if ENV.fetch('RAILS_ENV') != 'development'
      raise error
    ensure
      finalize_job_status
    end
  end

  def send_notification_email(error: nil)
    EmailNotifier.notify(mode: :inventory_feed, error: error)
  end

  def input_filepath
    @input_filepath ||= File.join(EXTRACT_DIR, File.basename(remote_filepath))
  end

  def remote_filepath
    @remote_filepath ||= begin
      remote_filepath = salsify_ftp.find_file(REMOTE_PATH, 'InventoryFeed_Full', "#{date.strftime('%Y%m%d')}")
      abort("unable to locate file with #{date}") unless remote_filepath
      job_status.update(activity: 'Importing file from FTP')
      remote_filepath
    end
  end

  def local_xml_filepath
    @local_xml_filepath ||= File.join(EXTRACT_DIR, "inventory-feed-#{date.strftime('%Y%m%d')}.xml")
  end

  def gz_tmp_file
    @gz_tmp_file ||= Tempfile.new('gz_tmp_file.xml.gz')
  end

  def upload_remote_filepath
    @upload_remote_filepath ||= File.join(REMOTE_UPLOAD_PATH, "Catalog_Inv_#{Time.now.strftime('%Y%m%d-%H%M')}.xml.gz")
  end

  def gzip_xml
    Zlib::GzipWriter.open(gz_tmp_file) { |gz| gz.write(File.read(local_xml_filepath)) }
  end

  def generate_xml
    xml = Demandware::XMLGenerator.new(local_xml_filepath, date)
    xml.serialize_inventory(parents)
  end

  def inventory_xml
    @inventory_xml ||= Demandware::XMLParser.new([extracted_file])
  end

  def populate_missing_parents
    puts "#{skus_missing_parents.count} skus missing..."
    FetchParentsFromSalsify.run(skus_missing_parents)
  end

  def skus_missing_parents
    @skus_missing_parents ||= (included_skus_ids - Sku.product_ids).uniq
  end

  def parents
    @parents ||= included_skus.map do |xml_sku|
      sku = Sku.find_by(product_id: xml_sku[:product_id])
      next unless sku
      sku.update_attribute(:inventory_reset_date, xml_sku[:inventory_reset_date])
      parent = sku.parent_product
      next unless parent
      next if parent.first_inventory_date
      parent.update_attribute(:first_inventory_date, date)
      parent
    end.compact
  end

  def included_skus
    @included_skus ||= inventory_xml.inventory_skus
  end

  def included_skus_ids
    inventory_xml.inventory_sku_ids
  end

  def date
    @date ||= Date.today
  end

  def generate_salsify_import
    GenerateSalsifyImport.run(included_skus, parents)
  end

  def run_salsify_import
    Salsify::Utils::Import.start_import_with_new_file(
      salsify_client(org_id: ORG_ID), SALSIFY_IMPORT_ID, SALSIFY_IMPORT_FILE_LOCATION
    )
  end

  class GenerateSalsifyImport < Struct.new(:skus, :parents)
    include Amadeus::Import

    def self.run(skus, parents)
      new(skus, parents).run
    end

    def run
      add_header
      add_sku_products
      add_parent_products
      serialize
    end

    def json_import
      @json_import ||= JsonImport.new
    end

    def add_header
      header = Header.new
      header.scope = [
        { products: [ 'product_id', 'inventoryAvailDate', 'inventory', 'inventoryResetDate' ] }
      ]
      json_import.add_header(header)
    end

    def add_sku_products
      skus.each do |sku|
        json_import.products[sku[:product_id]] = {
          'product_id' => sku[:product_id],
          'inventory' => sku[:inventory],
          'inventoryResetDate' => sku[:inventory_reset_date]
        }
      end
    end

    def add_parent_products
      parents.each do |parent|
        json_import.products[parent.product_id] = {
          'product_id' => parent.product_id,
          'inventoryAvailDate' => parent.first_inventory_date,
        }
      end
    end

    def serialize
      File.open(ProcessInventoryFeed::SALSIFY_IMPORT_FILE_LOCATION, 'w') { |f| f.write(json_import.serialize) }
    end

  end
end
