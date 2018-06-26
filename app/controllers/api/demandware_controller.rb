class Api::DemandwareController < ApplicationController
  skip_before_action :verify_authenticity_token

  # POST /api/demandware_publish
  def publish
    Delayed::Job.enqueue(DemandwareFeedJob.new(params['product_feed_export_url']))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in DemandwareController#publish:\n#{e.message}\n#{e.backtrace.join("\n")}"
  end

  # GET /api/test_demandware_publish
  def test_publish
    Delayed::Job.enqueue(DemandwareDirtyFamiliesJob.new(params['hours_back']))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in DemandwareController#test_publish:\n#{e.message}\n#{e.backtrace.join("\n")}"
  end

end
