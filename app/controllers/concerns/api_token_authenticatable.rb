module ApiTokenAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_with_token
  end

  private

  def authenticate_with_token
    return if user_signed_in?

    token = authentication_token_from_request
    return if token.blank?

    identifier = token_identifier_from_request
    user = User.authenticate_by_token(identifier: identifier, authentication_token: token)
    return unless user

  sign_in(:user, user, store: false)
  @current_user = user
  end

  def authentication_token_from_request
    authorization = request.headers['Authorization']
    if authorization&.start_with?('Bearer ')
      bearer_token = authorization.split(' ', 2).last
      return bearer_token.strip if bearer_token.present?
    end

    request.headers['X-User-Token'] || params[:user_token] || params[:auth_token]
  end

  def token_identifier_from_request
    request.headers['X-User-Id'] || request.headers['X-User-Email'] || params[:user_id] || params[:user_email]
  end
end
