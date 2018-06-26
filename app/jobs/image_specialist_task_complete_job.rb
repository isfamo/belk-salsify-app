class ImageSpecialistTaskCompleteJob < Struct.new(:products)

  STAMP = '$IMAGE$'.freeze

  def perform
    require_rel '../../lib/image_management/**/*.rb'
    puts "#{STAMP} ImageSpecialistTaskCompleteJob queued for #{products.length} products..."
    ImageManagement::ImageTask.handle_task_complete(products)
    puts "#{STAMP} ImageSpecialistTaskCompleteJob done!"
  rescue Exception => e
    puts "#{STAMP} ERROR in ImageSpecialistTaskCompleteJob: #{e.message}"
    puts "#{STAMP} #{e.backtrace.join("\n")}" if e.backtrace
  end

end
