class SalsifySessionController < ApplicationController
  # Provides methods to Authenticate with Salsify
  WHITELIST_DOMAIN = %w(belk.com salsify.com)

  def create
    session[:salsify] = request.env['omniauth.auth']
    if email_whitelisted?
      redirect_to root_path(success: true, message: "Logged in successfully!")
    else
      redirect_to root_path(success: false, message: "Email is not eligible for login!")
    end
  end

  def current_user_token
    session[:salsify]['credentials']['token']
  end

  def user
    user_email.split(/[+@]/).first
  end

  def user_email_domain
    user_email.split('@').second
  end

  def email_whitelisted?
    WHITELIST_DOMAIN.include?(user_email_domain)
  end
end
