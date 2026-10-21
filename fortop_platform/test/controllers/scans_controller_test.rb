require "test_helper"
require_relative "../support/github_sign_in"

class ScansControllerTest < ActionDispatch::IntegrationTest
  include GithubSignIn
  include ActiveJob::TestHelper

  setup do
    @user = sign_in_github
    @repository = connected_repository(@user)
  end

  test "start persists scan and activity before enqueueing actual background work" do
    assert_enqueued_with job: ScanJob do
      assert_difference "@repository.scans.count", 1 do
        post repository_scans_path(@repository)
      end
    end
    scan = @repository.scans.last
    assert scan.queued?
    assert_equal 0, scan.progress
    assert scan.scan_events.exists?
    assert_redirected_to repository_scan_path(@repository, scan)
  end

  test "repeated clicks reuse an active scan instead of launching multiple agents" do
    scan = @repository.scans.create!
    assert_no_enqueued_jobs do
      assert_no_difference "Scan.count" do
        post repository_scans_path(@repository)
      end
    end
    assert_redirected_to repository_scan_path(@repository, scan)
  end

  test "enqueue error produces a visible failed run which can be retried" do
    ScanJob.stub(:perform_later, ->(*) { raise ActiveJob::EnqueueError, "private queue detail" }) do
      post repository_scans_path(@repository)
    end
    scan = @repository.scans.last
    assert scan.failed?
    assert scan.finished_at
    assert_redirected_to repository_scan_path(@repository, scan)
    get response.location
    assert_response :success
    assert_select ".scan-error", text: /No se ha podido iniciar el análisis/
    assert_select ".is-complete", count: 0
    refute_includes response.body, "private queue detail"
  end

  test "scan ownership is enforced for start show and JSON progress" do
    another = User.create!(github_id: 90002, login: "someone", github_token: "secret")
    theirs = connected_repository(another, github_id: 202, name: "someone/private-site")
    scan = theirs.scans.create!
    assert_no_difference "Scan.count" do
      post repository_scans_path(theirs)
    end
    assert_response :not_found
    get repository_scan_path(theirs, scan)
    assert_response :not_found
    get repository_scan_path(@repository, scan, format: :json)
    assert_response :not_found
  end

  test "progress returns rendered latest state without credentials or raw agent metadata" do
    scan = @repository.scans.create!(status: "analyzing", progress: 35, metadata: { "internal" => "hidden-secret" })
    scan.record_event!("Leyendo las plantillas HTML.", kind: "tool")
    get repository_scan_path(@repository, scan, format: :json)
    assert_response :success
    data = response.parsed_body
    assert_equal true, data.fetch("active")
    assert_includes data.fetch("html"), "35%"
    assert_includes data.fetch("html"), "Leyendo las plantillas HTML."
    refute_includes response.body, "hidden-secret"
    refute_includes response.body, @user.github_token
    scan.update!(status: "completed", progress: 100, summary: "Se han revisado las señales del sitio.")
    get repository_scan_path(@repository, scan, format: :json)
    assert_equal false, response.parsed_body.fetch("active")
    assert_includes response.parsed_body.fetch("html"), "Análisis completado"
  end

  test "completed run presents real findings proposed corrections issues and PR links" do
    scan = @repository.scans.create!(status: "completed", progress: 100, summary: "Metadatos mejorados.",
      started_at: 2.minutes.ago, finished_at: Time.current, pull_request_url: "https://github.com/fortop-builder/site/pull/7",
      changed_files: [ { "path" => "app/views/layouts/application.html.erb", "additions" => 4, "deletions" => 1 } ],
      validation_results: [ { "name" => "Sintaxis", "passed" => true, "details" => "Correcto" } ])
    scan.findings.create!(title: "Descripción ausente", description: "Falta la descripción del sitio.", severity: "medium", category: "metadata", evidence: "No hay meta description.", status: "fixed", issue_url: "https://github.com/fortop-builder/site/issues/6")
    get repository_scan_path(@repository, scan)
    assert_response :success
    assert_select ".is-complete", count: 1
    assert_select "a[href=?]", scan.pull_request_url, count: 1
    assert_select "a[href=?]", "https://github.com/fortop-builder/site/issues/6", count: 1
    assert_select ".finding-state", "Corrección propuesta"
    assert_select ".validation-result", "Correcto"
    assert_select "[data-scan-progress-active-value=false]"
  end

  test "no changes and failed publication are represented accurately" do
    scan = @repository.scans.create!(status: "completed", progress: 100)
    get repository_scan_path(@repository, scan)
    assert_select ".no-changes-note", text: /No se ha creado un pull request/
    scan.update!(status: "failed", progress: 90, error_message: "Publicación incompleta.", pull_request_url: "https://github.com/fortop-builder/site/pull/2")
    get repository_scan_path(@repository, scan)
    assert_select ".is-complete", count: 0
    assert_select ".scan-error", text: /Publicación incompleta/
    assert_select "a[href=?]", scan.pull_request_url, count: 1
  end

  test "untrusted findings are escaped and invalid provider links never become executable" do
    scan = @repository.scans.create!(status: "completed", progress: 100, pull_request_url: "javascript:alert(1)")
    scan.findings.create!(title: "<script>alert(1)</script>", description: "<img src=x onerror=alert(1)>", severity: "low", category: "metadata", evidence: "<iframe src=evil>", issue_url: "https://evil.example/steal")
    get repository_scan_path(@repository, scan)
    assert_response :success
    assert_select "script:not([type=importmap]):not([type=module])", count: 0
    assert_select "a[href^='javascript:']", count: 0
    assert_select "a[href^='https://evil.example']", count: 0
    assert_includes response.body, "&lt;script&gt;"
    assert_select ".finding-body img", count: 0
  end
end
