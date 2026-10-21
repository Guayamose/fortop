require "test_helper"

class Github::InstallationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    oauth = Object.new
    oauth.define_singleton_method(:authorize_url) { |**_args| "https://github.com/login/oauth/authorize" }
    oauth.define_singleton_method(:exchange) { |**_args| { token: "ghu_installer", refresh_token: nil, expires_at: nil } }
    identity = Object.new
    identity.define_singleton_method(:user) { { "id" => 100_001, "login" => "installer" } }
    Github::OAuth.stub(:new, oauth) do
      Github::Client.stub(:new, identity) do
        post session_path
        state = session[:github_oauth]["state"]
        get callback_session_path, params: { state: state, code: "valid-code" }
      end
    end
  end

  test "installation redirect carries a session bound state" do
    Github::App.stub(:installation_url, ->(state:) { "https://github.com/apps/fortop-test/installations/new?state=#{state}" }) do
      post github_installation_path
    end
    assert_response :see_other
    state = URI.decode_www_form(URI(response.location).query).to_h.fetch("state")
    assert_equal 64, state.bytesize
    assert_equal state, session[:github_installation]["state"]
  end

  test "rejects a spoofed installation id even without a previous handshake" do
    client = Minitest::Mock.new
    client.expect :installations, [ { "id" => 8 } ], [], page: 1
    Github::Access.stub(:user_client, client) do
      get github_installation_callback_path, params: { installation_id: 999, setup_action: "install" }
    end
    assert_redirected_to new_repository_path
    assert_match "no está autorizada", flash[:alert]
    client.verify
  end

  test "legitimate installation callback still rechecks user authorization" do
    client = Minitest::Mock.new
    client.expect :installations, [ { "id" => 8 } ], [], page: 1
    Github::Access.stub(:user_client, client) do
      get github_installation_callback_path, params: { installation_id: 8, setup_action: "install" }
    end
    assert_redirected_to new_repository_path(installation_id: 8)
    client.verify
  end

  test "rejects mismatched state before querying installation permissions" do
    Github::App.stub(:installation_url, "https://github.com/apps/fortop-test/installations/new") do
      post github_installation_path
    end
    Github::Access.stub(:user_client, ->(_user) { flunk "unexpected access check" }) do
      get github_installation_callback_path, params: { installation_id: 8, state: "f" * 64 }
    end
    assert_redirected_to new_repository_path
    assert_match "caducado", flash[:alert]
  end
end
