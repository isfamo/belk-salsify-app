class RrdImageMetadataJob < Struct.new(:products)

  def perform
    puts "$$ Image metadata generation job queued for #{products.length} products..."
    begin
      require_rel '../../lib/rrd_integration/**/*.rb'
      RRDonnelley::RRDConnector.process_image_metadata_for_products(products)
    rescue Exception => e
      puts "$$ ERROR in RrdImageMetadataJob: #{e.message}\n#{e.backtrace.join("\n")}"
    end
  end

end
