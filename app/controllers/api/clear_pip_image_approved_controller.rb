require 'json'

class Api::ClearPipImageApprovedController < ApplicationController
  protect_from_forgery prepend: true

  NEWLINE = "\n".freeze

  # POST /api/clear_pip_image_approved
  def clear_pip_image_approved
    payload_alert_name = params['alert']['name']
    puts "Webhook alert: payload_alert_name: #{payload_alert_name}, product id: #{params['products'][0]['salsify:id']}"
    products = params['products']

    Delayed::Job.enqueue(ClearPipImageApprovedJob.new(payload_alert_name, products))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in ClearPipImageApprovedController#clear_pip_image_approved:\n Message: #{e.message}\n#{e.backtrace.join(NEWLINE)}"
  end

end
