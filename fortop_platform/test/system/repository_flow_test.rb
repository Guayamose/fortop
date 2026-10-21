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
      assert_text "Tu primer repositorio"
      assert_no_text "Has iniciado sesión con GitHub."
      assert_no_selector ".repository-card"
      assert_no_horizontal_overflow
      save_review_screenshot("repositories-empty-desktop")

      click_link "Conectar un repositorio"
      assert_selector ".picker-repo-copy strong", text: "browser-builder/website"
      save_review_screenshot("repository-picker-desktop")
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

  test "agent workspace filters searches expands and copies real activity across live updates" do
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
        assert_text "Agente de análisis"
        assert_text "Agente de remediación"
        assert_selector ".console-file-tsx"
        assert_selector ".console-current-copy strong", text: "Dando forma a las mejoras"
        assert_selector "[data-console-event]", count: 7
        assert_no_horizontal_overflow
      end
      save_console_screenshot("agent-workspace-desktop")

      within ".repository-console" do
        click_button "Hallazgos", exact: true
        assert_selector "[data-console-event]", count: 1
        assert_text "descripción de la página ausente"
        assert_no_selector "[data-category=code]"
        click_button "GitHub", exact: true
        assert_text "No hay acciones que coincidan."
        click_button "Limpiar filtros"
        click_button "Código", exact: true
        find("input[aria-label='Buscar actividad']").set("layout.tsx")
        assert_selector "[data-console-event]", count: 2
        find("button[aria-label='Ampliar consola']").click
        assert_selector "button[aria-label='Reducir consola']"
      end

      scan.record_event!("Remediación: verificando app/layout.tsx.", kind: "tool", metadata: { agent: "remediation", tool: "validate_changes", path: "app/layout.tsx", turn: 2 })
      within ".repository-console" do
        assert_selector "[data-console-event]", count: 3, wait: 10
        assert_equal "layout.tsx", find("input[aria-label='Buscar actividad']").value
        assert_selector "button[data-filter=code][aria-pressed=true]"
        assert_selector "button[aria-label='Reducir consola']"
        assert_selector ".console-event.is-arriving", text: "Verificando app/layout.tsx."

        # Exercise the clipboard action without changing the system clipboard.
        page.execute_script("window.consoleCopiedActivity = null; Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async (text) => { window.consoleCopiedActivity = text } } })")
        find("button[aria-label='Copiar actividad']").click
        assert_text "Actividad copiada"
        copied = page.evaluate_script("window.consoleCopiedActivity")
        assert_includes copied, "app/layout.tsx"
        refute_includes copied, "public/robots.txt"
        refute_includes copied, "descripción de la página ausente"

        find("input[aria-label='Buscar actividad']").set("")
        click_button "Todo", exact: false
        find("button[aria-label='Reducir consola']").click
      end
      checks = [ { "name" => "scope", "passed" => true }, { "name" => "syntax:app/layout.tsx", "passed" => true } ]
      scan.update!(status: "publishing", progress: 88, changed_files: [ { "path" => "app/layout.tsx", "additions" => 3, "deletions" => 1 } ], validation_results: checks)
      scan.record_event!("Verificación final: 2 de 2 comprobaciones correctas.", kind: "validation", metadata: { checks: checks })
      scan.record_event!("Issue registrado: descripción de la página ausente.", kind: "publication", metadata: { issue_url: "https://github.com/browser-builder/website/issues/21" })
      within ".repository-console" do
        assert_selector ".console-current-copy strong", text: "Llevando el trabajo a GitHub", wait: 10
        assert_selector ".console-file-diff", text: "+3"
        assert_selector ".console-check-result.is-success", text: "2/2 comprobaciones"
        click_button "GitHub", exact: true
        assert_selector "[data-console-event]", count: 1
        assert_link "Ver en GitHub", href: "https://github.com/browser-builder/website/issues/21"
        click_button "Todo", exact: false
      end
      save_console_screenshot("agent-workspace-publishing-desktop")
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      save_console_screenshot("agent-workspace-mobile")
      refute_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.console-art-spark')).animationName")
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
      assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.console-art-spark')).animationName")
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
      scan.update!(status: "paused")
      assert_selector ".repository-console[data-console-state=paused]", wait: 10
      assert_selector ".console-current-copy strong", text: "Lo dejamos justo aquí"
      assert_no_selector ".console-thinking-dots"
      assert_no_horizontal_overflow

      assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.console-art-spark')).animationName")
    ensure
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
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
      assert_selector "h1", text: "Te damos la bienvenida"
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
      assert_selector "h1", text: "Te damos la bienvenida"
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

  def save_console_screenshot(name)
    return unless ENV["SYSTEM_SCREENSHOTS"] == "1"

    directory = Rails.root.join("tmp/screenshots")
    FileUtils.mkdir_p(directory)
    console = find(".repository-console")
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
