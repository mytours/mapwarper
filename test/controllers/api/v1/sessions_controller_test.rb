require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = FactoryBot.create(:user, login: 'tokenuser', email: 'tokenuser@example.com')
  end

  def auth_headers(token: @user.authentication_token, user: @user)
    {
      'Authorization' => "Bearer #{token}",
      'X-User-Id' => user.id.to_s,
      'Accept' => 'application/json'
    }
  end

  test 'create rotates authentication token' do
    original_token = @user.authentication_token

    post '/api/v1/auth/sign_in.json',
      params: { user: { email: @user.email, password: 'password' } },
      headers: { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
      as: :json

    assert_response :success
    body = JSON.parse(response.body)

    @user.reload
    refute_equal original_token, @user.authentication_token
    assert_equal @user.authentication_token, body['meta']['auth_token']
  end

  test 'validate token succeeds with header authentication' do
    get '/api/v1/auth/validate_token.json', headers: auth_headers, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @user.id.to_s, body['data']['id']
  end

  test 'validate token fails for invalid token' do
    get '/api/v1/auth/validate_token.json',
        headers: auth_headers(token: 'invalid-token'),
        as: :json

    assert_response :unprocessable_entity
  end

  test 'destroy rotates authentication token and invalidates previous token' do
    old_token = @user.authentication_token

    delete '/api/v1/auth/sign_out.json', headers: auth_headers, as: :json

    assert_response :success
    @user.reload
    refute_equal old_token, @user.authentication_token

    get '/api/v1/auth/validate_token.json',
        headers: auth_headers(token: old_token),
        as: :json

    assert_response :unprocessable_entity
  end
end
