class Api::GroupingsController < ApplicationController
  protect_from_forgery prepend: true

  STAMP = '$GROUPINGS$'.freeze

  # POST /api/new_groupings
  def new_groupings
    Delayed::Job.enqueue(NewGroupingsJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in GroupingsController#new_groupings: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/removed_groupings
  def removed_groupings
    Delayed::Job.enqueue(RemovedGroupingsJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in GroupingsController#removed_groupings: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/modified_groupings
  def modified_groupings
    Delayed::Job.enqueue(ModifiedGroupingsJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in GroupingsController#modified_groupings: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end
