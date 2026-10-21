require "test_helper"
require_relative "../support/github_sign_in"

class RepositoriesControllerTest < ActionDispatch::IntegrationTest
  include GithubSignIn

  setup do
    @user = sign_in_github
  end

  test "first workspace shows the connect action without fabricated repositories or metrics" do
    get repositories_path
    assert_response :success
    assert_select "h1", "Repositorios"
    assert_select "a[href=?]", new_repository_path, text: /Conectar un repositorio/
    assert_select ".repository-card", count: 0
    assert_select ".empty-state", count: 1
    assert_select "[aria-disabled=true]", text: /Visibilidad de marca/
    refute_includes response.body, @user.github_token
  end

  test "repository index and detail only expose the signed in users repositories" do
    ours = connected_repository(@user)
    another = User.create!(github_id: 90002, login: "someone", github_token: "private-token")
    theirs = connected_repository(another, github_id: 202, name: "someone/private-site")
    get repositories_path
    assert_select ".repository-card", count: 1
    assert_select "a[href=?]", repository_path(ours), count: 1
    assert_select "a[href=?]", repository_path(theirs), count: 0
    get repository_path(theirs)
    assert_response :not_found
    assert_no_difference "Repository.count" do
      delete repository_path(theirs)
    end
    assert_response :not_found
  end

  test "picker offers GitHub installation when the app has no granted access" do
    client = Object.new
    client.define_singleton_method(:installations) { |**| [] }
    Github::Access.stub(:user_client, client) do
      get new_repository_path
    end
    assert_response :success
    assert_select "form[action=?]", github_installation_path
    assert_select ".picker-row", count: 0
  end

  test "picker uses the selected permitted installation and labels page scoped search" do
    client = Object.new
    client.define_singleton_method(:installations) do |**|
      [ { "id" => 5001, "account" => { "login" => "fortop-builder" } }, { "id" => 5002, "account" => { "login" => "team" } } ]
    end
    repo = github_repository(full_name: "team/landing")
    calls = []
    client.define_singleton_method(:installation_repositories) { |id, **options| calls << [ id, options ]; [ repo ] }
    Github::Access.stub(:user_client, client) do
      get new_repository_path, params: { installation_id: 5002, q: "landing" }
    end
    assert_response :success
    assert_equal [ [ 5002, { page: 1, per_page: 30 } ] ], calls
    assert_select "label[for=q]", "Filtrar esta página"
    assert_select ".picker-repo-copy strong", "team/landing"
    assert_select "input[name=installation_id][value='5002']"
  end

  test "connect uses canonical authorized GitHub data and does not accept injected attributes" do
    canonical = github_repository
    verifier = lambda do |user, installation_id:, full_name:|
      assert_equal @user.id, user.id
      assert_equal 5001, installation_id
      assert_equal "fortop-builder/site", full_name
      canonical
    end
    Github::Access.stub(:repository_for, verifier) do
      assert_difference "@user.repositories.count", 1 do
        post repositories_path, params: { installation_id: 5001, full_name: "fortop-builder/site", github_id: 999, html_url: "javascript:alert(1)", private: false }
      end
    end
    repository = @user.repositories.last
    assert_equal 101, repository.github_id
    assert_equal 5001, repository.installation_id
    assert_equal "https://github.com/fortop-builder/site", repository.html_url
    assert repository.private?
    assert_redirected_to repository_path(repository)
  end

  test "cannot connect unauthorized or readonly repositories" do
    Github::Access.stub(:repository_for, ->(*) { raise Github::Error.new("sensitive provider message", status: 403) }) do
      assert_no_difference "Repository.count" do
        post repositories_path, params: { full_name: "other/secret", installation_id: 123 }
      end
    end
    assert_redirected_to new_repository_path
    refute_includes flash[:alert], "sensitive provider message"
    Github::Access.stub(:repository_for, github_repository(permissions: { "push" => false })) do
      assert_no_difference "Repository.count" do
        post repositories_path, params: { full_name: "fortop-builder/site", installation_id: 5001 }
      end
    end
    assert_redirected_to new_repository_path(installation_id: 5001)
  end

  test "disconnect preserves repository while a scan is active and succeeds afterwards" do
    repository = connected_repository(@user)
    scan = repository.scans.create!
    assert_no_difference "Repository.count" do
      delete repository_path(repository)
    end
    assert_redirected_to repository_path(repository)
    scan.update!(status: "completed", progress: 100)
    assert_difference "Repository.count", -1 do
      delete repository_path(repository)
    end
    assert_redirected_to repositories_path
  end

  test "repository profile offers one workspace before the first analysis" do
    repository = connected_repository(@user)
    get repository_path(repository)
    assert_response :success
    assert_select "h1 .repository-title-name", repository.display_name
    assert_select ".repository-analysis", count: 1
    assert_select ".run-panel, .run-flow", count: 0
    assert_select "form[action=?]", repository_scans_path(repository) do
      assert_select "input[name=return_to][value=repository]"
      assert_select "button", text: "Iniciar análisis"
    end
    assert_select "[data-scan-progress-active-value=false]"
    assert_select ".repository-scan-metrics", count: 0
  end

  test "profile JSON updates progress and results without rendering private state" do
    repository = connected_repository(@user)
    scan = repository.scans.create!(status: "analyzing", progress: 35, metadata: { "internal" => "hidden-secret" })
    scan.record_event!("Revisando las plantillas HTML.", kind: "tool")
    get repository_path(repository, format: :json), params: { scan_id: scan.id }
    assert_response :success
    assert_equal true, response.parsed_body["active"]
    assert_includes response.parsed_body["html"], 'aria-valuenow="35"'
    assert_includes response.parsed_body["html"], "Revisando las plantillas HTML."
    refute_includes response.body, "hidden-secret"
    refute_includes response.body, @user.github_token

    scan.update!(status: "completed", progress: 100, summary: "Se ha revisado el código del sitio.", finished_at: Time.current)
    get repository_path(repository, format: :json), params: { scan_id: scan.id }
    assert_equal false, response.parsed_body["active"]
    assert_includes response.parsed_body["html"], "Análisis completado"
    assert_includes response.parsed_body["html"], "Se ha revisado el código del sitio."
    assert_includes response.parsed_body["html"], "Nuevo análisis"
  end

  test "an older publication retry remains selectable while a newer completed analysis exists" do
    repository = connected_repository(@user)
    older = repository.scans.create!(status: "failed", created_at: 2.hours.ago)
    newer = repository.scans.create!(status: "completed", progress: 100)
    older.update!(status: "queued")
    get repository_path(repository)
    assert_select "[data-scan-progress-url-value=?]", repository_path(repository, scan_id: older.id, follow_restart: "1", format: :json)
    assert_select ".repository-selected-scan", text: /Análisis ##{older.id}/
    assert_select "a[href=?]", repository_path(repository, scan_id: newer.id), text: "Volver al último análisis"
    assert_select "button", text: "Nuevo análisis", count: 0
    assert_select "button[disabled]", text: "Desconectar repositorio"

    get repository_path(repository), params: { scan_id: newer.id }
    assert_select ".repository-selected-scan", text: /Análisis ##{newer.id}/
    assert_select "a[href=?]", repository_path(repository, scan_id: older.id), text: /Ver análisis en curso/

    older.update!(status: "completed", progress: 100, summary: "Publicación recuperada.")
    get repository_path(repository, format: :json), params: { scan_id: older.id }
    assert_equal false, response.parsed_body["active"]
    assert_includes response.parsed_body["html"], "Publicación recuperada."
  end

  test "profile history cannot select a scan belonging to a different repository" do
    repository = connected_repository(@user)
    another = connected_repository(@user, github_id: 333, name: "fortop-builder/another")
    scan = another.scans.create!(status: "completed")
    get repository_path(repository), params: { scan_id: scan.id }
    assert_response :not_found
    get repository_path(repository, format: :json), params: { scan_id: scan.id }
    assert_response :not_found
    get repository_path(repository, format: :json), params: { scan_id: [ scan.id ] }
    assert_response :not_found
  end
end
