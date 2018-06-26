class DepartmentConfigFileUpdateJob < Struct.new(:ftp_path)
  include Muffin::FtpClient

  BELK_EMAIL_GROUPS_FILEPATH_PROD = './lib/rrd_integration/cache/belk_email_groups_prod.json'.freeze
  BELK_EMAIL_GROUPS_FILEPATH_TEST = './lib/rrd_integration/cache/belk_email_groups_test.json'.freeze

  # When the department config file is updated on Exavault, pull it in
  def perform
    if ftp_path.nil?
      puts "$DEPT JSON UPDATE$ No ftp path passed in, aborting!"
      return
    end

    puts "$DEPT JSON UPDATE$ Department json config file update job queued with file #{ftp_path.split('/').last}"
    local_path = ENV.fetch('CARS_ENVIRONMENT') == 'production' ? BELK_EMAIL_GROUPS_FILEPATH_PROD : BELK_EMAIL_GROUPS_FILEPATH_TEST

    renamed_filename = local_path.gsub('.json', "_replaced_#{Time.now.strftime('%Y%m%d_%H%M%S_%Z')}.json")
    File.rename(local_path, renamed_filename)
    with_salsify_ftp { |ftp| ftp.getbinaryfile(ftp_path.split('/salsify/').last, local_path) }

    begin
      Oj.load(File.read(local_path))
    rescue Exception => e
      # Provided json file doesn't parse correctly
      puts "$DEPT JSON UPDATE$ Provided department json file encountered error when parsing json, going to keep using existing version, error is: #{e.message}"

      # Delete provided file and keep using old one
      File.delete(local_path)
      File.rename(renamed_filename, local_path)
    end

    puts "$DEPT JSON UPDATE$ Department json config file update job done!"
  end

  def with_salsify_ftp
    yield Net::FTP.open(
      ENV.fetch('SALSIFY_FTP_HOST'),
      ENV.fetch('SALSIFY_SFTP_USERNAME'),
      ENV.fetch('SALSIFY_SFTP_PASSWORD')
    )
  end

end
