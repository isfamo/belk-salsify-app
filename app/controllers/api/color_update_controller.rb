class Api::ColorUpdateController < ApplicationController
  protect_from_forgery prepend: true

  # POST /api/color_code_updated
  def color_code_updated
    Delayed::Job.enqueue(ColorCodeUpdateJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in ColorUpdateController#color_code_updated:\n#{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/color_code_updated_non_master
  def color_code_updated_non_master
    Delayed::Job.enqueue(ColorCodeUpdateNonMasterJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in ColorUpdateController#color_code_updated_non_master:\n#{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/color_mapping_file_updated
  def color_mapping_file_updated
    Delayed::Job.enqueue(ColorMappingFileUpdateJob.new(params))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in ColorUpdateController#color_mapping_file_updated:\n#{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/omni_color_updated
  def omni_color_updated
    Delayed::Job.enqueue(OmniColorUpdateJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in ColorUpdateController#omni_color_updated:\n#{e.message}\n#{e.backtrace.join("\n")}"
  end

end
