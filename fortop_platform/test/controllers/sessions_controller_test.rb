require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "anonymous users are redirected to GitHub sign in" do
    get repositories_path
    assert_redirected_to new_session_path
  end

  test "GitHub authorization validates PKCE callback, encrypts credentials and signs out" do
    with_csrf_protection do
      with_fake_github do
        get new_session_path
        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_select 'meta[name="turbo-cache-control"][content="no-cache"]'
        assert_select 'form[action="/auth/github"][data-turbo="false"]'
        post session_path, params: { authenticity_token: form_token(session_path) }
        assert_response :see_other
        assert_match %r{\Ahttps://github.com/login/oauth/authorize}, response.location
        get callback_session_path, params: { code: "valid-code", state: @state }
        assert_redirected_to repositories_path
        assert_nil flash[:notice]
        user = User.find_by!(github_id: 555)
        assert_equal user.id, session[:user_id]
        assert_equal "ghu_test", user.github_token
        assert_equal "ghr_test", user.github_refresh_token
        stored = User.connection.select_value("SELECT github_token FROM users WHERE id = #{user.id.to_i}")
        refute_equal "ghu_test", stored
        refute_includes stored, "ghu_test"

        # Invalid tokens must still reject other session actions without signing out.
        delete logout_path
        assert_response :unprocessable_content
        assert_equal user.id, session[:user_id]

        get repositories_path
        delete logout_path, params: { authenticity_token: form_token(logout_path) }
        assert_redirected_to new_session_path
        assert_nil session[:user_id]
        follow_redirect!
        assert_response :success
        assert_select ".access-main > .flash", count: 0
        assert_select ".access-shell", count: 1
      end
    end
  end

  test "a login form from a lost session recovers with a fresh form before authorizing GitHub" do
    with_csrf_protection do
      with_fake_github do
        get new_session_path
        expired_token = form_token(session_path)
        reset!

        post session_path, params: { authenticity_token: expired_token }
        assert_response :see_other
        assert_redirected_to new_session_path
        assert_nil session[:github_oauth]
        assert_nil @state

        follow_redirect!
        assert_response :success
        assert_select ".access-main > .flash", count: 0
        assert_select ".access-login [role=alert]", text: /El formulario de acceso ha caducado/
        assert_equal "no-store", response.headers["Cache-Control"]

        post session_path, params: { authenticity_token: form_token(session_path) }
        assert_response :see_other
        assert_match %r{\Ahttps://github.com/login/oauth/authorize}, response.location
        assert_equal @state, session[:github_oauth]["state"]
      end
    end
  end

  test "missing and invalid login tokens never start GitHub authorization" do
    with_csrf_protection do
      with_fake_github do
        [ nil, "invalid-token" ].each do |token|
          post session_path, params: { authenticity_token: token }
          assert_response :see_other
          assert_redirected_to new_session_path
          assert_equal "no-store", response.headers["Cache-Control"]
          assert_nil session[:github_oauth]
          assert_nil session[:user_id]
          assert_nil @state
        end
      end
    end
  end

  test "a valid login token cannot authorize a request from another origin" do
    with_csrf_protection do
      with_fake_github do
        get new_session_path
        post session_path, params: { authenticity_token: form_token(session_path) },
          headers: { "Origin" => "https://untrusted.example" }
        assert_response :see_other
        assert_redirected_to new_session_path
        assert_nil session[:github_oauth]
        assert_nil @state
      end
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

  def form_token(action)
    css_select("form[action='#{action}'] input[name='authenticity_token']").first["value"]
  end

  def with_csrf_protection
    previous = ApplicationController.allow_forgery_protection
    ApplicationController.allow_forgery_protection = true
    yield
  ensure
    ApplicationController.allow_forgery_protection = previous
  end

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
    Github::App.stub(:configured?, true) do
      Github::OAuth.stub(:new, oauth) do
        Github::Client.stub(:new, client) { yield }
      end
    end
  end
end
