class VendorImageSampleJob < Struct.new(:time)

  def perform
    puts 'Vendor image sample job queued...'
    begin
      require_rel '../../lib/rrd_integration/**/*.rb'
      RRDonnelley::RRDConnector.send_sample_requests_to_rrd
      RRDonnelley::RRDConnector.check_rrd_for_processed_samples
    rescue Exception => e
      puts "$$ ERROR while running sample feed job: #{e.message}"
    end
  end

end
