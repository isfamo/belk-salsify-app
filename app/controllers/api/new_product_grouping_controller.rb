class Api::NewProductGroupingController < ApplicationController
  skip_before_action :verify_authenticity_token

  # POST /api/new_product_grouping
  def generate_ids
    params['alert'].each do |k,v|
      puts "#{k}: #{v}"
    end
    Delayed::Job.enqueue(NewProductGroupingJob.new(params['products']))
  rescue Exception => e
    puts "ERROR: Error in NewProductGroupingController#generate_ids:\n#{e.message}\n#{e.backtrace.join("\n")}"
  ensure
    render status: 200, json: ''
  end

  # POST /api/product_split_join
  def recalculate_after_split_join
    Delayed::Job.enqueue(SplitJoinRecalculateJob.new(params['_json']))
  rescue Exception => e
    puts "ERROR: Error in NewProductGroupingController#recalculate_after_split_join:\n#{e.message}\n#{e.backtrace.join("\n")}"
  ensure
    render status: 200, json: ''
  end

end
