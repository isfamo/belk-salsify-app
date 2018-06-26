class Api::ImageController < ApplicationController
  protect_from_forgery prepend: true

  STAMP = '$IMAGE$'.freeze

  # POST /api/img_properties_updated
  def img_properties_updated
    Delayed::Job.enqueue(ImageUpdateJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in ImageController#img_properties_updated: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/image_specialist_task_complete
  def image_specialist_task_complete
    Delayed::Job.enqueue(ImageSpecialistTaskCompleteJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in ImageController#image_specialist_task_complete: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/image_specialist_task_reopened
  def image_specialist_task_reopened
    Delayed::Job.enqueue(ImageSpecialistTaskReopenedJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in ImageController#image_specialist_task_reopened: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/rejection_notes_updated
  def rejection_notes_updated
    Delayed::Job.enqueue(ImagesRejectedJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in ImageController#rejection_notes_updated: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/start_sample_req
  def start_sample_req
    Delayed::Job.enqueue(StartSampleReqJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in ImageController#start_sample_req: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/pip_workflow_completed
  def pip_workflow_completed
    Delayed::Job.enqueue(PipWorkflowCompletedJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in ImageController#pip_workflow_completed: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end
