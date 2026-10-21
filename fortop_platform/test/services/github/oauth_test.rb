require "test_helper"
require_relative "fake_http"

class Github::OAuthTest < ActiveSupport::TestCase
  setup do
    @env = { "GITHUB_CLIENT_ID" => "Iv1.example", "GITHUB_CLIENT_SECRET" => "secret", "APP_URL" => "http://localhost:3000" }
  end

  test "GitHub App authorization has PKCE and state without OAuth App repository scopes" do
    url = Github::OAuth.new(env: @env).authorize_url(state: "state", code_verifier: "verifier")
    uri = URI(url)
    query = URI.decode_www_form(uri.query).to_h
    assert_equal "github.com", uri.host
    assert_equal "state", query["state"]
    assert_equal "S256", query["code_challenge_method"]
    assert_equal Base64.urlsafe_encode64(Digest::SHA256.digest("verifier"), padding: false), query["code_challenge"]
    assert_equal "http://localhost:3000/auth/github/callback", query["redirect_uri"]
    assert_nil query["scope"]
  end

  test "exchange preserves rotating credentials and expiry without exposing them in authorization URL" do
    http = GithubTestHttp.new({ "access_token" => "ghu_fake", "refresh_token" => "ghr_fake", "expires_in" => 28800 })
    travel_to Time.utc(2026, 10, 20, 10) do
      credentials = Github::OAuth.new(env: @env, http: http).exchange(code: "code", code_verifier: "verifier")
      assert_equal "ghu_fake", credentials[:token]
      assert_equal "ghr_fake", credentials[:refresh_token]
      assert_equal 8.hours.from_now, credentials[:expires_at]
    end
    assert_equal "application/json", http.requests.first[:accept]
    assert_equal "verifier", http.requests.first[:body][:code_verifier]
    assert_nil http.requests.first[:uri].query
  end

  test "refresh uses GitHub refresh grant and rejects error responses" do
    http = GithubTestHttp.new({ "error" => "bad_refresh_token", "error_description" => "sensitive details" })
    error = assert_raises(Github::Error) { Github::OAuth.new(env: @env, http: http).refresh(refresh_token: "expired") }
    assert_equal "refresh_token", http.requests.first[:body][:grant_type]
    refute_includes error.message, "sensitive"
  end

  test "rejects callback origins that contain embedded credentials or insecure remote addresses" do
    [ "https://attacker:password@example.com", "http://example.com", "https://example.com/path", "https://example.com?next=other" ].each do |url|
      env = @env.merge("APP_URL" => url)
      assert_raises(Github::Error) { Github::OAuth.new(env: env).authorize_url(state: "s", code_verifier: "v") }
    end
  end
end
