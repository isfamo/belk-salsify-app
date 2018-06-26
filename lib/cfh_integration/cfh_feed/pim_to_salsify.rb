require './lib/cfh_integration/demandware'

class PIMToSalsify
  include Muffin::SalsifyClient
  include FTPClients

  REMOTE_PATH = 'Belk/Prod/Catalog'.freeze
  ARCHIVE_PATH = 'Belk/Prod/Catalog Archive'.freeze
  REMOTE_UPLOAD_PATH = '/upload'.freeze
  EXTRACT_DIR = '/tmp'.freeze
  PRODUCT_CONTENT_FILE_LOCATION = 'lib/cfh_integration/output/product_import.json'.freeze
  GROUPING_FILE_LOCATION = 'lib/cfh_integration/output/grouping_import.json'.freeze
  PARENT_ID_FILE_LOCATION = 'lib/cfh_integration/output/parent_id_import.json'.freeze
  COLOR_CODE_FILE_LOCATION = 'lib/cfh_integration/output/color_code_export.csv'.freeze
  ORG_ID = 3562

  attr_reader :pim_xml_parser, :date, :file, :local_file_paths

  def initialize(date, file = nil)
    @date = date
    @local_file_paths = []
    @file = file
  end

  def self.import_pim_feed(date, file = nil)
    new(date, file).import_pim_feed
  end

  def import_pim_feed
    begin
      populate_local_files
      filenames = prepare_files.flatten
      @pim_xml_parser = Demandware::XMLParser.new(filenames)
      import_product_content
      import_groupings
      import_parent_ids
      archive_files_on_ftp
      remove_files_on_ftp
    ensure
      local_file_paths.each do |local_file_path|
        FileUtils.rm(local_file_path) if File.exist?(local_file_path)
      end
    end
  end

  private

  def archive_files_on_ftp
    local_file_paths.each { |file| salsify_ftp.upload(file, File.join(ARCHIVE_PATH, File.basename(file))) }
  end

  def remove_files_on_ftp
    remote_file_paths.each { |file| salsify_ftp.remove(file) }
  end

  def remote_file_paths
    @remote_file_paths ||= begin
      file_paths = file ? [ salsify_ftp.find_file(REMOTE_PATH, file) ] :
        salsify_ftp.find_files_with_retry(REMOTE_PATH, "Catalog_Delta_#{date.strftime('%Y%m%d')}")
      file_paths ? file_paths : raise("unable to locate file with #{date}")
    end
  end

  def populate_local_files
    remote_file_paths.each do |remote_file_path|
      local_file_paths << File.join(EXTRACT_DIR, File.basename(remote_file_path)) if remote_file_path
    end
  end

  def prepare_files
    files = []
    remote_file_paths.each_with_index do |remote_file_path, index|
      puts "$CFH SYNC$ downloading file path #{remote_file_path} (remote) #{local_file_paths[index]} (local)..."
      salsify_ftp.download(remote_file_path, local_file_paths[index])
      files << self.class.extract_pim_export(local_file_paths[index])
    end
    files
  end

  def self.extract_pim_export(filename)
    tar_extract = Gem::Package::TarReader.new(Zlib::GzipReader.open(filename))
    tar_extract.rewind # The extract has to be rewinded after every iteration
    tar_extract.map do |entry|
      puts "$CFH SYNC$ Extracting #{entry.full_name}..."
      destination = File.join(EXTRACT_DIR, entry.full_name)
      File.open(destination, 'wb') do |destination_file|
        destination_file.print(entry.read)
      end
      destination
      # sort on the way out into the map, that way files are done in order
    end.sort
  ensure
    tar_extract.close if tar_extract
  end

  def color_code_remote_filename
    File.join(REMOTE_UPLOAD_PATH, "Catalog_Color_#{date.strftime('%Y%m%d')}.csv")
  end

  def import_product_content
    descriptor = File.open(PRODUCT_CONTENT_FILE_LOCATION, 'wb')
    pim_xml_parser.all_to_json(descriptor)
    descriptor.close
    puts '$CFH SYNC$ importing product content...'
    Salsify::Utils::Import.start_import_with_new_file(salsify_client(org_id: ORG_ID), 79978, PRODUCT_CONTENT_FILE_LOCATION, wait_until_complete: true)
  end

  def import_groupings
    descriptor = File.open(GROUPING_FILE_LOCATION, 'wb')
    pim_xml_parser.product_sets_to_json(descriptor)
    descriptor.close
    puts '$CFH SYNC$ importing groupings...'
    Salsify::Utils::Import.start_import_with_new_file(salsify_client(org_id: ORG_ID), 79979, GROUPING_FILE_LOCATION, wait_until_complete: true)
  end

  def import_parent_ids
    descriptor = File.open(PARENT_ID_FILE_LOCATION, 'wb')
    pim_xml_parser.variants_to_json(descriptor)
    descriptor.close
    puts '$CFH SYNC$ importing parent ids...'
    Salsify::Utils::Import.start_import_with_new_file(salsify_client(org_id: ORG_ID), 79980, PARENT_ID_FILE_LOCATION, wait_until_complete: true)
  end
end
