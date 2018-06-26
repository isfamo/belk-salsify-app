class StartSampleReqJob < Struct.new(:products)

  STAMP = '$IMAGE$'.freeze

  def perform
    require_rel '../../lib/image_management/**/*.rb'
    puts "#{STAMP} StartSampleReqJob queued for #{products.length} products..."
    ImageManagement::SampleReq.start_sample_req(products)
    puts "#{STAMP} StartSampleReqJob done!"
  rescue Exception => e
    puts "#{STAMP} ERROR in StartSampleReqJob: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end
