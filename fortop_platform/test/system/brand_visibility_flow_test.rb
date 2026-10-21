require "application_system_test_case"
require_relative "../support/visibility_fixtures"

class BrandVisibilityFlowTest < ApplicationSystemTestCase
  include VisibilityFixtures

  setup do
    @previous_forgery_protection=ApplicationController.allow_forgery_protection
    ApplicationController.allow_forgery_protection=true
    page.current_window.resize_to(1440, 1000)
  end

  teardown { ApplicationController.allow_forgery_protection=@previous_forgery_protection }

  test "create a brand run a study and explore persistent evidence with filters on desktop and mobile" do
    with_browser_github do
      sign_in
      find(".main-nav a[href='#{brands_path}']").click
      assert_text "Empieza por contar tu historia."
      screenshot("visibility-empty")
      click_link "Crear mi primera marca"
      fill_in "Nombre de la marca", with: "Nébula"
      fill_in "Sitio web", with: "https://nebula.com"
      fill_in "Brief de la marca", with: "Software de facturación sencillo para pequeñas empresas de España, con soporte cercano y gestión de presupuestos."
      screenshot("visibility-brief")
      click_button "Crear marca", exact: true
      assert_text "Descubre dónde estás hoy."
      screenshot("visibility-ready")
      click_button "Iniciar estudio"
      assert_text "En cola"
      brand=User.find_by!(github_id: 93001).brands.first
      study=brand.visibility_studies.first
      # A small deterministic test panel replaces the paid provider, never production data.
      study.update!(settings: study.settings.merge("question_count"=>6))
      complete_visibility(study)
      assert_selector "#overview", wait: 10
      assert_text "Quién ocupa las respuestas."
      assert_selector ".visibility-question", count: 5
      assert_no_horizontal_overflow
      screenshot("visibility-report-desktop")
      find("#questions .visibility-question summary", match: :first).click
      within all(".visibility-question").first do
        click_link "Ver respuesta", match: :first
      end
      assert_selector "dialog[open]"
      within "dialog" do
        assert_text FakeVisibilityClient::ANSWER
        assert_text "Nébula · producto"
        assert_no_selector "script"
      end
      screenshot("visibility-evidence")
      find("button[aria-label='Cerrar evidencia']").click
      assert_no_selector "dialog[open]"
      select "Con marca", from: "scope"
      assert_selector ".visibility-question", count: 1
      assert_text "Este panel pregunta expresamente por marcas."
      assert_equal 1, brand.visibility_studies.count
      calls=study.visibility_calls.count
      visit brand_path(brand, study_id: study.id)
      assert_selector ".visibility-question", count: 5
      assert_equal calls, study.visibility_calls.count
      within ".visibility-action", match: :first do
        select "Completada", from: "Estado"
        click_button "Guardar"
      end
      assert_text "Acción actualizada."
      assert_equal "done", study.visibility_actions.first.reload.status
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      screenshot("visibility-report-mobile")
      find("a[href='#markets']").click
      page.execute_script("document.getElementById('markets').scrollIntoView({behavior: 'instant'})")
      assert_no_horizontal_overflow
      screenshot("visibility-markets-mobile", scroll: false)
    end
  end

  test "study controls pause resume and cancel through the real forms" do
    with_browser_github do
      sign_in
      brand=visibility_brand(user: User.find_by!(github_id: 93001))
      study=visibility_study(brand: brand)
      visit brand_path(brand)
      click_button "Pausar", exact: true
      assert_text "Terminando la tarea en curso…"
      VisibilityStudyJob.perform_now(study.id)
      assert_text "Estudio en pausa.", wait: 10
      assert_button "Continuar"
      fill_in "Presupuesto total USD", with: "4"
      click_button "Continuar"
      assert_button "Pausar"
      assert_equal BigDecimal("4"), study.reload.budget_usd
      accept_confirm { click_button "Cancelar", exact: true }
      assert_text "Terminando la tarea en curso…"
      VisibilityStudyJob.perform_now(study.id)
      assert_text "Cancelado", wait: 10
      assert_button "Iniciar estudio"
      assert_equal 0, study.reload.request_count
    end
  end

  private

  def sign_in
    visit new_session_path
    click_button "Continuar con GitHub"
    assert_selector "h1", text: "Repositorios"
  end

  def assert_no_horizontal_overflow
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1"), "Brand page should fit viewport"
  end

  def screenshot(name, scroll: true)
    return unless ENV["SYSTEM_SCREENSHOTS"]=="1"
    FileUtils.mkdir_p(Rails.root.join("tmp/screenshots"))
    page.execute_script("window.scrollTo(0,0)") if scroll
    page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png"))
  end

  def with_browser_github
    oauth=Object.new
    oauth.define_singleton_method(:authorize_url) { |state:, code_verifier:| "/auth/github/callback?#{URI.encode_www_form(code: 'visibility-test', state: state)}" }
    oauth.define_singleton_method(:exchange) { |**| { token: "ghu_test_only", refresh_token: "ghr_test_only", expires_at: 8.hours.from_now } }
    client=Object.new
    client.define_singleton_method(:user) { { "id"=>93001, "login"=>"brand-builder", "name"=>"Brand Builder" } }
    Visibility::GoogleClient.stub(:new, FakeVisibilityClient.new) do
      Github::OAuth.stub(:new, oauth) { Github::Client.stub(:new, client) { yield } }
    end
  end
end
