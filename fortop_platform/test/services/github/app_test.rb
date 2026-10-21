require "test_helper"
require_relative "fake_http"

class Github::AppTest < ActiveSupport::TestCase
  setup do
    @key = OpenSSL::PKey::RSA.generate(2048)
    @env = { "GITHUB_APP_ID" => "12", "GITHUB_APP_SLUG" => "fortop-test", "GITHUB_CLIENT_ID" => "Iv1.fake",
      "GITHUB_CLIENT_SECRET" => "secret", "GITHUB_APP_PRIVATE_KEY" => @key.to_pem }
  end

  test "signs short lived App JWT with the private key" do
    now = Time.utc(2026, 10, 20, 10)
    jwt = Github::App.new(env: @env).jwt(now: now)
    header, payload, signature = jwt.split(".")
    decoded = JSON.parse(Base64.urlsafe_decode64(payload))
    assert_equal "12", decoded["iss"]
    assert_equal now.to_i - 60, decoded["iat"]
    assert_equal now.to_i + 540, decoded["exp"]
    assert @key.public_key.verify(OpenSSL::Digest::SHA256.new, Base64.urlsafe_decode64(signature), "#{header}.#{payload}")
  end

  test "installation token request is limited to a single authorized repository" do
    http = GithubTestHttp.new({ "token" => "ghs_installation", "permissions" => {
      "contents" => "write", "issues" => "write", "pull_requests" => "write"
    }, "repository_selection" => "selected", "repositories" => [ { "id" => 19 } ] })
    result = Github::App.new(env: @env, http: http).installation_token(8, repository_id: 19)
    assert_equal "ghs_installation", result
    assert_equal "/app/installations/8/access_tokens", http.requests.first[:uri].path
    assert_equal [ 19 ], http.requests.first[:body][:repository_ids]
    assert_equal "write", http.requests.first[:body][:permissions][:contents]
    refute_includes http.requests.first[:uri].to_s, "secret"
  end

  test "rejects a token whose actual grant lacks required write permissions" do
    response = installation_grant
    response["permissions"]["contents"] = "read"
    http = GithubTestHttp.new(response)
    error = assert_raises(Github::Error) { Github::App.new(env: @env, http: http).installation_token(8, repository_id: 19) }
    assert_equal 403, error.status
  end

  test "rejects broader and mismatched installation token repository scopes" do
    [ [], [ { "id" => 20 } ], [ { "id" => 19 }, { "id" => 20 } ] ].each do |repositories|
      response = installation_grant.merge("repositories" => repositories)
      http = GithubTestHttp.new(response)
      assert_raises(Github::Error) { Github::App.new(env: @env, http: http).installation_token(8, repository_id: 19) }
    end
    http = GithubTestHttp.new(installation_grant.merge("repository_selection" => "all"))
    assert_raises(Github::Error) { Github::App.new(env: @env, http: http).installation_token(8, repository_id: 19) }
  end

  test "installation URL has optional state and validated slug" do
    url = Github::App.new(env: @env).installation_url(state: "state")
    assert_equal "https://github.com/apps/fortop-test/installations/new?state=state", url
    assert_raises(Github::Error) { Github::App.new(env: @env.merge("GITHUB_APP_SLUG" => "../attacker")).installation_url }
  end

  private

  def installation_grant
    { "token" => "ghs_installation", "permissions" => { "contents" => "write", "issues" => "write", "pull_requests" => "write" },
      "repository_selection" => "selected", "repositories" => [ { "id" => 19 } ] }
  end
end
