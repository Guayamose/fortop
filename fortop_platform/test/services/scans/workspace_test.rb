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

  test "reads beyond one hundred files and two megabytes and validates more than five corrections" do
    125.times { |index| @files["pages/page-#{index}.html"] = @files.fetch("index.html") + "<!-- #{'a' * 20_000} -->\n" }
    workspace = fresh_workspace
    paths = @files.keys.grep(/pages\//)
    paths.each { |path| workspace.read(path) }
    paths.first(12).each do |path|
      workspace.replace(path, "<title>Fortop</title>", "<title>Fortop · GEO</title>", finding_ids: [ 1 ])
    end

    assert_equal 125, workspace.coverage["read_files"]
    assert_operator workspace.coverage["read_bytes"], :>, 2_000_000
    assert_equal 12, workspace.changed_files.size
    assert_includes workspace.original(paths.first), "<title>Fortop</title>"
    assert_includes workspace.read(paths.first), "<title>Fortop · GEO</title>"
    assert Scans::Validator.new(workspace).call.all? { |check| check["passed"] }
  ensure
    workspace&.close
  end

  test "inventories beyond twenty thousand files retain correct pagination" do
    tree = Array.new(20_250) { |index| { "path" => format("pages/%05d.html", index), "type" => "blob", "mode" => "100644" } }
    workspace = Scans::Workspace.new(github: Object.new, full_name: "test/repo", sha: "a" * 40, tree: tree)
    page = workspace.list_files(offset: 20_200)
    assert_equal 20_250, page["total"]
    assert_equal 50, page["files"].length
    assert_equal "pages/20200.html", page["files"].first
    assert_nil page["next_offset"]
  ensure
    workspace&.close
  end

  test "line reading continues beyond the old byte and line ceilings" do
    @files["long.txt"] = "source\n" * 100_100
    workspace = fresh_workspace
    page = workspace.read_lines("long.txt", start_line: 100_001)
    assert_equal 100_100, page["total_lines"]
    assert page["content"].start_with?("100001: source\n")
    assert_includes page["content"], "100100: source\n"
    assert_nil page["next_line"]
  ensure
    workspace&.close
  end

  test "line pages expose a continuation when the response size cuts the requested range" do
    @files["wide.txt"] = ("a" * 300 + "\n") * 250
    workspace = fresh_workspace
    first = workspace.read_lines("wide.txt")
    assert first["truncated"]
    assert_operator first["next_line"], :>, 1
    second = workspace.read_lines("wide.txt", start_line: first["next_line"])
    assert second["content"].start_with?("#{first['next_line']}: ")
    assert_operator second["content"].lines.size, :>, 1
  ensure
    workspace&.close
  end

  test "search finds evidence beyond the first forty five files" do
    120.times { |index| @files[format("pages/%03d.html", index)] = index == 119 ? "needle\n" : "other\n" }
    workspace = fresh_workspace
    page = workspace.search("needle", prefix: "pages/")
    assert_equal 45, page["searched_files"]
    assert page["limited"]
    assert_empty page["matches"]
    page = workspace.search("needle", prefix: "pages/", offset: page["next_offset"], start_line: page["next_line"])
    page = workspace.search("needle", prefix: "pages/", offset: page["next_offset"], start_line: page["next_line"])
    assert_equal "pages/119.html", page["matches"].first["path"]
    assert_nil page["next_offset"]
    refute page["limited"]
    assert_equal 120, workspace.read_paths.size
  ensure
    workspace&.close
  end

  test "search resumes within a file without losing or duplicating matches" do
    @files["matches.txt"] = "needle\n" * 95
    workspace = fresh_workspace
    page = workspace.search("needle", prefix: "matches.txt")
    assert_equal 0, page["next_offset"]
    assert_equal 41, page["next_line"]
    matches = page["matches"]
    while page["next_offset"]
      page = workspace.search("needle", prefix: "matches.txt", offset: page["next_offset"], start_line: page["next_line"])
      matches += page["matches"]
    end
    assert_equal (1..95).to_a, matches.map { |match| match["line"] }
    refute page["limited"]
  ensure
    workspace&.close
  end

  test "pause snapshot restores edits and evidence lazily without storing the complete source inventory" do
    @workspace.read("index.html")
    @workspace.read("data.json")
    @workspace.replace("index.html", "<html>", '<html lang="es">', finding_ids: [ 7 ])
    snapshot = JSON.parse(JSON.generate(@workspace.snapshot))
    refute snapshot.key?("originals")
    refute_includes JSON.generate(snapshot), @files["data.json"]
    restored = fresh_workspace
    restored.restore!(snapshot)
    assert_equal @workspace.coverage.except("total_files"), restored.coverage.except("total_files")
    assert_equal @workspace.changes, restored.changes
    assert_equal @workspace.changed_files, restored.changed_files
    assert_equal @files["index.html"], restored.original("index.html")
    assert_equal @files["data.json"], restored.original("data.json")
    assert_equal @workspace.coverage.except("total_files"), restored.coverage.except("total_files")
    restored.replace("index.html", "<head>", '<head><meta name="description" content="Fortop">', finding_ids: [ 9 ])
    assert_equal [ 7, 9 ], restored.finding_ids("index.html")
    restored.discard("index.html")
    assert_equal @files["index.html"], restored.read("index.html")
  ensure
    restored&.close
  end

  test "searching source does not count as direct or complete inspection" do
    @workspace.search("Fortop")
    assert_equal 3, @workspace.coverage["read_files"]
    assert_equal 3, @workspace.coverage["searched_files"]
    assert_equal 0, @workspace.coverage["inspected_files"]
    assert_equal [ { "path" => "index.html", "start_line" => 1 } ], @workspace.pending_review
    @workspace.read_lines("index.html")
    assert_equal 1, @workspace.coverage["inspected_files"]
    assert_equal 1, @workspace.coverage["reviewed_files"]
    assert_empty @workspace.pending_review
  end

  test "long web files remain pending until all source pages are inspected including after a pause" do
    @files["index.html"] = "<p>Contenido</p>\n" * 450
    @workspace.read_lines("index.html")
    assert_equal [ { "path" => "index.html", "start_line" => 201 } ], @workspace.pending_review
    @workspace.read_lines("index.html", start_line: 401)
    assert_equal 201, @workspace.pending_review.first["start_line"]
    restored = fresh_workspace.restore!(JSON.parse(JSON.generate(@workspace.snapshot)))
    assert_equal 201, restored.pending_review.first["start_line"]
    restored.read_lines("index.html", start_line: 201)
    assert_empty restored.pending_review
    assert_equal 1, restored.coverage["reviewed_files"]
  ensure
    restored&.close
  end

  test "deferred web files retain a visible reason and are not counted as reviewed" do
    reason = "Esta plantilla es un ejemplo interno de documentación y no se sirve como página del sitio web."
    assert_raises(Agents::ToolError) { @workspace.defer_review("index.html", "No aplica") }
    @workspace.defer_review("index.html", reason)
    assert_empty @workspace.pending_review
    assert_equal 0, @workspace.coverage["reviewed_files"]
    assert_equal({ "index.html" => reason }, @workspace.coverage["deferred_files"])
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
