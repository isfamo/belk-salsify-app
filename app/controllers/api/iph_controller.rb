class Api::IphController < ApplicationController
  skip_before_action :verify_authenticity_token

  PROPERTY_NEEDS_IPH_MAPPING = 'Needs IPH Mapping'.freeze

  # TODO: Uncomment below code when we're ready to process GXS data and IPH changes

  # POST /api/iph_change
  def iph_change
    # Delayed::Job.enqueue(IphChangeJob.new(
    #   payload['organization']['id'],
    #   payload['alert']['name'],
    #   payload['products']
    # ))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR in IphController#iph_change: #{e.message}\n#{e.backtrace.join("\n")}"
    render status: 500, json: { error: e.message }
  end

  # POST /api/sku_iph_change
  def sku_iph_change
    # Only accept skus which need IPH mapping but parent doesn't
    # style_by_id = payload['parent_products'].map { |pr| [pr['salsify:id'], pr] }.to_h
    # skus = payload['products'].reject do |sku|
    #   style = style_by_id[sku['salsify:parent_id']]
    #   style && style[PROPERTY_NEEDS_IPH_MAPPING]
    # end
    #
    # if !skus.empty?
    #   Delayed::Job.enqueue(SkuIphChangeJob.new(
    #     payload['organization']['id'],
    #     payload['alert']['name'],
    #     style_by_id,
    #     skus
    #   ))
    # end
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR in IphController#sku_iph_change: #{e.message}\n#{e.backtrace.join("\n")}"
    render status: 500, json: { error: e.message }
  end

  # POST /api/gxs_iph_config_updated
  def gxs_iph_config_updated
    ftp_path = Oj.load(params.keys.first)['path']
    Delayed::Job.enqueue(IphConfigJob.new(ftp_path))
    render status: 200, json: ''
  rescue Exception => e
    puts "ERROR in IphController#gxs_iph_config_updated: #{e.message}\n#{e.backtrace.join("\n")}"
    render status: 500, json: { error: e.message }
  end

  def payload
    params.to_unsafe_h
  end

end
