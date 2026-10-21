require "test_helper"

class Github::HttpTest < ActiveSupport::TestCase
  Response = Struct.new(:code)

  test "does not retry ambiguous write failures or reveal response details" do
    http = Github::Http.new
    calls = 0
    http.define_singleton_method(:perform) do |*_args, **_options|
      calls += 1
      raise Timeout::Error, "secret in underlying request"
    end
    error = assert_raises(Github::Error) { http.request(URI("https://api.github.com/repos/a/b/issues"), method: :post, token: "private") }
    assert_equal 1, calls
    assert error.retryable?
    refute_includes error.message, "secret"
    refute_includes error.message, "private"
  end

  test "write responses classify temporary server failures separately from permissions" do
    http = Github::Http.new
    [ 401, 403, 422, 502, 503, 504 ].each do |status|
      http.define_singleton_method(:perform) { |*, **| [ Response.new(status.to_s), "private response" ] }
      error = assert_raises(Github::Error) { http.request(URI("https://api.github.com/repos/a/b/issues"), method: :post) }
      assert_equal status, error.status
      assert_equal [ 502, 503, 504 ].include?(status), error.retryable?
      refute_includes error.message, "private response"
    end
  end

  test "network diagnostics record only exception type and request metadata" do
    http = Github::Http.new
    http.define_singleton_method(:perform) { |*, **| raise Net::OpenTimeout, "private token in underlying request" }
    output = StringIO.new
    Rails.stub(:logger, ActiveSupport::Logger.new(output)) do
      assert_raises(Github::Error) { http.request(URI("https://api.github.com/repos/a/b/issues"), method: :post, token: "private") }
    end
    assert_includes output.string, "cause=Net::OpenTimeout"
    assert_includes output.string, "method=post"
    refute_includes output.string, "private"
  end

  test "bounded retry only for transient GET failures" do
    http = Github::Http.new
    calls = 0
    http.define_singleton_method(:perform) do |*_args, **_options|
      calls += 1
      [ Response.new(calls < 3 ? "503" : "200"), '{"id":1}' ]
    end
    http.define_singleton_method(:sleep) { |_duration| }
    assert_equal({ "id" => 1 }, http.request(URI("https://api.github.com/user")))
    assert_equal 3, calls
  end

  test "never follows redirects or allows arbitrary hosts" do
    http = Github::Http.new
    assert_raises(Github::Error) { http.request(URI("https://example.com/steal"), token: "secret") }
    assert_raises(Github::Error) { http.request(URI("https://api.github.com:8443/user")) }
    http.define_singleton_method(:perform) { |*_args, **_options| [ Response.new("302"), "" ] }
    error = assert_raises(Github::Error) { http.request(URI("https://api.github.com/user")) }
    assert_equal 302, error.status
  end
end
