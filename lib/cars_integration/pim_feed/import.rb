module PIMFeed
  class Import
    include Muffin::SalsifyClient
    include ImportIdHandler
    include FTPClients
    include UnzipFile

    FILE_LOCATION = 'lib/cars_integration/output/pim_import.json'.freeze
    PARENT_FILE_LOCATION = 'lib/cars_integration/output/parent_pim_import.json'.freeze
    EXTRACT_DIR = 'tmp'.freeze

    attr_reader :extracted_files, :ftp_filename, :date, :mode, :file_location, :parent_file_location,
      :remote_path, :full_feed_path, :archive_report_ftp_dir, :import_id, :parent_import_id

    def initialize(ftp_filename = nil, mode = :delta)
      @date = ActiveSupport::TimeZone.new('America/New_York').today
      @ftp_filename = ftp_filename
      @mode = mode.try(:to_sym)
      @file_location = mode == :delta ? FILE_LOCATION : File.join(EXTRACT_DIR, ftp_filename.gsub('.tar.gz', '.json'))
      @parent_file_location = mode == :delta ? PARENT_FILE_LOCATION : File.join(EXTRACT_DIR, ftp_filename.gsub('.tar.gz', '.json'))
      if ENV['CARS_ENVIRONMENT'] == 'production'
        @remote_path = 'CARS/PROD/PIM_Delta'
        @full_feed_path = 'CARS/PROD/PIM_Full'
        @archive_report_ftp_dir = 'CARS/PROD/PIM_Delta_Archive'
        @import_id = 182373
        @parent_import_id = 229625
      else
        @remote_path = 'CARS/INT/PIM_Delta'
        @full_feed_path = 'CARS/STG/PIM_Full'
        @archive_report_ftp_dir = 'CARS/INT_ARCHIVE'
        @import_id = 145458
        @parent_import_id = 216261
      end
    end

    def self.run(ftp_filename: nil, mode: :delta)
      new(ftp_filename, mode).run
    end

    def run
      Stopwatch.time('PIM feed import') do
        return unless remote_filepath
        download_file_from_ftp
        unzip_file(multiple_files: true)
        populate_parent_import_file
        serialize_parent_import_file
        populate_import_file
        serialize_import_file
        if mode == :full
          upload_import_file_to_salsify
        else
          run_salsify_import
          archive_file_on_ftp
        end
      end
    end

    def upload_import_file_to_salsify
      puts "$PIM IMPORT$ uploading full feed file #{file_location}..."
      salsify_ftp.upload(file_location, File.join('cars_full_feed', File.basename(file_location)))
    end

    def download_file_from_ftp
      puts "$PIM IMPORT$ downloading file path #{remote_filepath}..."
      salsify_ftp.download(remote_filepath, input_filepath)
    end

    def archive_file_on_ftp
      begin
        salsify_ftp.upload(input_filepath, archive_remote_path)
      rescue
      end
      salsify_ftp.remove(remote_filepath)
    end

    def archive_remote_path
      File.join(archive_report_ftp_dir, File.basename(remote_filepath))
    end

    def run_salsify_import
      run_style_import
      run_sku_import
    end

    def run_style_import
      calculated_import_id = calculate_import_id(client, "STYLES - #{input_filename}", parent_import_id)
      response = Salsify::Utils::Import.start_import_with_new_file(
        client, calculated_import_id, parent_file_location, wait_until_complete: false
      )
      puts "$PIM IMPORT$ uploading parent import with import_id: #{calculated_import_id} and run_id: #{response.id}"
    end

    def run_sku_import
      calculated_import_id = calculate_import_id(client, "SKUS - #{input_filename}", import_id)
      response = Salsify::Utils::Import.start_import_with_new_file(
        client, calculated_import_id, file_location, wait_until_complete: false
      )
      puts "$PIM IMPORT$ uploading product import with import_id: #{calculated_import_id} and run_id: #{response.id}"
    end

    # XXX will need to refactor with listener if they plan on uploading multiple times per day
    def remote_filepath
      @remote_filepath ||= begin
        remote_filepath = nil
        if mode == :delta
          remote_filepath = ftp_filename ? salsify_ftp.find_file(remote_path, ftp_filename.to_s) :
            salsify_ftp.find_pim_file(remote_path)
        elsif mode == :full
          remote_filepath = ftp_filename ? salsify_ftp.find_file(full_feed_path, ftp_filename.to_s) :
            salsify_ftp.find_file(full_feed_path, "Product_CARCreate_Delta_#{date.strftime('%Y%m%d')}")
        end
        remote_filepath
      end
    end

    def input_filename
      @input_filename ||= File.basename(remote_filepath)
    end

    def input_filepath
      @input_filepath ||= File.join(EXTRACT_DIR, input_filename)
    end

    def xml
      @xml ||= XMLParser.new(extracted_files, attribute_map, mode)
    end

    def populate_parent_import_file
      xml.products do |product|
        next unless product.parent_id
        salsify_parent_import_file.add_product(product.parent_id)
      end
    end

    def serialize_parent_import_file
      salsify_parent_import_file.serialize
    end

    def populate_import_file
      xml.products { |product| salsify_import_file.add_product(product.serialize) }
    end

    def serialize_import_file
      salsify_import_file.serialize
    end

    def salsify_import_file
      @salsify_import_file ||= PIMFeed::SalsifyImportFile.new(attribute_map, file_location, mode)
    end

    def salsify_parent_import_file
      @salsify_parent_import_file ||= PIMFeed::SalsifyParentImportFile.new(parent_file_location)
    end

    def attribute_map
      @attribute_map ||= PIMFeed::Attributes.new
    end

    def client
      @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
    end

  end
end
