class AdsFeedImportJob < Struct.new(:time)

  def perform
    puts 'ADS feed import job queued...'
    begin
      require_rel '../../lib/rrd_integration/**/*.rb'
      RRDonnelley::RRDConnector.pull_belk_ads_feed
    rescue Exception => e
      puts "$$ ERROR while pulling Belk ADS feed: #{e.message}"
    end
  end

end
