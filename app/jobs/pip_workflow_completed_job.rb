class PipWorkflowCompletedJob < Struct.new(:products)

  STAMP = '$IMAGE$'.freeze

  def perform
    begin
      require_rel '../../lib/image_management/**/*.rb'
      puts "#{STAMP} PipWorkflowCompletedJob queued for #{products.length} products..."
      ImageManagement::PipWorkflow.pip_workflow_completed(products)
      puts "#{STAMP} PipWorkflowCompletedJob done!"
    rescue Exception => e
      puts "#{STAMP} ERROR in PipWorkflowCompletedJob: #{e.message}\n#{e.backtrace.join("\n")}"
    end
  end

end
