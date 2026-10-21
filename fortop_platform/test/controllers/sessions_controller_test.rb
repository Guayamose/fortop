require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "anonymous users are redirected to GitHub sign in" do
    get repositories_path
    assert_redirected_to new_session_path
  end

  test "GitHub authorization validates PKCE callback, encrypts credentials and signs out" do
    with_fake_github do
      post session_path
      assert_response :see_other
      assert_match %r{\Ahttps://github.com/login/oauth/authorize}, response.location
      get callback_session_path, params: { code: "valid-code", state: @state }
      assert_redirected_to repositories_path
      user = User.find_by!(github_id: 555)
      assert_equal user.id, session[:user_id]
      assert_equal "ghu_test", user.github_token
      assert_equal "ghr_test", user.github_refresh_token
      stored = User.connection.select_value("SELECT github_token FROM users WHERE id = #{user.id.to_i}")
      refute_equal "ghu_test", stored
      refute_includes stored, "ghu_test"
      delete logout_path
      assert_redirected_to new_session_path
      assert_nil session[:user_id]
    end
  end

  test "callback rejects mismatched state and consumes the handshake" do
    with_fake_github do
      post session_path
      assert_no_difference("User.count") do
        get callback_session_path, params: { code: "valid-code", state: "f" * 64 }
        assert_redirected_to new_session_path
        get callback_session_path, params: { code: "valid-code", state: @state }
        assert_redirected_to new_session_path
      end
      assert_nil session[:user_id]
    end
  end

  test "callback rejects expired state" do
    with_fake_github do
      post session_path
      travel 11.minutes do
        assert_no_difference("User.count") do
          get callback_session_path, params: { code: "valid-code", state: @state }
        end
      end
      assert_redirected_to new_session_path
      assert_nil session[:user_id]
    end
  end

  test "authorization cancellation does not sign in or expose provider error details" do
    with_fake_github do
      post session_path
      get callback_session_path, params: { error: "access_denied", error_description: "private detail", state: @state }
      assert_redirected_to new_session_path
      refute_includes flash[:alert], "private detail"
      assert_nil session[:user_id]
    end
  end

  private

  def with_fake_github
    oauth = Object.new
    test = self
    oauth.define_singleton_method(:authorize_url) do |state:, code_verifier:|
      test.instance_variable_set(:@state, state)
      test.instance_variable_set(:@verifier, code_verifier)
      "https://github.com/login/oauth/authorize?state=#{state}"
    end
    oauth.define_singleton_method(:exchange) do |code:, code_verifier:|
      test.assert_equal "valid-code", code
      test.assert_equal test.instance_variable_get(:@verifier), code_verifier
      { token: "ghu_test", refresh_token: "ghr_test", expires_at: 8.hours.from_now }
    end
    client = Object.new
    client.define_singleton_method(:user) { { "id" => 555, "login" => "test-visitor", "name" => "Visitor" } }
    Github::OAuth.stub(:new, oauth) do
      Github::Client.stub(:new, client) { yield }
    end
  end
end
