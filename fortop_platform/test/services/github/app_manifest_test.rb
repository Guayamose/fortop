require "test_helper"
require "tmpdir"
require "dotenv"
require_relative "fake_http"

class Github::AppManifestTest < ActiveSupport::TestCase
  test "manifest requests repository permissions with local callbacks and disabled webhooks" do
    manifest = Github::AppManifest.new(env: { "APP_URL" => "http://localhost:3000" }).manifest
    assert_equal "http://localhost:3000/auth/github/callback", manifest[:callback_urls].first
    assert_equal "http://localhost:3000/github/installations/callback", manifest[:setup_url]
    assert_equal false, manifest[:hook_attributes][:active]
    assert_equal "", manifest[:hook_attributes][:url], "Inactive webhooks must not submit a localhost URL to GitHub"
    assert_empty manifest[:default_events]
    assert_equal false, manifest[:request_oauth_on_install]
    assert_equal({ contents: "write", issues: "write", pull_requests: "write", metadata: "read" }, manifest[:default_permissions])
  end

  test "manifest conversion stores all secrets atomically with owner only permissions and preserves AI settings" do
    key = OpenSSL::PKey::RSA.generate(2048).to_pem
    response = { "id" => 123, "slug" => "fortop-test", "client_id" => "Iv1.test", "client_secret" => "secret$literal",
      "pem" => key, "webhook_secret" => "hook" }
    env = {}
    http = GithubTestHttp.new(response)
    Dir.mktmpdir do |directory|
      path = File.join(directory, ".env")
      File.write(path, "FORTOP_TEST_EXISTING_SETTING=preserve\nGITHUB_CLIENT_ID=old\n")
      assert Github::AppManifest.new(env: env, http: http, env_path: path).register!(code: "a" * 40)
      parsed = Dotenv.parse(path, overwrite: true)
      assert_equal "preserve", parsed["FORTOP_TEST_EXISTING_SETTING"]
      assert_equal key, Base64.strict_decode64(parsed["GITHUB_APP_PRIVATE_KEY"])
      assert Github::App.new(env: parsed).jwt.present?
      assert_equal "secret$literal", parsed["GITHUB_CLIENT_SECRET"]
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal "123", env["GITHUB_APP_ID"]
      assert_equal key, env["GITHUB_APP_PRIVATE_KEY"]
      assert_empty Dir.glob(File.join(directory, ".env.fortop-*"))
    end
    assert_equal "/app-manifests/#{'a' * 40}/conversions", http.requests.first[:uri].path
  end

  test "does not persist incomplete conversion credentials" do
    http = GithubTestHttp.new({ "id" => 1 })
    Dir.mktmpdir do |directory|
      path = File.join(directory, ".env")
      assert_raises(Github::Error) { Github::AppManifest.new(env: {}, http: http, env_path: path).register!(code: "a" * 40) }
      refute File.exist?(path)
    end
  end

  test "persists required app credentials when webhook secret is absent nil or empty" do
    response = valid_conversion_response
    [ {}, { "webhook_secret" => nil }, { "webhook_secret" => "" } ].each do |optional_fields|
      env = {}
      http = GithubTestHttp.new(response.merge(optional_fields))
      Dir.mktmpdir do |directory|
        path = File.join(directory, ".env")
        assert Github::AppManifest.new(env: env, http: http, env_path: path).register!(code: "a" * 40)
        parsed = Dotenv.parse(path, overwrite: true)
        assert_equal "123", parsed["GITHUB_APP_ID"]
        assert Github::App.new(env: parsed).jwt.present?
        refute parsed.key?("GITHUB_WEBHOOK_SECRET")
        refute env.key?("GITHUB_WEBHOOK_SECRET")
        assert_equal 0o600, File.stat(path).mode & 0o777
      end
    end
  end

  test "rejects every missing required credential even when webhook secret is absent" do
    response = valid_conversion_response
    %w[id slug client_id client_secret pem].each do |required_field|
      http = GithubTestHttp.new(response.except(required_field))
      env = {}
      Dir.mktmpdir do |directory|
        path = File.join(directory, ".env")
        assert_raises(Github::Error) { Github::AppManifest.new(env: env, http: http, env_path: path).register!(code: "a" * 40) }
        refute File.exist?(path)
        assert_empty env
      end
    end
  end

  private

  def valid_conversion_response
    { "id" => 123, "slug" => "fortop-test", "client_id" => "Iv1.test", "client_secret" => "fake-client-secret",
      "pem" => OpenSSL::PKey::RSA.generate(2048).to_pem }
  end
end
