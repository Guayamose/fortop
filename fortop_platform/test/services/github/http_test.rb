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
    refute_includes error.message, "secret"
    refute_includes error.message, "private"
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
