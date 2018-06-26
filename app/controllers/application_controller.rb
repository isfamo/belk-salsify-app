class ApplicationController < ActionController::Base
  include ActionController::HttpAuthentication::Basic
  include ActionController::HttpAuthentication::Token::ControllerMethods
  include Muffin::SalsifyClient

  before_bugsnag_notify :add_diagnostics_to_bugsnag
  protect_from_forgery with: :exception

  def index
    render :file => 'public/root.html'
  end

  def login
    if session[:salsify]
      redirect_to root_path(success: true, message: 'Already logged in!')
    else
      salsify_session
    end
  end

  def logout
    session[:salsify] = nil
    redirect_to root_path(success: true, message: 'Logged out successfully!')
  end

  def user_email
    session[:salsify]['info']['email']
  end

  protected

  def http_basic_authentication
    credentials = [ENV['HTTP_AUTH_USER'], ENV['HTTP_AUTH_PASSWORD']].compact
    return true if credentials.empty?

    authentication_request(self, 'API', nil) unless
      has_basic_credentials?(request) &&
      user_name_and_password(request) == credentials
  end

  def salsify_session
    session[:original_request] = request.original_fullpath

    redirect_to '/auth/salsify' unless session[:salsify]
  end

  # TODO - only allow BELK users to access this app?
  def salsify_api_session
    unless session[:salsify]
      render json: { error: 'Unauthorized' }, status: 401
    end
  end

  def add_diagnostics_to_bugsnag(notification)
    notification.context = ENV['CARS_ENVIRONMENT'] == 'production' ? 'Belk Prod' : 'Belk QA'
  end

end
