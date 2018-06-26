class HexFeedExportJob < Struct.new(:time)

  def perform
    puts '$HEX$ Hex feed export job queued...'
    begin
      require_rel '../../lib/rrd_integration/**/*.rb'
      RRDonnelley::RRDConnector.send_belk_hex_feed
    rescue Exception => e
      puts "$HEX$ ERROR while sending Belk hex feed: #{e.message}\n#{e.backtrace.join("\n")}"
    end
  end

end
