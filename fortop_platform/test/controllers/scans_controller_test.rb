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
        post repository_scans_path(@repository), params: { return_to: "repository" }
      end
    end
    scan = @repository.scans.last
    assert scan.queued?
    assert_equal 0, scan.progress
    assert scan.scan_events.exists?
    assert_redirected_to repository_path(@repository)
    assert_no_enqueued_jobs do
      assert_no_difference "Scan.count" do
        post repository_scans_path(@repository), params: { return_to: "repository" }
      end
    end
    assert_redirected_to repository_path(@repository)
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

  test "a failed publication can be enqueued again without creating another scan" do
    scan = saved_publication
    get repository_scan_path(@repository, scan)
    assert_redirected_to repository_path(@repository, scan_id: scan.id)
    follow_redirect!
    assert_select "button", text: "Reintentar publicación"
    refute_includes response.body, "private saved source"
    assert_select "button", text: "Reintentar análisis", count: 0

    assert_enqueued_with(job: ScanJob, args: [ scan.id ]) do
      assert_no_difference "Scan.count" do
        post retry_publication_repository_scan_path(@repository, scan), params: { return_to: "repository" }
      end
    end
    assert_redirected_to repository_path(@repository)
    assert scan.reload.queued?
    assert_nil scan.error_message
    assert_nil scan.finished_at
    assert scan.publication_changes.present?
    assert_equal 88, scan.progress

    assert_no_enqueued_jobs do
      post retry_publication_repository_scan_path(@repository, scan)
    end
  end

  test "publication cannot be retried when a different scan is active" do
    scan = saved_publication
    @repository.scans.create!
    assert_no_enqueued_jobs do
      post retry_publication_repository_scan_path(@repository, scan)
    end
    assert scan.reload.failed?
    assert_redirected_to repository_scan_path(@repository, scan)
  end

  test "old failures without saved changes offer a new analysis instead of promising AI-free recovery" do
    scan = @repository.scans.create!(status: "failed", error_message: "GitHub no responde.")
    get repository_scan_path(@repository, scan)
    follow_redirect!
    assert_select "button", text: "Reintentar análisis"
    assert_select "button", text: "Reintentar publicación", count: 0
    assert_includes response.body, "nuevo análisis con IA"
    assert_no_enqueued_jobs do
      post retry_publication_repository_scan_path(@repository, scan)
    end
    assert scan.reload.failed?
  end

  test "retry enqueue failure leaves the checkpoint available for another click" do
    scan = saved_publication
    ScanJob.stub(:perform_later, ->(*) { raise ActiveJob::EnqueueError, "private queue detail" }) do
      post retry_publication_repository_scan_path(@repository, scan)
    end
    assert scan.reload.publication_retryable?
    assert scan.finished_at
    assert_includes scan.error_message, "encolar la publicación"
    refute_includes scan.error_message, "private"
  end

  test "publication retry enforces scan and repository ownership" do
    another = User.create!(github_id: 90003, login: "someone", github_token: "secret")
    theirs = connected_repository(another, github_id: 203, name: "someone/site")
    scan = theirs.scans.create!(status: "failed", publication_changes: "{}", validation_results: [ { "passed" => true } ])
    assert_no_enqueued_jobs do
      post retry_publication_repository_scan_path(theirs, scan)
      assert_response :not_found
      post retry_publication_repository_scan_path(@repository, scan)
      assert_response :not_found
    end
    assert scan.reload.failed?
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
    follow_redirect!
    assert_response :success
    assert_select ".repository-scan-error", text: /No se ha podido iniciar el análisis/
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
    follow_redirect!
    assert_response :success
    assert_select ".is-complete", count: 1
    assert_select "a[href=?]", scan.pull_request_url, count: 1
    assert_select "a[href=?]", "https://github.com/fortop-builder/site/issues/6", count: 1
    assert_select ".finding-heading span", "Corrección propuesta"
    assert_select ".repository-checks small", "Correcto"
    assert_select "[data-scan-progress-active-value=false]"
  end

  test "no changes and failed publication are represented accurately" do
    scan = @repository.scans.create!(status: "completed", progress: 100)
    get repository_scan_path(@repository, scan)
    follow_redirect!
    assert_select ".repository-no-changes", text: /No se ha creado un pull request/
    scan.update!(status: "failed", progress: 90, error_message: "Publicación incompleta.", pull_request_url: "https://github.com/fortop-builder/site/pull/2")
    get repository_scan_path(@repository, scan)
    follow_redirect!
    assert_select ".is-complete", count: 0
    assert_select ".repository-scan-error", text: /Publicación incompleta/
    assert_select ".repository-scan-state.is-error h3", "Análisis interrumpido"
    assert_select "a[href=?]", scan.pull_request_url, count: 1
  end

  test "untrusted findings are escaped and invalid provider links never become executable" do
    scan = @repository.scans.create!(status: "completed", progress: 100, pull_request_url: "javascript:alert(1)")
    scan.findings.create!(title: "<script>alert(1)</script>", description: "<img src=x onerror=alert(1)>", severity: "low", category: "metadata", evidence: "<iframe src=evil>", issue_url: "https://evil.example/steal")
    get repository_scan_path(@repository, scan)
    follow_redirect!
    assert_response :success
    assert_select "script:not([type=importmap]):not([type=module])", count: 0
    assert_select "a[href^='javascript:']", count: 0
    assert_select "a[href^='https://evil.example']", count: 0
    assert_includes response.body, "&lt;script&gt;"
    assert_select ".finding-body img", count: 0
  end

  private

  def saved_publication
    @repository.scans.create!(status: "failed", progress: 88, error_message: "GitHub no responde.", finished_at: Time.current,
      publication_changes: '{"index.html":"private saved source"}', validation_results: [ { "name" => "scope", "passed" => true } ])
  end
end
