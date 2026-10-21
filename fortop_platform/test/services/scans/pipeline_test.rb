require "test_helper"

class Scans::PipelineTest < ActiveSupport::TestCase
  class Github
    attr_reader :issues, :commits, :pulls, :branches
    attr_accessor :fail_pr_once, :fail_issue_count, :lose_issue_response, :lose_branch_response, :lose_commit_response, :lose_pr_response
    SOURCE = "<!doctype html>\n<html><head>\n<title>Fortop</title>\n</head><body><h1>Fortop</h1><p>Fortop analiza y mejora la visibilidad del código web.</p></body></html>\n".freeze

    def initialize
      @issues, @commits, @pulls, @branches = [], [], [], { "main" => "a" * 40 }
      @files_by_sha = { "a" * 40 => { "index.html" => SOURCE, "README.md" => "Página oficial: https://fortop.dev/" } }
      @fail_issue_count = 0
    end
    def repository(_name)
      { "default_branch" => "main", "permissions" => { "push" => true } }
    end
    def branch_sha(_name, branch)
      @branches.fetch(branch) { raise ::Github::Error.new("Missing branch", status: 404) }
    end
    def tree(_name, sha)
      @files_by_sha.fetch(sha).map do |path, content|
        { "path" => path, "type" => "blob", "mode" => "100644", "size" => content.bytesize, "sha" => Digest::SHA1.hexdigest(content) }
      end
    end
    def file(_name, path, ref:)
      @files_by_sha.fetch(ref).fetch(path)
    end
    def find_issue(_name, marker:)
      @issues.find { |issue| issue["body"].include?(marker) }
    end
    def create_issue(_name, title:, body:)
      if @fail_issue_count.positive?
        @fail_issue_count -= 1
        raise ::Github::Error.new("Fallo temporal de conexión.", retryable: true)
      end
      @issues << { "number" => @issues.size + 1, "html_url" => "https://github.com/test/repo/issues/#{@issues.size + 1}", "title" => title, "body" => body }
      lose_response!(:issue)
      @issues.last
    end
    def create_branch(_name, name:, sha:)
      @branches[name] = sha
      lose_response!(:branch)
    end
    def commit_files(_name, branch:, base_sha:, files:, message:)
      @commits << { branch: branch, base_sha: base_sha, files: files.deep_dup, message: message }
      @branches[branch] = "b" * 40
      @files_by_sha["b" * 40] = @files_by_sha.fetch(base_sha).merge(files)
      lose_response!(:commit)
      { "sha" => "b" * 40 }
    end
    def find_pull_request(_name, head:)
      @pulls.find { |pull| pull["head"] == head }
    end
    def create_pull_request(_name, head:, base:, title:, body:)
      if @fail_pr_once
        @fail_pr_once = false
        raise ::Github::Error, "GitHub no está disponible temporalmente."
      end
      @pulls << { "number" => 2, "html_url" => "https://github.com/test/repo/pull/2", "head" => head, "base" => base, "title" => title, "body" => body }
      lose_response!(:pr)
      @pulls.last
    end

    def lose_response!(operation)
      if public_send("lose_#{operation}_response")
        public_send("lose_#{operation}_response=", false)
        raise ::Github::Error.new("Respuesta perdida tras aceptar la escritura.", retryable: true)
      end
    end
  end

  class Provider
    attr_reader :model, :usage
    def initialize(responses)
      @responses = responses
      @model = "fixture-model"
      @usage = { "requests" => 0, "total_tokens" => 0 }
    end
    def generate(**_args)
      @usage["requests"] += 1
      @usage["total_tokens"] += 100
      response = @responses.shift || raise("Unexpected model request")
      response.respond_to?(:call) ? response.call : response
    end
  end

  setup do
    user = User.create!(github_id: SecureRandom.random_number(1_000_000_000), login: "test-user", github_token: "fake-token")
    @repository = user.repositories.create!(github_id: SecureRandom.random_number(1_000_000_000), full_name: "test/repo", default_branch: "main", html_url: "https://github.com/test/repo", installation_id: 42)
    @scan = @repository.scans.create!
    @github = Github.new
  end

  test "executes both agents, verifies edits and publishes real result objects" do
    provider = Provider.new(successful_script)
    Scans::Pipeline.new(@scan, github: @github, provider: provider).call

    assert @scan.reload.completed?, @scan.error_message
    assert_equal 100, @scan.progress
    assert_equal 1, @github.issues.size
    assert_equal 1, @github.commits.size
    assert_equal 1, @github.pulls.size
    assert_includes @github.pulls.first["body"], "- #1: Falta descripción"
    assert_includes @github.commits.first[:files]["index.html"], '<meta name="description"'
    assert_equal "fixed", @scan.findings.first.status
    assert @scan.validation_results.all? { |check| check["passed"] }
    assert_equal "index.html", @scan.changed_files.first["path"]
    assert_equal 8, @scan.metadata.dig("usage", "requests")
    assert @scan.scan_events.where(kind: "tool").exists?
  end

  test "publishes two validated findings corrected by separate edits to the same file" do
    Scans::Pipeline.new(@scan, github: @github, provider: Provider.new(two_finding_script)).call

    assert @scan.reload.completed?, @scan.error_message
    assert_equal 2, @scan.findings.where(status: "fixed").count
    assert_equal 0, @scan.findings.where(status: "manual").count
    assert_equal @scan.findings.pluck(:id).sort, @scan.changed_files.first["finding_ids"].sort
    assert @scan.validation_results.all? { |check| check["passed"] }
    content = @github.commits.first[:files].fetch("index.html")
    assert_includes content, '<meta name="description"'
    assert_includes content, 'type="application/ld+json"'
    assert_equal 1, @github.pulls.size
  end

  test "rejects a later full rewrite that reverts an earlier linked description correction" do
    Scans::Pipeline.new(@scan, github: @github, provider: Provider.new(two_finding_script(revert: :description))).call

    assert @scan.reload.failed?
    assert_empty @github.pulls
    assert_empty @github.commits
    assert_equal @scan.findings.pluck(:id).sort, @scan.changed_files.first["finding_ids"].sort
    assert @scan.validation_results.any? { |check| check["name"].end_with?(":description") && !check["passed"] }
  end

  test "rejects a later full rewrite that removes an earlier linked JSON LD correction" do
    Scans::Pipeline.new(@scan, github: @github, provider: Provider.new(two_finding_script(revert: :json_ld))).call

    assert @scan.reload.failed?
    assert_empty @github.pulls
    assert_empty @github.commits
    assert_equal @scan.findings.pluck(:id).sort, @scan.changed_files.first["finding_ids"].sort
    assert @scan.validation_results.any? { |check| check["name"].end_with?(":json_ld") && !check["passed"] }
  end

  test "never opens a pull request when independent final validation fails" do
    invalid = ->(_workspace) { -> { [ { "name" => "fixture-invalid", "passed" => false, "details" => "Invalid change" } ] } }
    Scans::Pipeline.new(@scan, github: @github, provider: Provider.new(successful_script), validator_factory: invalid).call

    assert @scan.reload.failed?
    assert_empty @github.pulls
    assert_empty @github.commits
    assert_equal 1, @github.issues.size
    assert_includes @scan.error_message, "no se ha abierto ningún PR"
  end

  test "linking a cosmetic edit to a metadata finding does not count as remediation" do
    script = successful_script
    script[5] = -> { tool("replace_text", path: "index.html", old_text: "<title>Fortop</title>", new_text: "<title>Fortop</title>\n<!-- inspected -->", finding_ids: [ @scan.findings.first.id ]) }
    Scans::Pipeline.new(@scan, github: @github, provider: Provider.new(script)).call

    assert @scan.reload.failed?
    assert_empty @github.pulls
    assert @scan.validation_results.any? { |check| check["name"].include?("semantic:") && !check["passed"] }
    assert_equal "manual", @scan.findings.first.status
  end

  test "resumes publication after provider independent GitHub failure without duplicating commit or issue" do
    @github.fail_pr_once = true
    Scans::Pipeline.new(@scan, github: @github, provider: Provider.new(successful_script)).call
    assert @scan.reload.failed?
    assert_equal "b" * 40, @scan.metadata.dig("publication", "commit_sha")

    @scan.update!(status: "queued", error_message: nil, publication_changes: nil)
    never_call_ai = Provider.new([])
    Scans::Pipeline.new(@scan, github: @github, provider: never_call_ai).call

    assert @scan.reload.completed?, @scan.error_message
    assert_equal 1, @github.commits.size
    assert_equal 1, @github.issues.size
    assert_equal 1, @github.pulls.size
    assert_equal 0, never_call_ai.usage["requests"]
    assert_equal 8, @scan.metadata.dig("usage", "requests")
  end

  test "automatically retries an issue failure without repeating either agent" do
    @github.fail_issue_count = 1
    run_pipeline(provider: Provider.new(successful_script))

    assert @scan.reload.completed?, @scan.error_message
    assert_equal 1, @github.issues.size
    assert_equal 1, @github.commits.size
    assert_equal 1, @github.pulls.size
    assert_equal 8, @scan.metadata.dig("usage", "requests")
    assert_equal 1, @scan.scan_events.where(kind: "warning").count
    assert_nil @scan.publication_changes
  end

  %w[issue branch commit pr].each do |operation|
    test "recovers a lost #{operation} write response without duplicate publications" do
      @github.public_send("lose_#{operation}_response=", true)
      run_pipeline(provider: Provider.new(successful_script))

      assert @scan.reload.completed?, @scan.error_message
      assert_equal 1, @github.issues.size
      assert_equal 1, @github.commits.size
      assert_equal 1, @github.pulls.size
      assert_equal 8, @scan.metadata.dig("usage", "requests")
      assert_equal 1, @scan.scan_events.where(kind: "warning").count
    end
  end

  test "exhausted retries keep an encrypted checkpoint and resume before any commit without AI" do
    @github.fail_issue_count = 3
    run_pipeline(provider: Provider.new(successful_script))

    assert @scan.reload.failed?
    assert @scan.publication_retryable?
    assert_equal 2, @scan.scan_events.where(kind: "warning").count
    assert_empty @github.commits
    saved = JSON.parse(@scan.publication_changes).fetch("files")
    assert_includes saved.fetch("index.html"), '<meta name="description"'
    raw = Scan.connection.select_value("SELECT publication_changes FROM scans WHERE id = #{@scan.id}")
    refute_includes raw, saved.fetch("index.html")
    assert @scan.metadata.dig("publication", "commit_sha").blank?

    @scan.update!(status: "queued", error_message: nil)
    provider = Provider.new([])
    run_pipeline(provider: provider)

    assert @scan.reload.completed?, @scan.error_message
    assert_equal 0, provider.usage["requests"]
    assert_equal 8, @scan.metadata.dig("usage", "requests")
    assert_equal 1, @github.issues.size
    assert_equal 1, @github.commits.size
    assert_equal 1, @github.pulls.size
    assert_nil @scan.publication_changes
  end

  test "an issues-only publication can resume without AI or a proposed commit" do
    @github.fail_issue_count = 3
    script = [ tool("read_file", path: "index.html"), tool("report_finding", finding_arguments.merge("automatable" => false)), final("Requiere revisión manual.") ]
    run_pipeline(provider: Provider.new(script))
    assert @scan.reload.publication_retryable?
    assert_empty JSON.parse(@scan.publication_changes).fetch("files")
    @scan.update!(status: "queued", error_message: nil)

    run_pipeline

    assert @scan.reload.completed?, @scan.error_message
    assert_equal 3, @scan.metadata.dig("usage", "requests")
    assert_equal 1, @github.issues.size
    assert_empty @github.commits
    assert_empty @github.pulls
  end

  test "permission errors are not automatically retried" do
    calls = 0
    @github.define_singleton_method(:create_issue) do |*, **|
      calls += 1
      raise ::Github::Error.new("Autorización caducada.", status: 401)
    end
    run_pipeline(provider: Provider.new(successful_script))
    assert @scan.reload.failed?
    assert_equal 1, calls
    assert_equal 0, @scan.scan_events.where(kind: "warning").count
    assert @scan.publication_retryable?
  end

  test "recovery preserves validation context from inspected files that were not modified" do
    @github.fail_issue_count = 3
    script = successful_script
    script.insert(2, tool("read_file", path: "README.md"))
    script[6] = -> { tool("replace_text", path: "index.html", old_text: "<title>Fortop</title>", new_text: '<title>Fortop</title><meta name="description" content="Visita https://fortop.dev/ para conocer Fortop.">', finding_ids: [ @scan.findings.first.id ]) }
    run_pipeline(provider: Provider.new(script))
    assert @scan.reload.publication_retryable?, @scan.error_message
    assert_includes JSON.parse(@scan.publication_changes).fetch("read_paths"), "README.md"
    @scan.update!(status: "queued", error_message: nil)

    run_pipeline

    assert @scan.reload.completed?, @scan.error_message
    assert_equal 9, @scan.metadata.dig("usage", "requests")
    assert_equal 1, @github.commits.size
  end

  test "recovered changes must pass independent validation again before publishing" do
    @github.fail_issue_count = 3
    run_pipeline(provider: Provider.new(successful_script))
    @scan.update!(status: "queued", error_message: nil)
    provider = Provider.new([])
    invalid = ->(_workspace) { -> { [ { "name" => "recheck", "passed" => false } ] } }
    Scans::Pipeline.new(@scan, github: @github, provider: provider, validator_factory: invalid).call

    assert @scan.reload.failed?
    assert_includes @scan.error_message, "recuperadas"
    assert_equal 0, provider.usage["requests"]
    assert_empty @github.issues
    assert_empty @github.commits
    assert_empty @github.pulls
  end

  test "a checkpoint with mismatched files is rejected without spending AI or publishing" do
    @scan.update!(publication_changes: '{"../private.rb":"unsafe"}', validation_results: [ { "name" => "scope", "passed" => true } ])
    run_pipeline
    assert @scan.reload.failed?
    assert_includes @scan.error_message, "no corresponden"
    assert_empty @github.issues
    assert_empty @github.commits
  end

  test "no findings is an honest successful audit without fake publications" do
    provider = Provider.new([ tool("read_file", path: "index.html"), final("No hay hallazgos suficientes.") ])
    Scans::Pipeline.new(@scan, github: @github, provider: provider).call
    assert @scan.reload.completed?, @scan.error_message
    assert_empty @github.issues
    assert_empty @github.pulls
    assert_includes @scan.summary, "sin hallazgos"
  end

  test "reuses the same evidence issue across successive scans" do
    Scans::Pipeline.new(@scan, github: @github, provider: Provider.new(successful_script)).call
    assert @scan.reload.completed?
    first_issue = @scan.findings.first.issue_url
    @scan = @repository.scans.create!
    Scans::Pipeline.new(@scan, github: @github, provider: Provider.new(successful_script)).call
    assert @scan.reload.completed?, @scan.error_message
    assert_equal 1, @github.issues.size
    assert_equal first_issue, @scan.findings.first.issue_url
  end

  test "never commits to a managed branch that is the repository default" do
    branch = "fortop/scan-#{@scan.id}"
    @github.define_singleton_method(:repository) { |_name| { "default_branch" => branch, "permissions" => { "push" => true } } }
    @github.branches[branch] = "a" * 40
    provider = Provider.new([])
    Scans::Pipeline.new(@scan, github: @github, provider: provider).call
    assert @scan.reload.failed?
    assert_empty @github.commits
    assert_empty @github.pulls
    assert_equal 0, provider.usage["requests"]
    assert_includes @scan.error_message, "rama predeterminada"
  end

  test "rejects repositories with issues disabled before spending AI tokens or publishing anything" do
    @github.define_singleton_method(:repository) do |_name|
      { "default_branch" => "main", "has_issues" => false, "permissions" => { "push" => true } }
    end
    provider = Provider.new([])

    Scans::Pipeline.new(@scan, github: @github, provider: provider).call

    assert @scan.reload.failed?
    assert_equal 0, provider.usage["requests"]
    assert_equal 0, provider.usage["total_tokens"]
    assert_empty @github.issues
    assert_empty @github.pulls
    assert_empty @github.commits
    assert_equal [ "main" ], @github.branches.keys
    assert_not @scan.scan_events.where(kind: "tool").exists?
    assert_includes @scan.error_message, "issues desactivados"
    assert_includes @scan.error_message, "Settings > General > Features"
  end

  test "uses the verified installation capability when GitHub metadata reports user push false" do
    repository_id = @repository.github_id
    @github.define_singleton_method(:repository) do |_name|
      { "id" => repository_id, "default_branch" => "main", "has_issues" => true, "permissions" => { "push" => false } }
    end
    @github.define_singleton_method(:write_authorized_for?) { |id| id.to_s == repository_id.to_s }

    Scans::Pipeline.new(@scan, github: @github, provider: Provider.new(successful_script)).call

    assert @scan.reload.completed?, @scan.error_message
    assert_equal 1, @github.issues.size
    assert_equal 1, @github.pulls.size
  end

  test "does not infer write access from missing user permissions or an unrelated installation grant" do
    repository_id = @repository.github_id
    @github.define_singleton_method(:repository) do |_name|
      { "id" => repository_id, "default_branch" => "main", "has_issues" => true }
    end
    @github.define_singleton_method(:write_authorized_for?) { |id| id.to_s == (repository_id + 1).to_s }
    provider = Provider.new([])

    Scans::Pipeline.new(@scan, github: @github, provider: provider).call

    assert @scan.reload.failed?
    assert_equal 0, provider.usage["requests"]
    assert_empty @github.issues
    assert_empty @github.pulls
    assert_includes @scan.error_message, "permiso de escritura"
  end

  test "rejects an unmarked client with explicit push false without spending AI tokens" do
    @github.define_singleton_method(:repository) do |_name|
      { "default_branch" => "main", "permissions" => { "push" => false } }
    end
    provider = Provider.new([])
    Scans::Pipeline.new(@scan, github: @github, provider: provider).call
    assert @scan.reload.failed?
    assert_equal 0, provider.usage["requests"]
    assert_empty @github.issues
    assert_empty @github.pulls
  end

  test "does not accept mismatched GitHub identity even with a scoped write capability" do
    repository_id = @repository.github_id
    @github.define_singleton_method(:repository) do |_name|
      { "id" => repository_id + 1, "default_branch" => "main", "permissions" => { "push" => true } }
    end
    @github.define_singleton_method(:write_authorized_for?) { |_id| true }
    provider = Provider.new([])

    Scans::Pipeline.new(@scan, github: @github, provider: provider).call

    assert @scan.reload.failed?
    assert_equal 0, provider.usage["requests"]
    assert_empty @github.commits
    assert_includes @scan.error_message, "ya no corresponde"
  end

  test "rejects unsupported findings without original observed evidence" do
    workspace = Scans::Workspace.new(github: @github, full_name: "test/repo", sha: "a" * 40, tree: @github.tree("test/repo", "a" * 40))
    tools = Agents::AnalysisTools.new(workspace: workspace, scan: @scan)
    arguments = finding_arguments
    assert_raises(Agents::ToolError) { tools.call("report_finding", arguments) }
    workspace.read("index.html")
    assert_raises(Agents::ToolError) { tools.call("report_finding", arguments.merge("evidence" => "fabricated proof")) }
    assert_raises(Agents::ToolError) { tools.call("report_finding", arguments.merge("line_number" => 99)) }
    assert_empty @scan.findings
  ensure
    workspace&.close
  end

  test "does not mark an audit complete if the agent never inspects source" do
    Scans::Pipeline.new(@scan, github: @github, provider: Provider.new([ final("All done") ])).call
    assert @scan.reload.failed?
    assert_includes @scan.error_message, "sin inspeccionar"
    assert_empty @github.pulls
  end

  test "large audits remediate multiple batches and recover publication without repeating AI" do
    paths = Array.new(21) { |index| format("pages/%02d.html", index) }
    originals = @github.instance_variable_get(:@files_by_sha).fetch("a" * 40)
    paths.each { |path| originals[path] = Github::SOURCE }
    analysis = paths.flat_map do |path|
      [ tool("read_file", path: path), tool("report_finding", finding_arguments.merge("file_path" => path)) ]
    end
    remediation = paths.each_slice(20).flat_map do |batch|
      edits = batch.flat_map do |path|
        [ tool("read_file", path: path), -> {
          tool("replace_text", path: path, old_text: "<title>Fortop</title>",
            new_text: '<title>Fortop</title><meta name="description" content="Fortop analiza y mejora la visibilidad del código web.">',
            finding_ids: [ @scan.findings.find_by!(file_path: path).id ])
        } ]
      end
      edits + [ tool("validate_changes", {}), final("Lote de #{batch.size} correcciones verificado.") ]
    end
    provider = Provider.new(analysis + [ final("21 hallazgos contrastados.") ] + remediation)
    @github.fail_issue_count = 3
    run_pipeline(provider: provider)

    assert @scan.reload.failed?, @scan.error_message
    assert @scan.publication_retryable?
    assert_equal 21, @scan.findings.count
    assert_equal 21, @scan.changed_files.size
    assert @scan.validation_results.all? { |check| check["passed"] }
    assert_includes @scan.metadata["remediation_summary"], "20 correcciones"
    assert_includes @scan.metadata["remediation_summary"], "1 correcciones"
    assert_operator provider.usage["requests"], :>, 80

    @scan.update!(status: "queued", finished_at: nil)
    unused_provider = Provider.new([])
    run_pipeline(provider: unused_provider)

    assert @scan.reload.completed?, @scan.error_message
    assert_equal 0, unused_provider.usage["requests"]
    assert_equal 21, @scan.findings.where(status: "fixed").count
    assert_equal 21, @github.issues.size
    assert_equal 21, @github.commits.first[:files].size
    assert_equal 1, @github.pulls.size
  end

  private

  def run_pipeline(provider: Provider.new([]))
    pipeline = Scans::Pipeline.new(@scan, github: @github, provider: provider)
    pipeline.define_singleton_method(:sleep) { |_duration| }
    pipeline.call
  end

  def two_finding_script(revert: nil)
    description_tag = '<meta name="description" content="Fortop analiza y mejora la visibilidad del código web.">'
    schema_tag = '<script type="application/ld+json">{"@context":"https://schema.org","@type":"WebPage","name":"Fortop"}</script>'
    description_edit = -> { tool("replace_text", path: "index.html", old_text: "<title>Fortop</title>", new_text: "<title>Fortop</title>\n#{description_tag}", finding_ids: [ @scan.findings.find_by!(category: "metadata").id ]) }
    schema_edit = -> { tool("replace_text", path: "index.html", old_text: "</head>", new_text: "#{schema_tag}\n</head>", finding_ids: [ @scan.findings.find_by!(category: "structured_data").id ]) }
    edits = case revert
    when :description
      [ description_edit, -> { tool("write_file", path: "index.html", content: Github::SOURCE.sub("</head>", "#{schema_tag}\n</head>"), finding_ids: [ @scan.findings.find_by!(category: "structured_data").id ]) } ]
    when :json_ld
      [ schema_edit, -> { tool("write_file", path: "index.html", content: Github::SOURCE.sub("</head>", "#{description_tag}\n</head>"), finding_ids: [ @scan.findings.find_by!(category: "metadata").id ]) } ]
    else
      [ description_edit, schema_edit ]
    end
    schema_finding = finding_arguments.merge("title" => "Falta JSON-LD de la página", "description" => "No se observa JSON-LD en el HTML inspeccionado.", "category" => "structured_data", "line_number" => 4, "evidence" => "</head>", "recommendation" => "Añadir JSON-LD WebPage usando únicamente los datos existentes.")
    [ tool("list_files", {}), tool("read_file", path: "index.html"), tool("report_finding", finding_arguments), tool("report_finding", schema_finding), final("Dos hallazgos contrastados."), tool("read_file", path: "index.html"), *edits, tool("validate_changes", {}), final("Correcciones propuestas para revisión.") ]
  end

  def successful_script
    [
      tool("list_files", {}), tool("read_file", path: "index.html"), tool("report_finding", finding_arguments), final("Falta una descripción de la página en el documento HTML observado."),
      tool("read_file", path: "index.html"),
      -> { tool("replace_text", path: "index.html", old_text: "<title>Fortop</title>", new_text: "<title>Fortop</title>\n<meta name=\"description\" content=\"Fortop analiza y mejora la visibilidad del código web.\">", finding_ids: [ @scan.findings.first.id ]) },
      tool("validate_changes", {}), final("Propuesta una descripción basada en el contenido existente; comprobaciones estáticas correctas.")
    ]
  end

  def finding_arguments
    { "title" => "Falta descripción de la página", "description" => "El head observado contiene title pero no una descripción.", "category" => "metadata", "severity" => "medium", "file_path" => "index.html", "line_number" => 3, "evidence" => "<title>Fortop</title>", "recommendation" => "Añadir una descripción fiel al contenido existente.", "automatable" => true }
  end

  def tool(name, args)
    { "role" => "model", "parts" => [ { "functionCall" => { "name" => name, "args" => args.stringify_keys } } ] }
  end

  def final(text)
    { "role" => "model", "parts" => [ { "text" => text } ] }
  end
end
