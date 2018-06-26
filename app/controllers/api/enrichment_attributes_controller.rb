class Api::EnrichmentAttributesController < ApplicationController
  skip_before_filter :verify_authenticity_token

  def refresh_attributes
    puts '$ENRICHMENT ATTRIBUTES$ queuing attribute refresh job...'
    Delayed::Job.enqueue(Enrichment::TargetSchemaRefreshJob.new(user_email))
    Delayed::Job.enqueue(Enrichment::SetLookupAttributesJob.new)
    render status: 200, json: {}
  end

  def set_initial_lookup_attributes
    puts '$ENRICHMENT ATTRIBUTES$ queuing initial lookup attributes job...'
    Delayed::Job.enqueue(Enrichment::SetLookupAttributesJob.new(webhook_products))
  end

  def webhook_products
    Amadeus::Export::WebhookExport.new(params.to_hash).merged_products.map(&:to_h)
  end

end
