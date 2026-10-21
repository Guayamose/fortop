require "application_system_test_case"

class RepositoryFlowTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  test "GitHub sign in connects a repository starts agents and receives completion through live polling" do
    with_browser_github do
      visit new_session_path
      assert_text "Todo empieza"
      click_button "Continuar con GitHub"
      assert_selector "h1", text: "Repositorios"
      assert_text "Tu primer repositorio"
      assert_no_selector ".repository-card"
      assert_no_horizontal_overflow

      click_link "Conectar un repositorio"
      assert_selector ".picker-repo-copy strong", text: "browser-builder/website"
      click_button "Conectar", exact: true
      assert_selector "h1", text: "website"
      assert_text "El primer análisis está por llegar."

      assert_enqueued_with(job: ScanJob) do
        click_button "Iniciar análisis y remediación"
        assert_selector "h1", text: /Análisis #/
      end
      assert_text "En cola"
      assert_no_selector ".scan-state-symbol.is-complete"
      scan = User.find_by!(github_id: 92001).repositories.find_by!(github_id: 42001).scans.last
      assert scan.queued?

      scan.update!(status: "analyzing", progress: 38, started_at: Time.current)
      scan.record_event!("El agente de análisis está revisando las plantillas.", kind: "tool")
      assert_selector "[role=progressbar][aria-valuenow='38']", wait: 10
      assert_text "El agente de análisis está revisando las plantillas."

      scan.update!(status: "completed", progress: 100, summary: "El agente ha revisado la estructura y documentado una oportunidad de mejora.", finished_at: Time.current)
      scan.findings.create!(title: "Revisar descripción de la página", description: "La plantilla no define una descripción específica.", severity: "medium", category: "metadata", evidence: "La plantilla revisada no contiene meta description.", status: "manual", automatable: false,
        issue_url: "https://github.com/browser-builder/website/issues/11")
      scan.record_event!("Ejecución completada. El diagnóstico ya está disponible.")

      # No navigation or reload: Stimulus fetches the real JSON endpoint and
      # replaces the progress with the terminal summary rendered by Rails.
      assert_text "Análisis completado", wait: 10
      assert_selector ".scan-state-symbol.is-complete"
      assert_selector "[role=progressbar][aria-valuenow='100']"
      assert_text "El agente ha revisado la estructura y documentado una oportunidad de mejora."
      assert_text "No se ha creado un pull request."
      assert_text "Revisión manual"
      assert_selector "[data-scan-progress-active-value='false']"
      assert_no_horizontal_overflow
      save_review_screenshot("scan-completed-desktop")
      find(".finding-card summary").click
      assert_link "Ver issue en GitHub", href: "https://github.com/browser-builder/website/issues/11"

      page.current_window.resize_to(390, 844)
      assert_selector "h1", text: /Análisis #/
      assert_no_horizontal_overflow
      save_review_screenshot("scan-completed-mobile")
      click_link "browser-builder/website", exact: true
      assert_selector "h1", text: "website"
      assert_text "Historial de análisis"
      assert_no_horizontal_overflow
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
