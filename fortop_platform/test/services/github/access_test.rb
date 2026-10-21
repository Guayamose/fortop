require "test_helper"
require_relative "fake_http"

class Github::AccessTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(github_id: 999, login: "visitor", github_token: "ghu_test", github_refresh_token: "ghr_test")
    @canonical = { "id" => 5, "full_name" => "owner/site", "archived" => false, "disabled" => false, "permissions" => { "push" => true } }
  end

  test "requires current user access to installation and repository before fetching canonical data" do
    client = Minitest::Mock.new
    client.expect :installations, [ { "id" => 2 } ], [], page: 1
    client.expect :installation_repositories, [ @canonical ], [ 2 ], page: 1
    client.expect :repository, @canonical, [ "owner/site" ]
    Github::Access.stub(:user_client, client) do
      assert_equal @canonical, Github::Access.repository_for(@user, installation_id: 2, full_name: "owner/site")
    end
    client.verify
  end

  test "rejects a repository missing from the user's installation repository intersection" do
    client = Minitest::Mock.new
    client.expect :installations, [ { "id" => 2 } ], [], page: 1
    client.expect :installation_repositories, [], [ 2 ], page: 1
    Github::Access.stub(:user_client, client) do
      error = assert_raises(Github::Error) { Github::Access.repository_for(@user, installation_id: 2, full_name: "owner/hidden") }
      assert_equal 403, error.status
    end
    client.verify
  end

  test "cannot borrow another user's installation" do
    client = Minitest::Mock.new
    client.expect :installations, [ { "id" => 2 } ], [], page: 1
    Github::Access.stub(:user_client, client) do
      error = assert_raises(Github::Error) { Github::Access.repository_for(@user, installation_id: 9999, full_name: "owner/site") }
      assert_equal 403, error.status
    end
    client.verify
  end

  test "renews expiring user credentials and persists rotated refresh token" do
    @user.update!(github_token_expires_at: 1.minute.from_now)
    oauth = Minitest::Mock.new
    oauth.expect :refresh, { token: "ghu_new", refresh_token: "ghr_new", expires_at: 8.hours.from_now }, [], refresh_token: "ghr_test"
    client = Object.new
    tokens = []
    Github::OAuth.stub(:new, oauth) do
      Github::Client.stub(:new, ->(**arguments) { tokens << arguments.fetch(:token); client }) do
        assert_equal client, Github::Access.user_client(@user)
        assert_equal client, Github::Access.user_client(@user)
      end
    end
    assert_equal [ "ghu_new", "ghu_new" ], tokens
    assert_equal "ghr_new", @user.reload.github_refresh_token
    oauth.verify
  end

  test "only gives a repository scoped capability after visitor authorization and verified app grant" do
    repository = Struct.new(:user, :installation_id, :full_name, :github_id).new(@user, 2, "owner/site", 5)
    app = Minitest::Mock.new
    app.expect :installation_token, "ghs_scoped", [ 2 ], repository_id: 5
    Github::Access.stub(:repository_for, @canonical) do
      Github::App.stub(:new, app) do
        client = Github::Access.client_for(repository)
        assert client.write_authorized_for?(5)
        refute client.write_authorized_for?(6)
      end
    end
    app.verify
  end

  test "does not mint an installation token after repository identity changed" do
    repository = Struct.new(:user, :installation_id, :full_name, :github_id).new(@user, 2, "owner/site", 999)
    Github::Access.stub(:repository_for, @canonical) do
      Github::App.stub(:new, -> { flunk "must not mint a token for mismatched repository" }) do
        error = assert_raises(Github::Error) { Github::Access.client_for(repository) }
        assert_equal 403, error.status
      end
    end
  end

  test "rechecks visitor permission before renewing an expired installation token" do
    repository = Struct.new(:user, :installation_id, :full_name, :github_id).new(@user, 2, "owner/site", 5)
    app = Minitest::Mock.new
    app.expect :installation_token, "ghs_scoped", [ 2 ], repository_id: 5
    http = GithubTestHttp.new(Github::Error.new("Expired", status: 401))
    checks = 0
    authorize = lambda do |*_, **_options|
      checks += 1
      raise Github::Error.new("Access revoked", status: 403) if checks > 1
      @canonical
    end
    Github::Access.stub(:repository_for, authorize) do
      Github::App.stub(:new, app) do
        Github::Http.stub(:new, http) do
          client = Github::Access.client_for(repository)
          error = assert_raises(Github::Error) { client.repository("owner/site") }
          assert_equal 403, error.status
        end
      end
    end
    assert_equal 2, checks
    assert_equal 1, http.requests.size
    app.verify
  end
end
