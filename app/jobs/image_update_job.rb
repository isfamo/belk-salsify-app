class ImageUpdateJob < Struct.new(:products)

  STAMP = '$IMAGE$'.freeze
  SLEEP_TIME = 10.freeze

  def perform
    require_rel '../../lib/image_management/**/*.rb'
    puts "#{STAMP} ImageUpdateJob queued for #{products.length} products..."
    ImageManagement::ImageMetadata.process_metadata(products)

    # puts "#{STAMP} Sleeping #{SLEEP_TIME} seconds after processing metadata and before sending images via FTP"
    # sleep SLEEP_TIME
    #
    # ImageManagement::ImageTransfer.send_images(products)
    puts "#{STAMP} ImageUpdateJob done!"
  rescue Exception => e
    puts "#{STAMP} ERROR in ImageUpdateJob: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end
