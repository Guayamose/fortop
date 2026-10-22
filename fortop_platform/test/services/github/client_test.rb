require "test_helper"
require_relative "fake_http"

class Github::ClientTest < ActiveSupport::TestCase
  SHA = "a" * 40

  test "access grants resolve only personal accounts and reject malformed usernames before HTTP" do
    http = GithubTestHttp.new({ "id" => 123, "login" => "Some-User", "type" => "User" }, { "id" => 456, "login" => "organization", "type" => "Organization" })
    client = Github::Client.new("token", http: http)
    assert_equal 123, client.account("some-user").fetch("id")
    assert_equal "/users/some-user", http.requests.first[:uri].path
    assert_raises(Github::Error) { client.account("organization") }
    [ "", "../user", "someone?admin=true", "https://github.com/user", "-user" ].each do |login|
      assert_raises(Github::Error) { client.account(login) }
    end
    assert_equal 2, http.requests.size
  end

  test "installation write capability only matches its explicitly authorized repository" do
    client = Github::Client.new(token: "installation", authorized_repository_id: 19)
    assert client.write_authorized_for?(19)
    assert client.write_authorized_for?("19")
    refute client.write_authorized_for?(20)
    refute client.write_authorized_for?(nil)
    refute Github::Client.new(token: "visitor").write_authorized_for?(19)
  end

  test "reads only installation-authorized repositories with visitor token" do
    http = GithubTestHttp.new({ "installations" => [ { "id" => 9 } ] }, { "repositories" => [ { "id" => 3 } ] })
    client = Github::Client.new(token: "visitor", http: http)
    assert_equal [ { "id" => 9 } ], client.installations
    assert_equal [ { "id" => 3 } ], client.installation_repositories(9)
    assert_equal "/user/installations/9/repositories", http.requests.last[:uri].path
    assert_equal "visitor", http.requests.last[:token]
  end

  test "encodes nested file paths and decodes text from the pinned reference" do
    http = GithubTestHttp.new({ "type" => "file", "size" => 4, "encoding" => "base64", "content" => Base64.strict_encode64("hola") })
    result = Github::Client.new("token", http: http).file("owner/repo", "public/my file.html", ref: SHA)
    assert_equal "hola", result
    assert_includes http.requests.first[:uri].path, "my%20file.html"
    assert_equal SHA, URI.decode_www_form(http.requests.first[:uri].query).to_h["ref"]
  end

  test "rejects traversal and invalid repository names before requesting data" do
    http = GithubTestHttp.new
    client = Github::Client.new("token", http: http)
    assert_raises(Github::Error) { client.repository("owner/repo/../../user") }
    [ "../.env", "public/../.env", "/etc/passwd", "public//index.html", ".git/config", "back\\slash" ].each do |path|
      assert_raises(Github::Error) { client.file("owner/repo", path, ref: SHA) }
    end
    assert_empty http.requests
  end

  test "rejects incomplete non-recursive subtrees instead of using partial inventory" do
    http = GithubTestHttp.new({ "tree" => [], "truncated" => true }, { "tree" => [], "truncated" => true })
    assert_raises(Github::Error) { Github::Client.new("token", http: http).tree("owner/repo", SHA) }
  end

  test "recovers truncated recursive inventories through complete nested subtrees" do
    http = GithubTestHttp.new(
      { "tree" => [ { "path" => "incomplete.html" } ], "truncated" => true },
      { "tree" => [ { "path" => "README.md", "type" => "blob" }, { "path" => "app", "type" => "tree", "sha" => "b" * 40 } ] },
      { "tree" => [ { "path" => "page.html", "type" => "blob" }, { "path" => "views", "type" => "tree", "sha" => "c" * 40 } ] },
      { "tree" => [ { "path" => "layout.erb", "type" => "blob" } ] }
    )
    entries = Github::Client.new("token", http: http).tree("owner/repo", SHA)
    assert_equal %w[README.md app app/page.html app/views app/views/layout.erb], entries.map { |entry| entry["path"] }
    assert_equal 4, http.requests.size
    assert http.requests.drop(1).all? { |request| request[:uri].query.nil? }
  end

  test "shared subtrees are fetched once but included under each complete path" do
    http = GithubTestHttp.new(
      { "tree" => [], "truncated" => true },
      { "tree" => [ { "path" => "one", "type" => "tree", "sha" => "b" * 40 }, { "path" => "two", "type" => "tree", "sha" => "b" * 40 } ] },
      { "tree" => [ { "path" => "page.html", "type" => "blob" } ] }
    )
    entries = Github::Client.new("token", http: http).tree("owner/repo", SHA)
    assert_includes entries.map { |entry| entry["path"] }, "one/page.html"
    assert_includes entries.map { |entry| entry["path"] }, "two/page.html"
    assert_equal 3, http.requests.size
  end

  test "issue recovery can continue beyond ten pages" do
    marker = "<!-- fortop:large-repository -->"
    pages = Array.new(10) { Array.new(100) { { "number" => 1, "body" => "Other issue" } } }
    http = GithubTestHttp.new(*pages, [ { "number" => 1001, "body" => marker } ])
    assert_equal 1001, Github::Client.new("token", http: http).find_issue("owner/repo", marker: marker)["number"]
    assert_equal "11", URI.decode_www_form(http.requests.last[:uri].query).to_h["page"]
  end

  test "renews expired installation access once during a long scan" do
    http = GithubTestHttp.new(Github::Error.new("Expired", status: 401), { "id" => 19 })
    renewals = 0
    client = Github::Client.new(token: "expired-installation", http: http, authorized_repository_id: 19,
      token_refresher: -> { renewals += 1; "renewed-installation" })
    assert_equal 19, client.repository("owner/repo")["id"]
    assert_equal 1, renewals
    assert_equal %w[expired-installation renewed-installation], http.requests.map { |request| request[:token] }
    assert client.write_authorized_for?(19)
  end

  test "does not loop credential renewals or replay uncertain writes" do
    renewals = 0
    refresh = -> { renewals += 1; "new-installation" }
    http = GithubTestHttp.new(Github::Error.new("Expired", status: 401), Github::Error.new("Still expired", status: 401))
    client = Github::Client.new(token: "expired", http: http, token_refresher: refresh)
    assert_raises(Github::Error) { client.repository("owner/repo") }
    assert_equal 1, renewals

    [ Github::Error.new("Forbidden", status: 403), Github::Error.new("Response lost", retryable: true) ].each do |error|
      http = GithubTestHttp.new(error)
      client = Github::Client.new(token: "current", http: http, token_refresher: -> { flunk "Must not refresh or replay this write" })
      assert_raises(Github::Error) { client.create_issue("owner/repo", title: "Finding", body: "Evidence") }
      assert_equal 1, http.requests.size
    end
  end

  test "commits against base tree preserving executable modes and fast forwards only the managed branch" do
    http = GithubTestHttp.new(
      { "default_branch" => "main" }, { "object" => { "sha" => SHA } }, { "tree" => { "sha" => "b" * 40 } },
      { "tree" => [ { "path" => "script", "mode" => "100755", "type" => "blob" } ], "truncated" => false },
      { "sha" => "c" * 40 }, { "sha" => "d" * 40 }, { "ref" => "refs/heads/fortop/scan-1" }
    )
    commit = Github::Client.new("installation", http: http).commit_files("owner/repo", branch: "fortop/scan-1",
      base_sha: SHA, files: { "script" => "updated", "public/robots.txt" => "User-agent: *" }, message: "Improve crawlability")
    assert_equal "d" * 40, commit["sha"]
    create_tree = http.requests.find { |entry| entry[:method] == :post && entry[:uri].path.end_with?("/trees") }
    assert_equal "b" * 40, create_tree[:body][:base_tree]
    assert_equal "100755", create_tree[:body][:tree].first[:mode]
    assert_equal "100644", create_tree[:body][:tree].last[:mode]
    assert_equal({ sha: "d" * 40, force: false }, http.requests.last[:body])
    assert_includes http.requests.last[:uri].path, "fortop%2Fscan-1"
  end

  test "cannot publish to default branch even if default happens to use managed prefix" do
    http = GithubTestHttp.new({ "default_branch" => "fortop/main" })
    client = Github::Client.new("token", http: http)
    assert_raises(Github::Error) do
      client.commit_files("owner/repo", branch: "fortop/main", base_sha: SHA, files: { "robots.txt" => "content" }, message: "change")
    end
    assert http.requests.none? { |entry| entry[:method] == :post || entry[:method] == :patch }
    assert_raises(Github::Error) { client.create_branch("owner/repo", name: "main", sha: SHA) }
  end

  test "rejects commits after managed branch changed" do
    http = GithubTestHttp.new({ "default_branch" => "main" }, { "object" => { "sha" => "b" * 40 } })
    error = assert_raises(Github::Error) do
      Github::Client.new("token", http: http).commit_files("owner/repo", branch: "fortop/scan-1", base_sha: SHA,
        files: { "robots.txt" => "text" }, message: "change")
    end
    assert_equal 409, error.status
    assert http.requests.all? { |entry| entry[:method] == :get }
  end

  test "recovers issue and pull request by stable identifiers" do
    marker = "<!-- fortop:repo:1:finding:abc -->"
    http = GithubTestHttp.new([ { "number" => 2, "body" => marker, "pull_request" => {} }, { "number" => 3, "body" => marker } ],
      [ { "number" => 4, "head" => { "ref" => "fortop/scan-1" } } ])
    client = Github::Client.new("token", http: http)
    assert_equal 3, client.find_issue("owner/repo", marker: marker)["number"]
    assert_equal 4, client.find_pull_request("owner/repo", head: "fortop/scan-1")["number"]
  end
end
