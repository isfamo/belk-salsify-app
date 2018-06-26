class ImagesRejectedJob < Struct.new(:products)

  STAMP = '$IMAGE$'.freeze

  def perform
    require_rel '../../lib/image_management/**/*.rb'
    puts "#{STAMP} ImagesRejectedJob queued for #{products.length} products..."
    ImageManagement::ImageRejection.rejection_notes_updated(products)
    puts "#{STAMP} ImagesRejectedJob done!"
  rescue Exception => e
    puts "#{STAMP} ERROR in ImagesRejectedJob: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end
