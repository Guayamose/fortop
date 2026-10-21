require "application_system_test_case"

class RepositoryFlowTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @previous_forgery_protection = ApplicationController.allow_forgery_protection
    ApplicationController.allow_forgery_protection = true
    page.current_window.resize_to(1440, 1000)
  end

  teardown do
    ApplicationController.allow_forgery_protection = @previous_forgery_protection
  end

  test "an expired login form recovers and allows a fresh GitHub sign in" do
    with_browser_github do
      visit new_session_path
      assert_button "Continuar con GitHub"
      page.driver.browser.manage.delete_cookie(Rails.application.config.session_options.fetch(:key))

      assert_no_difference "User.count" do
        click_button "Continuar con GitHub"
        assert_current_path new_session_path
        assert_text "El formulario de acceso ha caducado."
        assert_no_text "GitHub conectado"
      end

      click_button "Continuar con GitHub"
      assert_selector "h1", text: "Repositorios"
      assert_text "GitHub conectado"
    end
  end

  test "GitHub sign in connects a repository starts agents and receives completion through live polling" do
    with_browser_github do
      visit new_session_path
      assert_text "Todo empieza"
      find("button[aria-label='Pausar animación']").click
      assert_selector "button[aria-label='Reanudar animación']"
      find("button[aria-label='Reanudar animación']").click
      save_review_screenshot("access-desktop")
      click_button "Continuar con GitHub"
      assert_selector "h1", text: "Repositorios"
      assert_text "Tu primer repositorio"
      assert_no_selector ".repository-card"
      assert_no_horizontal_overflow
      save_review_screenshot("repositories-empty-desktop")

      click_link "Conectar un repositorio"
      assert_selector ".picker-repo-copy strong", text: "browser-builder/website"
      save_review_screenshot("repository-picker-desktop")
      click_button "Conectar", exact: true
      assert_selector "h1", text: "website"
      assert_text "Listo para analizar."
      save_review_screenshot("repository-profile-desktop")
      repository = User.find_by!(github_id: 92001).repositories.find_by!(github_id: 42001)

      assert_enqueued_with(job: ScanJob) do
        click_button "Iniciar análisis"
        assert_selector ".repository-scan-state h3", text: "En cola"
      end
      assert_current_path repository_path(repository)
      assert_selector "h1", text: "website"
      assert_text "En cola"
      assert_button "Desconectar repositorio", disabled: true
      assert_no_selector ".repository-scan-state.is-complete"
      scan = repository.scans.last
      assert scan.queued?
      find(".repository-scan-details > summary", text: "Actividad reciente de los agentes").click

      scan.update!(status: "analyzing", progress: 38, started_at: Time.current)
      scan.record_event!("El agente de análisis está revisando las plantillas.", kind: "tool")
      assert_selector "[role=progressbar][aria-valuenow='38']", wait: 10
      assert_text "El agente de análisis está revisando las plantillas."
      assert_selector ".repository-scan-details[open] > summary", text: "Actividad reciente de los agentes"
      find(".repository-scan-details > summary", text: "Actividad reciente de los agentes").click
      save_review_screenshot("scan-running-desktop")

      scan.update!(status: "completed", progress: 100, summary: "El agente ha revisado la estructura y documentado una oportunidad de mejora.", finished_at: Time.current)
      scan.findings.create!(title: "Revisar descripción de la página", description: "La plantilla no define una descripción específica.", severity: "medium", category: "metadata", evidence: "La plantilla revisada no contiene meta description.", status: "manual", automatable: false,
        issue_url: "https://github.com/browser-builder/website/issues/11")
      scan.record_event!("Ejecución completada. El diagnóstico ya está disponible.")

      # No navigation or reload: Stimulus fetches the real JSON endpoint and
      # replaces the progress with the terminal summary rendered by Rails.
      assert_text "Análisis completado", wait: 10
      assert_selector ".repository-scan-state.is-complete"
      assert_current_path repository_path(repository)
      assert_text "El agente ha revisado la estructura y documentado una oportunidad de mejora."
      assert_text "No se ha creado un pull request."
      assert_selector "[data-scan-progress-active-value='false']"
      assert_button "Nuevo análisis"
      assert_button "Desconectar repositorio", disabled: false
      assert_no_selector ".repository-history"
      assert_no_horizontal_overflow
      save_review_screenshot("scan-completed-desktop")
      find(".repository-scan-details > summary", text: "Ver hallazgos y recomendaciones").click
      assert_text "Revisión manual"
      find(".finding-card summary").click
      assert_link "Ver issue en GitHub", href: "https://github.com/browser-builder/website/issues/11"

      page.current_window.resize_to(390, 844)
      assert_selector "h1", text: "website"
      assert_no_horizontal_overflow
      save_review_screenshot("scan-completed-mobile")
      assert_no_horizontal_overflow

      assert_enqueued_with(job: ScanJob) do
        click_button "Nuevo análisis"
        assert_selector ".repository-scan-state h3", text: "En cola"
      end
      new_scan = repository.scans.recent.first
      assert_text "Historial de análisis"
      assert_current_path repository_path(repository)
      find(".history-row", text: "Análisis ##{scan.id}").click
      assert_selector ".repository-scan-state h3", text: "Análisis completado"
      assert_current_path repository_path(repository, scan_id: scan.id)
      assert_no_button "Nuevo análisis"
      click_link "Ver análisis en curso"
      assert_selector ".repository-scan-state h3", text: "En cola"
      assert_current_path repository_path(repository, scan_id: new_scan.id)
    end
  end

  test "failed publication can be retried from its result screen and resume live progress" do
    with_browser_github do
      visit new_session_path
      click_button "Continuar con GitHub"
      assert_selector "h1", text: "Repositorios"
      user = User.find_by!(github_id: 92001)
      repository = user.repositories.create!(github_id: 42001, installation_id: 88001, full_name: "browser-builder/website", html_url: "https://github.com/browser-builder/website")
      scan = repository.scans.create!(status: "failed", progress: 88, error_message: "GitHub no responde.", finished_at: Time.current,
        publication_changes: '{"files":{},"read_paths":[]}', validation_results: [ { "name" => "scope", "passed" => true } ])
      visit repository_scan_path(repository, scan)
      assert_current_path repository_path(repository, scan_id: scan.id)
      assert_button "Reintentar publicación"
      assert_text "sin repetir la IA"
      save_review_screenshot("scan-retry-desktop")
      assert_enqueued_with(job: ScanJob, args: [ scan.id ]) do
        assert_no_difference "Scan.count" do
          click_button "Reintentar publicación"
          assert_text "En cola"
        end
      end
      assert scan.reload.queued?
      assert_current_path repository_path(repository)
      assert_no_horizontal_overflow
      scan.update!(status: "completed", progress: 100, publication_changes: nil, summary: "Publicación recuperada.", finished_at: Time.current,
        pull_request_url: "https://github.com/browser-builder/website/pull/42", pull_request_number: 42)
      assert_text "Análisis completado", wait: 10
      assert_text "Publicación recuperada."
      assert_no_button "Reintentar publicación"
      assert_selector "[data-scan-progress-active-value='false']"
      assert_link "Ver pull request", href: scan.pull_request_url
      save_review_screenshot("repository-proposal-desktop")
    end
  end

  test "repository list filters real rows by search and status and fits mobile" do
    with_browser_github do
      visit new_session_path
      click_button "Continuar con GitHub"
      assert_selector "h1", text: "Repositorios"
      user = User.find_by!(github_id: 92001)
      completed = user.repositories.create!(github_id: 42001, installation_id: 88001, full_name: "browser-builder/website", html_url: "https://github.com/browser-builder/website", language: "Ruby")
      completed.scans.create!(status: "completed", progress: 100, finished_at: Time.current)
      failed = user.repositories.create!(github_id: 42002, installation_id: 88001, full_name: "browser-builder/fortop-integration-check-ee2bda", html_url: "https://github.com/browser-builder/fortop-integration-check-ee2bda", language: "HTML")
      failed.scans.create!(status: "failed", progress: 88, error_message: "GitHub no responde.", finished_at: Time.current)

      visit repositories_path
      assert_selector ".repository-card", count: 2
      assert_no_horizontal_overflow
      save_review_screenshot("repository-list-desktop")
      find("input[aria-label='Buscar repositorios']").set("Ruby")
      assert_selector ".repository-card", count: 1
      assert_link "browser-builder/website"
      find("button[data-filter='failed']").click
      assert_text "No hay repositorios que coincidan."
      click_button "Quitar filtros"
      assert_selector ".repository-card", count: 2
      find("button[data-filter='failed']").click
      assert_selector ".repository-card", count: 1
      assert_link "browser-builder/fortop-integration-check-ee2bda"

      find("button[data-filter='all']").click
      find("summary[aria-label='Menú de cuenta']").click
      assert_button "Cerrar sesión"
      find("summary[aria-label='Menú de cuenta']").click
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      assert_selector ".repository-card", count: 2
      save_review_screenshot("repository-list-mobile")
      click_link "browser-builder/fortop-integration-check-ee2bda"
      assert_selector "h1", text: "fortop-integration-check-ee2bda"
      assert_no_horizontal_overflow
      save_review_screenshot("repository-profile-mobile")

      visit new_session_path
      # Signed-in users are redirected to their workspace rather than shown login.
      assert_selector "h1", text: "Repositorios"
    end
  end

  private

  def assert_no_horizontal_overflow
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "The page should fit its viewport without horizontal overflow"
  end

  def save_review_screenshot(name)
    return unless ENV["SYSTEM_SCREENSHOTS"] == "1"

    directory = Rails.root.join("tmp/screenshots")
    FileUtils.mkdir_p(directory)
    page.execute_script("window.scrollTo(0, 0)")
    page.save_screenshot(directory.join("#{name}.png"))
  end

  def with_browser_github
    oauth = Object.new
    oauth.define_singleton_method(:authorize_url) do |state:, code_verifier:|
      "/auth/github/callback?#{URI.encode_www_form(code: 'system-test-code', state: state)}"
    end
    oauth.define_singleton_method(:exchange) { |**| { token: "ghu_browser_test_only", refresh_token: "ghr_browser_test_only", expires_at: 8.hours.from_now } }
    client = Object.new
    client.define_singleton_method(:user) { { "id" => 92001, "login" => "browser-builder", "name" => "Browser Builder" } }
    client.define_singleton_method(:installations) { |**| [ { "id" => 88001, "account" => { "login" => "browser-builder" } } ] }
    repository = { "id" => 42001, "full_name" => "browser-builder/website", "default_branch" => "main", "html_url" => "https://github.com/browser-builder/website", "description" => "La web del proyecto", "language" => "Ruby", "private" => true, "permissions" => { "push" => true }, "archived" => false, "disabled" => false }
    client.define_singleton_method(:installation_repositories) { |*, **| [ repository ] }

    Github::App.stub(:configured?, true) do
      Github::OAuth.stub(:new, oauth) do
        Github::Client.stub(:new, client) do
          Github::Access.stub(:user_client, client) do
            Github::Access.stub(:repository_for, repository) { yield }
          end
        end
      end
    end
  end
end
