require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "GitHub tokens are encrypted in storage and identity survives a login rename" do
    user = User.from_github({ "id" => 42, "login" => "original" }, token: "test-private-token",
      refresh_token: "test-refresh-token", expires_at: 1.hour.from_now)
    raw = User.connection.select_one("SELECT github_token, github_refresh_token FROM users WHERE id = #{user.id}")
    refute_includes raw["github_token"], "test-private-token"
    refute_includes raw["github_refresh_token"], "test-refresh-token"
    assert_equal "test-private-token", user.reload.github_token
    renamed = User.from_github({ "id" => 42, "login" => "renamed" }, token: "new-test-token")
    assert_equal user.id, renamed.id
    assert_equal "renamed", renamed.login
    assert_equal "new-test-token", renamed.github_token
  end
end
