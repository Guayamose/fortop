require "test_helper"

class Scans::WorkspaceTest < ActiveSupport::TestCase
  setup do
    @files = files = { "index.html" => "<html><head><title>Fortop</title></head><body>Fortop</body></html>\n", "data.json" => '{"name":"Fortop"}', "danger.rb" => 'File.write("/tmp/fortop-should-never-run", "oops")' }
    github = Object.new
    github.define_singleton_method(:file) { |_repo, path, ref:| files.fetch(path) }
    tree = files.keys.map { |path| { "path" => path, "type" => "blob", "mode" => "100644", "size" => files[path].bytesize } }
    tree += [ { "path" => ".env", "type" => "blob", "mode" => "100644" }, { "path" => "symlink.html", "type" => "blob", "mode" => "120000" }, { "path" => "config/secrets.yml", "type" => "blob", "mode" => "100644" } ]
    @workspace = Scans::Workspace.new(github: github, full_name: "test/repo", sha: "a" * 40, tree: tree)
  end

  teardown { @workspace.close }

  test "excludes traversal, credentials, hidden paths and symlinks" do
    %w[../index.html /etc/passwd .env config/secrets.yml symlink.html .github/workflows/pwn.yml].each do |path|
      assert_raises(Agents::ToolError) { @workspace.read(path) }
    end
    assert_raises(Agents::ToolError) { @workspace.write("symlink.html", "overwrite link", finding_ids: [ 1 ]) }
    assert_equal %w[danger.rb data.json index.html], @workspace.list_files["files"]
  end

  test "requires inspection before modifying existing files and protects config" do
    assert_raises(Agents::ToolError) { @workspace.write("index.html", "changed", finding_ids: [ 1 ]) }
    assert_raises(Agents::ToolError) { @workspace.write("config/routes.rb", "Rails.application.routes.draw {}", finding_ids: [ 1 ]) }
    @workspace.read("index.html")
    @workspace.replace("index.html", "<title>Fortop</title>", "<title>Fortop · GEO</title>", finding_ids: [ 1 ])
    assert_equal [ 1 ], @workspace.finding_ids("index.html")
    assert_equal "index.html", @workspace.changed_files.first["path"]
  end

  test "preserves links for incremental edits to one file and clears them when the diff is discarded" do
    original = @workspace.read("index.html")
    @workspace.replace("index.html", "<head>", '<head><meta name="description" content="Fortop">', finding_ids: [ 1 ])
    @workspace.replace("index.html", "<html>", '<html lang="es">', finding_ids: [ 2 ])
    assert_equal [ 1, 2 ], @workspace.changed_files.first["finding_ids"]

    @workspace.discard("index.html")
    assert_empty @workspace.changes
    assert_empty @workspace.finding_ids("index.html")
    assert_equal original, @workspace.read("index.html")

    @workspace.replace("index.html", "<html>", '<html lang="es">', finding_ids: [ 3 ])
    assert_equal [ 3 ], @workspace.finding_ids("index.html")
    @workspace.write("index.html", original, finding_ids: [ 4 ])
    assert_empty @workspace.changes
    assert_empty @workspace.finding_ids("index.html")
  end

  test "validator rejects malformed structured data" do
    @workspace.read("data.json")
    @workspace.write("data.json", '{"name":', finding_ids: [ 1 ])
    results = Scans::Validator.new(@workspace).call
    assert results.any? { |check| check["name"] == "syntax:data.json" && !check["passed"] }
  end

  test "Ruby validation parses without executing repository code" do
    @workspace.read("danger.rb")
    @workspace.write("danger.rb", @workspace.original("danger.rb") + "\n# documentation\n", finding_ids: [ 1 ])
    assert Scans::Validator.new(@workspace).call.all? { |check| check["passed"] }
    assert_not File.exist?("/tmp/fortop-should-never-run")
  end

  test "parses Rails ERB block helpers without evaluating templates" do
    @workspace.write("app/views/layouts/application.html.erb", '<html><head><title>Fortop</title></head><body><%= link_to "/" do %>Fortop<% end %></body></html>', finding_ids: [ 1 ])
    assert Scans::Validator.new(@workspace).call.all? { |check| check["passed"] }
  end

  test "unsupported JSX corrections require manual intervention" do
    @workspace.write("app/page.tsx", "export default () => <title>Fortop</title>", finding_ids: [ 1 ])
    assert Scans::Validator.new(@workspace).call.any? { |check| !check["passed"] }
  end

  test "rejects new crawl blocking and ungrounded canonical domains" do
    @workspace.write("public/robots.txt", "User-agent: *\nDisallow: /\n", finding_ids: [ 1 ])
    @workspace.read("index.html")
    @workspace.replace("index.html", "<title>Fortop</title>", '<title>Fortop</title><link rel="canonical" href="https://fabricated-fortop-domain.com/">', finding_ids: [ 1 ])
    failures = Scans::Validator.new(@workspace).call.reject { |check| check["passed"] }
    assert failures.any? { |check| check["details"].include?("bloqueo completo") }
    assert failures.any? { |check| check["details"].include?("dominios que no aparecen") }
  end

  test "rejects invalid JSON LD inside otherwise valid HTML" do
    @workspace.read("index.html")
    @workspace.replace("index.html", "<title>Fortop</title>", '<title>Fortop</title><script type="application/ld+json">{"@context":"https://schema.org","@type":}</script>', finding_ids: [ 1 ])
    assert Scans::Validator.new(@workspace).call.any? { |check| check["name"].start_with?("json_ld:") && !check["passed"] }
  end

  test "excludes literal credential source before returning, caching or staging it" do
    synthetic_tokens = [ "AIza" + "a" * 35, "AQ." + "a" * 40, "ghu_" + "b" * 36, "github_pat_" + "c" * 50, "sk-proj-" + "d" * 40, "sk-ant-api03-" + "e" * 40, "ya29." + "f" * 40, "AQ" + "g" * 40, "-----BEGIN PRIVATE KEY-----" ]
    synthetic_tokens.each do |token|
      @files["danger.rb"] = "GEMINI_API_KEY = #{token.inspect}\n"
      workspace = fresh_workspace
      assert_empty workspace.search("GEMINI_API_KEY")["matches"]
      error = assert_raises(Agents::ToolError) { workspace.read_lines("danger.rb") }
      assert_not_includes error.message, token
      assert_nil workspace.original("danger.rb")
      assert_not_includes workspace.read_paths, "danger.rb"
      assert_not File.exist?(File.join(workspace.directory, "danger.rb"))
      assert_raises(Agents::ToolError) { workspace.write("danger.rb", "# remove credential", finding_ids: [ 1 ]) }
      assert_empty workspace.changes
      workspace.close
    end
  end

  test "keeps normal environment references and short documentation placeholders readable" do
    @files["danger.rb"] = 'GEMINI_API_KEY = ENV.fetch("GEMINI_API_KEY"); # AIza... placeholder'
    assert_equal @files["danger.rb"], @workspace.read("danger.rb")
  end

  private

  def fresh_workspace
    files = @files
    github = Object.new
    github.define_singleton_method(:file) { |_repo, path, ref:| files.fetch(path) }
    tree = files.keys.map { |path| { "path" => path, "type" => "blob", "mode" => "100644", "size" => files[path].bytesize } }
    Scans::Workspace.new(github: github, full_name: "test/repo", sha: "a" * 40, tree: tree)
  end
end
