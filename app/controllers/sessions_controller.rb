class SessionsController < Devise::SessionsController
  skip_before_action :verify_authenticity_token, if: :json_request?
  respond_to :html, :json

  protected

  def json_request?
    request.format.json?
  end
end
