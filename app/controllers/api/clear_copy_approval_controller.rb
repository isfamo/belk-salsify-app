require 'json'

class Api::ClearCopyApprovalController < ApplicationController
  protect_from_forgery prepend: true

  # NOTE: Before this was used, we used salsify webhook url https://salsify-webhooks.herokuapp.com/incoming/4a8a1c785f0a5a956ec1

  # POST /api/clear_copy_approval
  def clear_copy_approval
    Delayed::Job.enqueue(ClearCopyApprovalJob.new(params['alert']['name'], params['products']))
    render status: 200, json: ''
  rescue Exception => e
    puts "$COPY$ ERROR: Error in ClearCopyApprovalController#clear_copy_approval: #{e.message}\n#{e.backtrace.join("\n")}"
  end

end
