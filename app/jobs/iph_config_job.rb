class IphConfigJob < Struct.new(:ftp_path)

  STAMP = '$IPH_CONFIG_UPDATED$'.freeze

  def perform
    begin
      require_rel '../../lib/iph_mapping/**/*.rb'
      IphMapping::IphConfig.retrieve(ftp_path)
    rescue Exception => e
      puts "#{STAMP} ERROR in IphConfigJob: #{e.message}\n#{e.backtrace.join("\n")}"
    end
  end

end
