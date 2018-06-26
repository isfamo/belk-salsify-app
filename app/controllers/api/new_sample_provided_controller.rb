require 'json'

# NOTE: this is not directly related to the Sample items that Louis' code does - this is a workflow helper based on that property

class Api::NewSampleProvidedController < ApplicationController
  protect_from_forgery prepend: true

  NEWLINE = "\n".freeze

  # POST /api/new_sample_flag
  def new_sample_flag
    payload_alert_name = params['alert']['name']
    puts "Webhook alert: payload_alert_name: #{payload_alert_name}, product id: #{params['products'][0]['salsify:id']}"
    products = params['products']

    Delayed::Job.enqueue(NewSampleProvidedJob.new(payload_alert_name, products))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in NewSampleProvidedController#new_sample_flag:\n Message: #{e.message}\n#{e.backtrace.join(NEWLINE)}"
  end

end
