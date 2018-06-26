require 'csv'
require 'new_relic/agent'
require './lib/cfh_integration/demandware'

class ProcessCMAFeed
  include FTPClients
  include UnzipFile
  include Muffin::SalsifyClient
  include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
  include JobStatusHelper
  include ErrorUtils

  HEADERS = [
    'SKUCODE', 'VENDORUPC', 'RECORDTYPE', 'EVENTID', 'STARTDATE', 'STARTTIME',
    'ENDDATE', 'ENDTIME', 'ADEVENT', 'ORIGPRICE', 'SALEPRICE', 'SALECLEARANCE'
  ].freeze
  LOG_LEVEL = ENV['LOG_LEVEL'] || 'info'
  REMOTE_UPLOAD_PATH = '/upload'.freeze
  EXTRACT_DIR = 'tmp'.freeze
  SALSIFY_IMPORT_ID = 126525.freeze
  SALSIFY_IMPORT_FILE_LOCATION = 'lib/cfh_integration/output/pricing.json'.freeze
  PROD = 'prod'.freeze
  TEST = 'test'.freeze
  ORG_ID = 3562

  attr_reader :date, :on_demand_filename, :extracted_file, :export_only_mode,
    :remote_path, :remote_ir_path, :mode

  def initialize(date, on_demand_filename = nil, export_only_mode = false)
    @date = date
    @on_demand_filename = on_demand_filename
    @export_only_mode = export_only_mode
    @mode = ENV['CARS_ENVIRONMENT'] == 'production' ? PROD : TEST
    job_status.update(title: :cma)
    NewRelic::Agent.manual_start(sync_startup: true)
    if mode == PROD
      @remote_path = 'Belk/Prod/Price'
      @remote_ir_path = 'Belk/Prod/Price_IR'
    else
      @remote_path = 'Belk/Qa/Price'
      @remote_ir_path = 'Belk/Qa/Price_IR'
    end
  end

  def self.run(date, on_demand_filename = nil)
    new(date, on_demand_filename).run
  end

  def self.import_pricing_feed(date)
    new(date).import_pricing_feed
  end

  def self.export_xml(date)
    new(date, nil, true).run
  end

  def self.export_xml_for_internal_use(date)
    new(date).export_xml
  end

  def run
    begin
      job_status.update(activity: 'Listening for file on FTP')
      import_pricing_feed unless export_only_mode
      export_xml
      upload_to_belk_ftp
      send_notification_email if ENV.fetch('RAILS_ENV') != 'development'
      remove_file_from_salsify_ftp
      run_salsify_import
    rescue => error
      job_status.error = format_error(error)
      send_notification_email(error: error) if ENV.fetch('RAILS_ENV') != 'development'
      raise error
    ensure
      finalize_job_status
    end
  end

  def upload_to_belk_ftp
    if mode == PROD
      belk_ftp.upload(gz_tmp_file, upload_remote_filepath)
    else
      belk_qa_ftp.upload(gz_tmp_file, upload_remote_filepath)
    end
  end

  def remove_file_from_salsify_ftp
    salsify_ftp.remove(remote_filepath)
  end

  def import_pricing_feed
    job_status.update(activity: 'Importing feed')
    start_time = Time.now
    puts "$CMA$ downloading file path #{remote_filepath}..."
    salsify_ftp.download(remote_filepath, input_filepath)
    puts "$CMA$ CMA import starting..."
    unzip_file
    add_headers_to_csv
    import_cma_data
    puts "$CMA$ CMA Events file was parsed in #{(Time.now - start_time) / 60} minutes"
  end

  def export_xml
    start_time = Time.now
    puts "$CMA$ CMA export start time: #{start_time}"
    job_status.update(activity: 'Generating XML')
    puts "$CMA$ filtering events with #{skus_with_recent_inventory.count} skus..."
    append_parent_ids
    generate_xml
    puts "$CMA$ CMA XML Demandware file was generated in #{(Time.now - start_time) / 60} minutes"
    gzip_xml
    puts '$CMA$ Exporting generating CMA XML to Belk FTP'
    job_status.update(activity: 'Uploading XML')
    puts '$CMA$ Exporting generating CMA XML to Salsify FTP'
    salsify_ftp.upload(gz_tmp_file, upload_remote_filepath)
    gz_tmp_file.open
    # rows_with_errors.map { |row| row.to_hash }
    # send_notification_email(error: rows_with_errors) if rows_with_errors.present? && ENV.fetch('RAILS_ENV') != 'development'
  end

  def send_notification_email(error: nil)
    EmailNotifier.notify(mode: :cma_feed, error: error)
  end

  def remote_filepath
    @remote_filepath ||= begin
      if on_demand_filename
        remote_filepath = salsify_ftp.find_file(remote_ir_path, on_demand_filename)
      else
        remote_filepath = salsify_ftp.find_file_with_retry(remote_path, "PRICEBOOK_SALSIFY_#{date.strftime('%Y%m%d')}")
      end
      abort("unable to locate file with #{date}") unless remote_filepath
      job_status.update(activity: 'Importing file from FTP')
      remote_filepath
    end
  end

  def input_filepath
    @input_filepath ||= File.join(EXTRACT_DIR, File.basename(remote_filepath))
  end

  def local_xml_filepath
    @local_xml_filepath ||= File.join(EXTRACT_DIR, "cma-feed-#{date.strftime('%Y%m%d')}.xml")
  end

  def gz_tmp_file
    @gz_tmp_file ||= Tempfile.new('gz_tmp_file.xml.gz')
  end

  def upload_remote_filepath
    @upload_remote_filepath ||= File.join(REMOTE_UPLOAD_PATH, "Catalog_Promo_#{Time.now.strftime('%Y%m%d-%H%M')}.xml.gz")
  end

  def gzip_xml
    Zlib::GzipWriter.open(gz_tmp_file) { |gz| gz.write(File.read(local_xml_filepath)) }
  end

  def generate_xml
    xml = Demandware::XMLGenerator.new(local_xml_filepath, date)
    xml.create_from_grouped_skus(grouped_skus, grouped_parents, regular_price_skus, skus_with_recent_inventory)
  end

  def grouped_skus
    cma_events.group_by(&:sku_code)
  end

  def grouped_parents
    bonus_event_codes.group_by(&:parent_id)
  end

  def bonus_event_codes
    @bonus_event_codes ||= CMAEvent.bonus_event_codes(date, cma_events)
  end

  def bonus_event_codes_without_parent_ids
    @bonus_event_codes_without_parent_ids ||= bonus_event_codes.where("parent_id is null")
  end

  def cma_events
    @cma_events ||= CMAEvent.active_today_and_in_future(date, skus_with_recent_inventory)
  end

  def regular_price_skus
    @regular_price_skus ||= CMAEvent.actively_priced_skus(date)
  end

  def append_parent_ids
    puts "$CMA$ appending parent_ids for #{bonus_event_codes_without_parent_ids.count} CMA events..."
    bonus_event_codes_without_parent_ids.in_batches do |skus|
      skus.each do |sku|
        next if sku.parent_id
        sku.update(parent_id: parent_lookup[sku.sku_code])
      end
    end
  end

  def skus_with_recent_inventory
    @skus_with_recent_inventory ||= Sku.with_recent_inventory(date)
  end

  def parent_lookup
    @parent_lookup ||= Sku.sku_to_parent_hash(bonus_event_codes_without_parent_ids.pluck(:sku_code).uniq)
  end

  def included_skus
    CustomCSV::Wrapper.new(csv_local_filepath).map(&:first).uniq - [ 'SKUCODE' ]
  end

  def import_cma_data
    CMAEvent.bulk_insert do |worker|
      CustomCSV::Wrapper.new(csv_local_filepath).foreach do |row|
        row = CMAEvent.new_from_cma_row(row)
        if !row.errors.present? && row.valid?
          worker.add(row.attributes)
          puts '$CMA$ Inserted 500 rows successfully' if worker.pending_count == 0
        else
          puts "$CMA$ SQLINSERT: ERROR: #{row.errors.full_messages.to_sentence}"
          rows_with_errors << row
        end
      end
    end
  end

  def add_headers_to_csv
    CSV.open(csv_local_filepath, 'wb') do |csv|
      csv << HEADERS
      CustomCSV::Wrapper.new(extracted_file).foreach_without_header { |row| csv << row }
    end
  end

  def csv_local_filepath
    @csv_local_filepath ||= File.join(EXTRACT_DIR, "formatted_#{File.basename(extracted_file, '.*')}.csv")
  end

  def rows_with_errors
    @rows_with_errors ||= []
  end

  def generate_salsify_import
    puts '$CMA$ generating salsify import...'
    GenerateSalsifyImport.run(regular_price_skus)
  end

  def run_salsify_import
    return unless mode == PROD
    generate_salsify_import
    puts '$CMA$ importing pricing into salsify...'
    Salsify::Utils::Import.start_import_with_new_file(
      salsify_client(org_id: ORG_ID), SALSIFY_IMPORT_ID, SALSIFY_IMPORT_FILE_LOCATION
    )
  end

  add_transaction_tracer :import_cma_data, :category => :task

  class GenerateSalsifyImport < Struct.new(:skus)
    include Amadeus::Import

    def self.run(skus)
      new(skus).run
    end

    def run
      add_header
      add_products
      serialize
    end

    def json_import
      @json_import ||= JsonImport.new
    end

    def add_header
      header = Header.new
      header.scope = [ { products: [ 'product_id', 'regularPrice' ] } ]
      json_import.add_header(header)
    end

    def add_products
      skus.each do |sku|
        json_import.products[sku.sku_code] = {
          'product_id' => sku.sku_code,
          'regularPrice' => sku.regular_price
        }
      end
    end

    def serialize
      File.open(ProcessCMAFeed::SALSIFY_IMPORT_FILE_LOCATION, 'w') { |f| f.write(json_import.serialize) }
    end

  end
end
