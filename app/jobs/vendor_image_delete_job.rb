class VendorImageDeleteJob < Struct.new(:time)

  def perform
    puts 'Vendor image delete job queued...'
    begin
      require_rel '../../lib/rrd_integration/**/*.rb'
      RRDonnelley::RRDConnector.send_deleted_asset_feed_to_rrd
    rescue Exception => e
      puts "$$ ERROR while sending vendor image delete feed: #{e.message}"
    end
  end

end
