class VendorImageUploadJob < Struct.new(:time)

  def perform
    puts 'Vendor image upload job queued...'
    begin
      require_rel '../../lib/rrd_integration/**/*.rb'
      RRDonnelley::RRDConnector.send_asset_feed_to_rrd
    rescue Exception => e
      puts "$$ ERROR while sending vendor image upload feed: #{e.message}"
    end
  end

end
