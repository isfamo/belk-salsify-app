class VendorImageResponsePullJob < Struct.new(:time)

  def perform
    puts 'Vendor image response pull job queued...'
    begin
      require_rel '../../lib/rrd_integration/**/*.rb'
      RRDonnelley::RRDConnector.check_rrd_for_processed_assets
      RRDonnelley::RRDConnector.process_rrd_vendor_image_histories
    rescue Exception => e
      puts "$$ ERROR while retrieving vendor image responses: #{e.message}"
    end
  end

end
