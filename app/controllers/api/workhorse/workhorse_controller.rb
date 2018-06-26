class Api::Workhorse::WorkhorseController < ApplicationController
  protect_from_forgery prepend: true
  before_action :validate_token

  # GET /api/workhorse/sample_requests
  def fetch_sample_requests
    if params['unsent']
      sample_reqs = RrdRequestedSample.where('sent_to_rrd != ?', true)
    else
      sample_reqs = RrdRequestedSample.all
    end
    render json: sample_reqs
  end

  # PUT /api/workhorse/sample_requests
  def update_sample_requests
    update_hashes = params['sample_requests'].map(&:to_hash)
    result_by_id = update_hashes.map do |update_hash|
      begin
        RrdRequestedSample.find(
          update_hash['id']
        ).update_attributes!(
          update_hash.reject { |k, v| k == 'id' }
        )
        [update_hash['id'], true]
      rescue Exception => e
        [update_hash['id'], { error: e.message }]
      end
    end.to_h
    render json: result_by_id
  end

  def validate_token
    if request.env['HTTP_API_TOKEN'].nil?
      return render status: 401, json: { error: 'Unauthorized! Must include "api_token" header.' }
    elsif request.env['HTTP_API_TOKEN'] != ENV.fetch('BELK_RAILS_API_TOKEN')
      return render status: 401, json: { error: 'Unauthorized! Provided api_token is invalid.' }
    end
  end

end
