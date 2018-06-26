# Authenication helpers
module RequestBodyHandler
  extend ActiveSupport::Concern

  FAILURE_BODY = { status: 'failure', message: 'requires a JSON request body' }.freeze

  def request_body
    @request_body ||= begin
      Hashie::Mash.new(JSON.parse(request.body.read))
    rescue
      respond_with_failure
    end
  end

  def respond_with_failure
    render json: FAILURE_BODY.to_json, status: 422
  end

end
