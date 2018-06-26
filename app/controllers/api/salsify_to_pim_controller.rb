require 'json'

class Api::SalsifyToPimController < ApplicationController
  protect_from_forgery prepend: true

  NEWLINE = "\n".freeze

  # POST /api/send_to_pim
  def send_to_pim
    payload_alert_name = params['alert']['name']
    puts "send_to_pim Webhook alert: payload_alert_name: #{payload_alert_name}, product id: #{params['products'][0]['salsify:id']}"
    products = params['salsify_to_pim']['products']

    Delayed::Job.enqueue(SalsifyToPimJob.new(payload_alert_name, products))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in SalsifyToPimController#send_to_pim:\n Message: #{e.message}\n#{e.backtrace.join(NEWLINE)}"
  end

  def send_to_pim_nope
    render status: 200, json: 'Nothing to see here.'
  rescue Exception => e
    puts "ERROR: Error in SalsifyToPimController#send_to_pim_nope:\n Message: #{e.message}\n#{e.backtrace.join(NEWLINE)}"
  end

  # POST /api/set_default_sku
  def set_default_sku
    payload_alert_name = params['alert']['name']
    puts "set_default_sku Webhook alert: payload_alert_name: #{payload_alert_name}, product id: #{params['products'][0]['salsify:id']}"

    Delayed::Job.enqueue(SetDefaultSkuJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR: Error in SalsifyToPimController#set_default_sku:\n Message: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end
