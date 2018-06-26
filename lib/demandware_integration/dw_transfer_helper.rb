module Demandware

  class DwTransferHelper
    include Muffin::FtpClient

    STAMP = '$DW TRANSFER$'.freeze
    EXAVAULT_UPLOAD_PATH_DW_PROD = 'salsify_to_demandware/prod'.freeze
    EXAVAULT_UPLOAD_PATH_DW_QA = 'salsify_to_demandware/qa'.freeze
    EXAVAULT_UPLOAD_PATH_CFH_PROD = 'Belk/Prod/Catalog'.freeze
    EXAVAULT_UPLOAD_PATH_CFH_QA = 'Belk/Int/Catalog'.freeze
    BELK_UPLOAD_PATH = '/upload'.freeze

    attr_reader :dw_zip_paths, :cfh_tar_path, :xml_mode

    def initialize(dw_zip_paths, cfh_tar_path, xml_mode)
      @dw_zip_paths = dw_zip_paths
      @cfh_tar_path = cfh_tar_path
      @xml_mode = xml_mode
    end

    def self.send_dw_packages(dw_zip_paths:, cfh_tar_path:, xml_mode:)
      new(dw_zip_paths, cfh_tar_path, xml_mode).send_dw_packages
    end

    def send_dw_packages
      send_to_belk
      send_to_exavault
    end

    def send_to_belk
      t = Time.now
      puts "#{STAMP} Sending #{dw_zip_paths.length} files to Belk SFTP"
      dw_zip_paths.each do |zip_path|
        filename = zip_path.split('/').last
        puts "#{STAMP} Sending #{filename} to Belk SFTP"
        FTP::Wrapper.new(client: mode == :prod ? :belk : :belk_qa).upload(zip_path, File.join(BELK_UPLOAD_PATH, filename))
        puts "#{STAMP} Successful upload of #{filename} to Belk SFTP"
      end
      puts "#{STAMP} Done uploading #{dw_zip_paths.length} files to Belk SFTP, took #{((Time.now - t) / 60).round(1)} minutes"
    end

    def send_to_exavault
      t = Time.now
      puts "#{STAMP} Sending #{dw_zip_paths.length} DW files to Exavault"
      dw_zip_paths.each do |zip_path|
        next unless zip_path
        filename = zip_path.split('/').last
        puts "#{STAMP} Sending #{filename} to Exavault (DW)"
        upload_path = mode == :prod ? EXAVAULT_UPLOAD_PATH_DW_PROD : EXAVAULT_UPLOAD_PATH_DW_QA
        FTP::Wrapper.new.upload(zip_path, File.join(upload_path, filename))
        puts "#{STAMP} Successful upload of #{filename} to Exavault (DW)"
      end

      if xml_mode != XML_MODE_LIMITED
        cfh_filename = cfh_tar_path.split('/').last
        puts "#{STAMP} Sending #{cfh_filename} to Exavault (CFH)"
        upload_path = mode == :prod ? EXAVAULT_UPLOAD_PATH_CFH_PROD : EXAVAULT_UPLOAD_PATH_CFH_QA
        FTP::Wrapper.new.upload(cfh_tar_path, File.join(upload_path, cfh_filename))
        puts "#{STAMP} Successful upload of #{cfh_filename} to Exavault (CFH)"
      end

      puts "#{STAMP} Done uploading DW zips and CFH tar to Exavault, took #{((Time.now - t) / 60).round(1)} minutes"
    end

    def mode
      @mode ||= ENV.fetch('CARS_ENVIRONMENT') == 'production' ? :prod : :qa
    end

  end

end
