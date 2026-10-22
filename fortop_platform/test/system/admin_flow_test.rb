require "application_system_test_case"
require_relative "../support/visibility_fixtures"

class AdminFlowTest < ApplicationSystemTestCase
  include VisibilityFixtures
  setup do
    @previous_csrf = ApplicationController.allow_forgery_protection
    ApplicationController.allow_forgery_protection = true
    page.current_window.resize_to(1440, 1000)
  end

  teardown { ApplicationController.allow_forgery_protection = @previous_csrf }

  test "owner manages access and operational settings on desktop and mobile" do
    visitor = User.create!(github_id: 4455, login: "another-builder", github_token: "test-private")
    repository = visitor.repositories.create!(github_id: 8899, full_name: "another-builder/a-long-repository-name-for-responsive-layouts", default_branch: "main", html_url: "https://github.com/another-builder/a-long-repository-name-for-responsive-layouts", language: "Ruby")
    scan = repository.scans.create!(status: "failed", error_message: "El ejecutor se ha interrumpido.", metadata: { "usage" => { "total_tokens" => 450, "requests" => 2 } })
    scan.record_event!("Se han revisado los metadatos del sitio.")
    brand = visibility_brand(user: visitor)
    study = visibility_study(brand: brand)
    study.update!(status: "completed", spent_usd: "0.25", token_count: 500, request_count: 2)
    import = visitor.brand_imports.create!(status: "failed", retryable: true, error_message: "El archivo no se pudo interpretar.")
    with_owner_github do
      visit new_session_path
      click_button "Continuar con GitHub"
      assert_selector "h1", text: "Te damos la bienvenida"
      find("summary[aria-label='Menú de cuenta']").click
      click_link "Administración"
      assert_selector "h1", text: "Tu centro de control."
      assert_text "Acceso exclusivo · @Guayamose"
      assert_no_horizontal_overflow
      save_review_screenshot("admin-desktop")
      within ".admin-nav" do
        click_link "Accesos"
      end
      fill_in "Nombre de usuario en GitHub", with: "invited-user"
      click_button "Autorizar cuenta"
      assert_text "@invited-user ya puede iniciar sesión."
      assert_selector ".admin-table strong", text: "@invited-user"
      assert_equal 778899, GithubAccessGrant.find_by!(login: "invited-user").github_id
      save_review_screenshot("admin-access-desktop")
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      assert_button "Autorizar cuenta"
      save_review_screenshot("admin-access-mobile")
      within ".admin-nav" do
        click_link "Configuración"
      end
      assert_selector "h1", text: "Configuración."
      assert_no_horizontal_overflow
      select "Pausadas", from: "Permitir nuevas ejecuciones"
      fill_in "Tokens por análisis · 0 sin límite", with: "600000"
      accept_confirm { click_button "Guardar configuración" }
      assert_text "Configuración guardada."
      assert_equal "600000", PlatformSetting.fetch("AGENT_MAX_TOTAL_TOKENS")
      refute PlatformSetting.new_work_enabled?
      assert_no_horizontal_overflow
      save_review_screenshot("admin-settings-mobile")
      within ".admin-nav" do
        click_link "Accesos"
      end
      accept_confirm { click_button "Retirar acceso" }
      assert_text "Acceso retirado a @invited-user."
      refute GithubAccessGrant.exists?(github_id: 778899)
      within ".admin-nav" do
        click_link "Registro"
      end
      assert_text "Acceso autorizado"
      assert_text "Configuración actualizada"
      assert_text "Acceso retirado"
      assert_no_horizontal_overflow
      page.current_window.resize_to(1440, 1000)
      save_review_screenshot("admin-audit-desktop")
      page.current_window.resize_to(390, 844)
      [ admin_root_path, admin_users_path, admin_user_path(visitor), admin_repositories_path, admin_repository_path(repository),
        admin_brands_path, admin_brand_path(brand), admin_activity_path,
        admin_activity_entry_path(kind: "scans", id: scan.id), admin_activity_entry_path(kind: "studies", id: study.id),
        admin_activity_entry_path(kind: "imports", id: import.id) ].each do |path|
        visit path
        assert_selector ".admin-heading h1"
        assert_no_horizontal_overflow
      end
    end
  end

  private

  def with_owner_github
    oauth = Object.new
    oauth.define_singleton_method(:authorize_url) { |state:, **| "/auth/github/callback?code=test-code&state=#{state}" }
    oauth.define_singleton_method(:exchange) { |**| { token: "ghu_browser_test", refresh_token: "ghr_browser_test", expires_at: 8.hours.from_now } }
    client = Object.new
    client.define_singleton_method(:user) { { "id" => User::OWNER_GITHUB_ID, "login" => "Guayamose", "name" => "Rafael" } }
    client.define_singleton_method(:account) { |login| { "id" => 778899, "login" => login, "type" => "User" } }
    Github::App.stub(:configured?, true) do
      Github::OAuth.stub(:new, oauth) do
        Github::Access.stub(:user_client, client) do
          Github::Client.stub(:new, client) { yield }
        end
      end
    end
  end

  def assert_no_horizontal_overflow
    fits = page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth + 1")
    unless fits
      details = page.evaluate_script("Array.from(document.querySelectorAll('body *')).filter(el => el.getBoundingClientRect().right > innerWidth + 1 && getComputedStyle(el).position !== 'fixed').slice(0, 15).map(el => [el.tagName, el.className, el.getAttribute('name'), el.getAttribute('type'), el.parentElement.className, el.getBoundingClientRect().left, el.getBoundingClientRect().width])")
    end
    assert fits, "The page overflows horizontally: #{details.inspect}"
  end

  def save_review_screenshot(name)
    path = Rails.root.join("tmp/screenshots/#{name}.png")
    FileUtils.mkdir_p(path.dirname)
    page.save_screenshot(path)
  end
end
