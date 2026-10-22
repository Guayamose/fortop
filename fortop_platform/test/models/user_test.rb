require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "only the verified GitHub ID grants administration and login access is closed by default" do
    owner = User.new(github_id: User::OWNER_GITHUB_ID, login: "a-new-handle")
    assert owner.admin?
    assert owner.login_allowed?
    visitor = User.new(github_id: 42, login: "Guayamose", email: "owner@example.com")
    refute visitor.admin?
    refute visitor.login_allowed?
    GithubAccessGrant.create!(github_id: 42, login: "previous-handle")
    assert visitor.login_allowed?
    refute visitor.admin?
    refute User.github_allowed?("63518682x")
    refute User.github_allowed?(nil)
  end

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
