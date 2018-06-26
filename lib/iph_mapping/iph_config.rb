module IphMapping
  class IphConfig

    def initialize
      Dirs.recursive_init_dir(IPH_CONFIG_FILE_LOCATION)
    end

    def self.load_config
      new.load_config
    end

    def self.retrieve(ftp_path)
      new.retrieve(ftp_path)
    end

    def load_config
      download_config_file unless have_local_file?
      parsed_config_file
    end

    def retrieve(ftp_path)
      puts "#{STAMP} Retrieving new version of gxs_iph_config.json file from FTP at path: #{ftp_path}"
      with_ftp { |ftp| ftp.getbinaryfile(ftp_path, iph_config_file_path) }
      puts "#{STAMP} Done retrieving file from #{ftp_path}"
    end

    def have_local_file?
      File.exists?(iph_config_file_path)
    end

    def download_config_file
      puts "#{STAMP} Don't have local copy of IPH config, downloading..."
      with_ftp { |ftp| ftp.getbinaryfile(ftp_filepath, iph_config_file_path) }
    end

    def ftp_filepath
      @ftp_filepath ||= ENV.fetch('CARS_ENVIRONMENT') == 'production' ? IPH_CONFIG_FILE_FTP_PATH_PROD : IPH_CONFIG_FILE_FTP_PATH_QA
    end

    def with_ftp
      Net::FTP.open(
        ENV.fetch('SALSIFY_FTP_HOST'),
        ENV.fetch('SALSIFY_FTP_ADMIN_USERNAME'),
        ENV.fetch('SALSIFY_FTP_ADMIN_PASSWORD')
      ) do |ftp|
        ftp.passive = true
        yield ftp
      end
    end

    def parsed_config_file
      Oj.load(File.read(iph_config_file_path))
    end

    def iph_config_file_path
      @iph_config_file_path ||= File.join(IPH_CONFIG_FILE_LOCATION, IPH_CONFIG_FILE_NAME)
    end

  end
end
