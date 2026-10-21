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
        assert_no_selector ".access-main > .flash"
        assert_selector ".access-login [role=alert]", text: "El formulario de acceso ha caducado."
        assert_no_text "GitHub conectado"
      end

      click_button "Continuar con GitHub"
      assert_selector "h1", text: "Te damos la bienvenida"
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
      assert_selector "h1", text: "Te damos la bienvenida"
      assert_current_path root_path
      assert_no_text "Has iniciado sesión con GitHub."
      assert_no_selector ".repository-browser"
      assert_no_selector ".empty-state"
      assert_no_horizontal_overflow
      save_review_screenshot("home-desktop")
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      save_review_screenshot("home-mobile")
      page.current_window.resize_to(1440, 1000)
      within ".main-nav" do
        click_link "Repositorios", exact: true
      end
      assert_current_path repositories_path
      assert_selector "h1", text: "Repositorios"
      assert_text "Tu primer repositorio"
      assert_no_selector ".workspace-welcome"
      save_review_screenshot("repositories-empty-desktop")

      click_link "Conectar un repositorio"
      assert_selector ".picker-repo-copy strong", text: "browser-builder/website"
      assert_text "Fortop solo tiene acceso a los repositorios seleccionados"
      assert_link "Añadir repositorios en GitHub", href: "https://github.com/settings/installations/88001"
      save_review_screenshot("repository-picker-desktop")
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      save_review_screenshot("repository-picker-mobile")
      page.current_window.resize_to(1440, 1000)
      click_button "Conectar", exact: true
      assert_selector "h1", text: "website"
      assert_text "Descubre qué puede mejorar tu web."
      assert_selector ".repository-ready-steps li", count: 3
      assert_no_horizontal_overflow
      save_review_screenshot("repository-profile-desktop")
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      assert_button "Iniciar análisis"
      save_review_screenshot("repository-ready-mobile")
      page.current_window.resize_to(1440, 1000)
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
      assert_selector ".repository-console [role=log]"
      assert_button "Pausar"
      assert_button "Reiniciar"
      assert_button "Cancelar"

      scan.update!(status: "analyzing", progress: 38, started_at: Time.current)
      scan.record_event!("El agente de análisis está revisando las plantillas.", kind: "tool")
      assert_selector "[role=progressbar][aria-valuenow='38']", wait: 10
      assert_text "El agente de análisis está revisando las plantillas."
      assert_selector ".repository-console li", text: "El agente de análisis está revisando las plantillas."
      save_review_screenshot("scan-running-desktop")

      scan.update!(status: "completed", progress: 100, summary: "El agente ha revisado la estructura y documentado una oportunidad de mejora.", finished_at: Time.current)
      scan.findings.create!(title: "Revisar descripción de la página", description: "La plantilla no define una descripción específica.", severity: "medium", category: "metadata", evidence: "La plantilla revisada no contiene meta description.", status: "manual", automatable: false,
        issue_url: "https://github.com/browser-builder/website/issues/11")
      scan.record_event!("Ejecución completada. El diagnóstico ya está disponible.")

      # No navigation or reload: Stimulus fetches the real JSON endpoint and
      # replaces the progress with the terminal results rendered by Rails.
      assert_text "Análisis completado", wait: 10
      assert_selector ".repository-scan-state.is-complete"
      assert_current_path repository_path(repository)
      assert_no_text "El agente ha revisado la estructura y documentado una oportunidad de mejora."
      assert_text "No se ha creado un pull request."
      assert_selector "[data-scan-progress-active-value='false']"
      assert_button "Nuevo análisis"
      assert_button "Desconectar repositorio", disabled: false
      assert_no_selector ".repository-history"
      assert_no_horizontal_overflow
      save_review_screenshot("scan-completed-desktop")
      assert_text "Revisión manual"
      find(".finding-review > summary").click
      assert_text "La plantilla no define una descripción específica."
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
      assert_no_selector ".repository-history[open]"
      find(".repository-history > summary").click
      find(".history-row", text: "Análisis ##{scan.id}").click
      assert_selector ".repository-scan-state h3", text: "Análisis completado"
      assert_current_path repository_path(repository, scan_id: scan.id)
      assert_no_button "Nuevo análisis"
      click_link "Ver análisis en curso"
      assert_selector ".repository-scan-state h3", text: "En cola"
      assert_current_path repository_path(repository, scan_id: new_scan.id)
    end
  end

  test "finding reviews expand with highlighted evidence and the actual remediation diff" do
    with_browser_github do
      visit new_session_path
      click_button "Continuar con GitHub"
      assert_selector "h1", text: "Te damos la bienvenida"
      user = User.find_by!(github_id: 92001)
      repository = user.repositories.create!(github_id: 42001, installation_id: 88001, full_name: "browser-builder/website", html_url: "https://github.com/browser-builder/website")
      repository.scans.create!(status: "completed", progress: 100, created_at: 1.day.ago)
      scan = repository.scans.create!(status: "completed", progress: 100, base_sha: "a" * 40, pull_request_url: "https://github.com/browser-builder/website/pull/42",
        validation_results: [ { "name" => "HTML", "passed" => true } ])
      before = "<!doctype html>\n<html>\n<head>\n<title>Fortop</title>\n<meta name=\"description\" content=\"\">\n</head>\n</html>\n"
      after = before.sub('content=""', 'content="Fortop analiza y propone mejoras de SEO en tu repositorio."')
      finding = scan.findings.create!(title: "La página principal tiene una descripción vacía", description: "La plantilla compartida declara una meta description sin contenido. Las páginas que heredan este layout no proporcionan un resumen propio en esta etiqueta.",
        impact: "El buscador puede elegir un fragmento de otra parte del contenido. Este análisis de código no confirma qué fragmento se muestra actualmente.",
        remediation_rationale: "El cambio sustituye el valor vacío por un resumen basado en el contenido real. Así la etiqueta aporta contexto sobre la página sin prometer qué fragmento elegirá el buscador.",
        recommendation: "Completar la descripción con el propósito de Fortop, ya documentado en el repositorio, y mantener una única etiqueta en el HTML final.",
        verification: "Abrir la página renderizada y comprobar que existe una sola meta description, con texto no vacío y coherente con la página.",
        category: "metadata", severity: "medium", file_path: "app/views/layouts/application.html.erb", line_number: 5,
        evidence: '<meta name="description" content="">', status: "fixed", issue_url: "https://github.com/browser-builder/website/issues/21")
      delta = Scans::CodeDiff.call(before: before, after: after, path: finding.file_path)
      scan.update!(changed_files: [ delta.merge("path" => finding.file_path, "finding_ids" => [ finding.id ]) ])
      active_scan = repository.scans.create!(status: "queued")
      visit repository_path(repository, scan_id: scan.id)
      assert_no_selector ".finding-review[open]"
      assert_no_text "Qué hemos encontrado"
      find(".finding-review > summary").click
      within ".finding-review" do
        assert_text "Qué hemos encontrado"
        assert_text "Por qué afecta"
        assert_text "Por qué mejora esta remediación"
        assert_text finding.remediation_rationale
        assert_text "Cómo comprobarlo"
        assert_selector ".finding-evidence [data-code-highlighted='true']"
        assert_selector ".finding-evidence .syntax-highlight span[style*='rgb(86, 156, 214)']", text: "meta"
        assert_selector ".finding-evidence .syntax-highlight span[style*='rgb(156, 220, 254)']", text: "name"
        assert_selector ".finding-evidence .syntax-highlight span[style*='rgb(206, 145, 120)']", text: "description"
        assert_selector ".finding-source-line .finding-line-number", text: "5"
        assert_selector ".diff-deletion", text: 'content=""'
        assert_selector ".diff-addition", text: "Fortop analiza y propone mejoras de SEO"
        assert_selector ".finding-diff[data-code-highlighted='true']"
        assert_selector ".diff-addition .syntax-highlight span[style*='rgb(86, 156, 214)']", text: "meta"
        assert_link "Ver origen", href: "https://github.com/browser-builder/website/blob/#{'a' * 40}/app/views/layouts/application.html.erb#L5"
        assert_link "Revisar en el PR", href: scan.pull_request_url
      end
      assert_no_horizontal_overflow
      save_section_screenshot("finding-review-desktop", ".finding-review")
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      save_section_screenshot("finding-review-mobile", ".finding-review")
      active_scan.update!(status: "discovering")
      assert_selector ".repository-history .badge", text: "Preparando repositorio", visible: :all, wait: 10
      assert_selector ".finding-review[open] .finding-evidence [data-code-highlighted='true']"
      assert_selector ".finding-evidence .syntax-highlight span[style*='rgb(86, 156, 214)']", text: "meta"
      assert_selector ".finding-review[open] .finding-diff[data-code-highlighted='true']"
      find(".finding-review > summary").click
      assert_no_text "Qué hemos encontrado"
      assert_no_selector ".repository-history[open]"
    end
  end

  test "scan controls pause continue restart and cancel with live console scroll preserved" do
    with_browser_github do
      visit new_session_path
      click_button "Continuar con GitHub"
      assert_selector "h1", text: "Te damos la bienvenida"
      user = User.find_by!(github_id: 92001)
      repository = user.repositories.create!(github_id: 42001, installation_id: 88001, full_name: "browser-builder/website", html_url: "https://github.com/browser-builder/website")
      scan = repository.scans.create!(status: "analyzing", progress: 38, started_at: 1.minute.ago)
      45.times { |index| scan.record_event!("Leyendo plantilla #{index}.", kind: "tool") }
      visit repository_path(repository)
      assert_selector ".repository-console li", count: 45
      assert page.evaluate_script("(() => { const c = document.querySelector('[role=log]'); return c.scrollTop > 0 })()")
      page.execute_script("const c = document.querySelector('[role=log]'); c.scrollTop = 0; c.dispatchEvent(new Event('scroll'))")
      scan.record_event!("Buscando metadatos adicionales.", kind: "tool")
      assert_selector ".repository-console li", text: "Buscando metadatos adicionales.", visible: :all, wait: 10
      assert_equal 0, page.evaluate_script("document.querySelector('[role=log]').scrollTop")
      find("button[aria-label='Ir a las últimas acciones']").click
      assert page.evaluate_script("document.querySelector('[role=log]').scrollTop > 0")

      click_button "Pausar"
      assert_selector "h3", text: "Pausando el análisis…"
      assert_raises(Scans::Control::Halted) { Scans::Control.new(scan).check! { { "phase" => "analysis" } } }
      assert_selector "h3", text: "Análisis en pausa", wait: 10
      assert_button "Continuar"
      assert_no_button "Pausar"
      assert_button "Desconectar repositorio", disabled: true
      save_review_screenshot("scan-paused-desktop")
      assert_no_difference("Scan.count") do
        click_button "Continuar"
        assert_selector "h3", text: "En cola"
      end
      assert scan.reload.queued?
      accept_confirm { click_button "Reiniciar" }
      assert_selector "h3", text: "Reiniciando el análisis…"
      assert_raises(Scans::Control::Halted) { Scans::Control.new(scan).check! }
      replacement = repository.scans.active.sole
      assert_selector ".repository-selected-scan", text: "Análisis ##{replacement.id}", wait: 10
      assert_current_path repository_path(repository)
      assert_selector "h3", text: "En cola"
      assert_text "Historial de análisis"
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      assert_button "Pausar"
      save_review_screenshot("scan-controls-mobile")
      click_button "Cancelar"
      assert_selector "h3", text: "Cancelando el análisis…"
      assert_raises(Scans::Control::Halted) { Scans::Control.new(replacement).check! }
      assert_selector "h3", text: "Análisis cancelado", wait: 10
      assert_button "Nuevo análisis"
      assert_button "Desconectar repositorio", disabled: false
      assert_no_button "Continuar"
      assert_selector "[data-scan-progress-active-value='false']"
    end
  end

  test "agent activity shows readable actions and stays live without extra controls" do
    with_browser_github do
      visit new_session_path
      click_button "Continuar con GitHub"
      assert_selector "h1", text: "Te damos la bienvenida"
      user = User.find_by!(github_id: 92001)
      repository = user.repositories.create!(github_id: 42001, installation_id: 88001, full_name: "browser-builder/website", html_url: "https://github.com/browser-builder/website")
      scan = repository.scans.create!(status: "remediating", progress: 45, started_at: 1.minute.ago)
      scan.record_event!("Instantánea del repositorio preparada.")
      scan.record_event!("Análisis: explorando archivos.", kind: "tool", metadata: { agent: "analysis", tool: "list_files", turn: 1 })
      scan.record_event!("Análisis: leyendo código (app/layout.tsx).", kind: "tool", metadata: { agent: "analysis", tool: "read_file", path: "app/layout.tsx", turn: 2 })
      scan.record_event!("Análisis: contrastando referencias.", kind: "tool", metadata: { agent: "analysis", tool: "search", turn: 3 })
      finding = scan.findings.create!(title: "Descripción de la página ausente", description: "Falta una descripción específica.", category: "metadata", severity: "medium", evidence: "<head><title>Website</title></head>", automatable: true)
      scan.record_event!("Hallazgo: descripción de la página ausente.", kind: "finding", metadata: { finding_id: finding.id, severity: "medium" })
      scan.record_event!("Análisis: leyendo código (public/robots.txt).", kind: "tool", metadata: { agent: "analysis", tool: "read_file", path: "public/robots.txt", turn: 4 })
      scan.record_event!("Remediación: preparando una corrección (app/layout.tsx).", kind: "tool", metadata: { agent: "remediation", tool: "replace_text", path: "app/layout.tsx", turn: 1 })
      visit repository_path(repository)
      within ".repository-console" do
        assert_text "Actividad del agente"
        assert_text "En directo"
        assert_text "Explorando archivos."
        assert_text "Preparando una corrección"
        assert_selector ".activity-file", text: "app/layout.tsx", count: 2
        assert_selector ".agent-action", count: 7
        assert_no_selector ".console-toolbar, .console-current, .console-footer"
        assert_no_selector "input"
        assert_no_button "Copiar actividad"
        assert_no_button "Ampliar consola"
        assert_no_horizontal_overflow
      end
      save_section_screenshot("agent-workspace-desktop")

      scan.record_event!("Remediación: verificando app/layout.tsx.", kind: "tool", metadata: { agent: "remediation", tool: "validate_changes", path: "app/layout.tsx", turn: 2 })
      within ".repository-console" do
        assert_selector ".agent-action", count: 8, wait: 10
        assert_selector ".agent-action", text: "Verificando app/layout.tsx."
      end
      checks = [ { "name" => "scope", "passed" => true }, { "name" => "syntax:app/layout.tsx", "passed" => true } ]
      scan.update!(status: "publishing", progress: 88, changed_files: [ { "path" => "app/layout.tsx", "additions" => 3, "deletions" => 1 } ], validation_results: checks)
      scan.record_event!("Verificación final: 2 de 2 comprobaciones correctas.", kind: "validation", metadata: { checks: checks })
      scan.record_event!("Issue registrado: descripción de la página ausente.", kind: "publication", metadata: { issue_url: "https://github.com/browser-builder/website/issues/21" })
      within ".repository-console" do
        assert_selector ".agent-action", count: 10, wait: 10
        assert_text "Verificación final: 2 de 2 comprobaciones correctas."
        assert_link "Ver en GitHub", href: "https://github.com/browser-builder/website/issues/21"
      end
      save_section_screenshot("agent-workspace-publishing-desktop")
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      save_section_screenshot("agent-workspace-mobile")
      scan.update!(status: "paused")
      assert_selector ".repository-console[data-console-state=paused]", wait: 10
      within ".repository-console" do
        assert_text "En pausa"
        assert_selector ".agent-action", count: 10
      end
      assert_no_horizontal_overflow
    end
  end

  test "failed publication can be retried from its result screen and resume live progress" do
    with_browser_github do
      visit new_session_path
      click_button "Continuar con GitHub"
      assert_selector "h1", text: "Te damos la bienvenida"
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
      assert_no_text "Publicación recuperada."
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
      assert_selector "h1", text: "Te damos la bienvenida"
      user = User.find_by!(github_id: 92001)
      completed = user.repositories.create!(github_id: 42001, installation_id: 88001, full_name: "browser-builder/website", html_url: "https://github.com/browser-builder/website", language: "Ruby")
      completed.scans.create!(status: "completed", progress: 100, finished_at: Time.current)
      failed = user.repositories.create!(github_id: 42002, installation_id: 88001, full_name: "browser-builder/fortop-integration-check-ee2bda", html_url: "https://github.com/browser-builder/fortop-integration-check-ee2bda", language: "HTML")
      failed.scans.create!(status: "failed", progress: 88, error_message: "GitHub no responde.", finished_at: Time.current)

      visit repositories_path
      assert_selector "h1", text: "Repositorios"
      assert_no_selector ".workspace-welcome"
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
      assert_selector "h1", text: "Te damos la bienvenida"
      assert_current_path root_path
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

  def save_section_screenshot(name, selector = ".repository-console")
    return unless ENV["SYSTEM_SCREENSHOTS"] == "1"

    directory = Rails.root.join("tmp/screenshots")
    FileUtils.mkdir_p(directory)
    console = find(selector)
    page.execute_script("window.scrollTo({ top: window.scrollY + arguments[0].getBoundingClientRect().top - 80, behavior: 'instant' })", console)
    console.native.save_screenshot(directory.join("#{name}.png"))
  end

  def with_browser_github
    oauth = Object.new
    oauth.define_singleton_method(:authorize_url) do |state:, code_verifier:|
      "/auth/github/callback?#{URI.encode_www_form(code: 'system-test-code', state: state)}"
    end
    oauth.define_singleton_method(:exchange) { |**| { token: "ghu_browser_test_only", refresh_token: "ghr_browser_test_only", expires_at: 8.hours.from_now } }
    client = Object.new
    client.define_singleton_method(:user) { { "id" => 92001, "login" => "browser-builder", "name" => "Browser Builder" } }
    client.define_singleton_method(:installations) do |**|
      [ { "id" => 88001, "account" => { "login" => "browser-builder", "type" => "User" }, "repository_selection" => "selected" } ]
    end
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
