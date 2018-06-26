class ImageSpecialistTaskReopenedJob < Struct.new(:products)

  STAMP = '$IMAGE$'.freeze

  def perform
    require_rel '../../lib/image_management/**/*.rb'
    puts "#{STAMP} ImageSpecialistTaskReopenedJob queued for #{products.length} products..."
    ImageManagement::ImageRejection.image_spec_task_reopened(products)
    puts "#{STAMP} ImageSpecialistTaskReopenedJob done!"
  rescue Exception => e
    puts "#{STAMP} ERROR in ImageSpecialistTaskReopenedJob: #{e.message}"
    puts "#{STAMP} #{e.backtrace.join("\n")}" if e.backtrace
  end

end
