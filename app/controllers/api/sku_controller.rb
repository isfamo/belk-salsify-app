class Api::SkuController < ApplicationController
  protect_from_forgery prepend: true

  STAMP = '$SKU$'.freeze

  # POST /api/skus_created
  def skus_created
    #Delayed::Job.enqueue(SkusCreatedJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in SkuController#skus_created: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/il_sku_converted
  def il_sku_converted
    #Delayed::Job.enqueue(IlSkuConvertedJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in SkuController#il_sku_converted: #{e.message}\n#{e.backtrace.join("\n")}"
  end

  # POST /api/color_master_deactivated
  def color_master_deactivated
    Delayed::Job.enqueue(ColorMasterDeactivatedJob.new(params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "#{STAMP} ERROR: Error in SkuController#color_master_deactivated: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end
