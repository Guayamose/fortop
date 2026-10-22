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

  test "brand deletion asks for confirmation and works on mobile" do
    with_browser_github do
      sign_in
      brand = visibility_brand(user: User.find_by!(github_id: 93001))
      visit brand_path(brand)
      assert_button "Eliminar marca"
      dismiss_confirm(/¿Eliminar Nébula\?/) { click_button "Eliminar marca" }
      assert_current_path brand_path(brand)
      assert Brand.exists?(brand.id)
      screenshot("visibility-delete-desktop")
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      screenshot("visibility-delete-mobile")
      accept_confirm(/todos sus estudios e informes/) { click_button "Eliminar marca" }
      assert_current_path brands_path
      assert_text "Marca y estudios eliminados."
      assert_not Brand.exists?(brand.id)
    end
  end

  test "brand logos preview persist and can return to the automatic website icon" do
    with_browser_github do
      sign_in
      visit new_brand_path
      fill_in "Nombre de la marca", with: "Marca con logo"
      fill_in "Brief de la marca", with: "Software de facturación sencillo para pequeñas empresas de España, con soporte cercano y gestión de presupuestos."
      attach_file "brand_logo", Rails.root.join("public/icon.png"), make_visible: true
      assert_selector ".brand-logo img[src^='blob:']", visible: true
      assert_text "icon.png · Se guardará con la marca."
      screenshot("visibility-logo-form")
      click_button "Crear marca", exact: true
      assert_text "Descubre dónde estás hoy."
      brand = User.find_by!(github_id: 93001).brands.last
      assert_selector ".brand-profile-identity .brand-logo img[src^='/brands/#{brand.id}/logo']", visible: true
      visit brands_path
      assert_selector ".brand-row .brand-logo img[src^='/brands/#{brand.id}/logo']", visible: true
      screenshot("visibility-logo-list")

      click_link "Marca con logo"
      click_link "Editar brief"
      click_button "Quitar logo"
      assert_no_selector ".brand-logo img", visible: true
      fill_in "Sitio web", with: "nebula.com"
      assert_selector ".brand-logo img[src*='domain=nebula.com']", visible: :all
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      page.execute_script("document.querySelector('.brand-logo-editor').scrollIntoView({behavior: 'instant', block: 'center'})")
      screenshot("visibility-logo-form-mobile", scroll: false)
      click_button "Guardar nueva versión"
      assert_text "Descubre dónde estás hoy."
      assert_not brand.reload.logo.attached?
      assert_selector ".brand-profile-identity .brand-logo img[src*='domain=nebula.com']", visible: :all
      # A failed network image uses the unboxed fallback rather than a broken image.
      page.execute_script("document.querySelector('.brand-logo img').src = 'data:image/png;base64,broken'")
      assert_selector ".brand-logo-fallback .icon", visible: true
      assert_no_selector ".brand-logo img", visible: true
    end
  end

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
      assert_selector ".visibility-discovery-lanes article", count: 3
      assert_no_horizontal_overflow
      screenshot("visibility-report-desktop")
      page.execute_script("document.querySelector('.visibility-discovery').scrollIntoView({behavior: 'instant', block: 'center'})")
      screenshot("visibility-discovery-desktop", scroll: false)
      select "Para tu cliente y tu zona", from: "lane"
      assert_selector ".visibility-question", count: 4
      select "Todos", from: "lane"
      assert_selector ".visibility-question", count: 5
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
      page.execute_script("document.querySelector('.visibility-discovery').scrollIntoView({behavior: 'instant', block: 'start'})")
      screenshot("visibility-discovery-mobile", scroll: false)
      find("a[href='#markets']").click
      page.execute_script("document.getElementById('markets').scrollIntoView({behavior: 'instant'})")
      assert_no_horizontal_overflow
      screenshot("visibility-markets-mobile", scroll: false)
    end
  end

  test "dropping documents autocompletes the brief preserves edits and keeps versioned context" do
    with_browser_github do
      sign_in
      visit new_brand_path
      text = "Nébula ofrece software de facturación para pequeñas empresas de España. Su web es https://nebula.com. Compite con Contalia."
      page.execute_script(<<~JS, text)
        const transfer = new DataTransfer()
        transfer.items.add(new File([arguments[0]], "dossier-marca.md", {type: "text/markdown"}))
        document.querySelector('.brand-dropzone').dispatchEvent(new DragEvent('drop', {bubbles: true, cancelable: true, dataTransfer: transfer}))
      JS
      assert_text "Documentos recibidos. Preparando la lectura…"
      fill_in "Nombre de la marca", with: "Nombre elegido mientras se lee"
      import = User.find_by!(github_id: 93001).brand_imports.last
      BrandImportJob.perform_now(import.id)
      assert_field "Sitio web", with: "https://nebula.com", wait: 10
      assert_field "Nombre de la marca", with: "Nombre elegido mientras se lee"
      assert_field "Brief de la marca", with: /Software de facturación/
      assert_selector ".brand-document", text: "dossier-marca.md"
      assert_selector "input[name='brand[document_ids][]'][value='#{import.documents.sole.id}']", visible: :all
      assert_button "Crear marca", disabled: false
      assert_button "Deshacer autocompletado"
      assert_no_horizontal_overflow
      screenshot("visibility-import-desktop")
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      screenshot("visibility-import-mobile")
      fill_in "Nombre de la marca", with: "Nébula"
      click_button "Crear marca", exact: true
      assert_text "Descubre dónde estás hoy."
      brand = User.find_by!(github_id: 93001).brands.last
      original = brand.current_brief
      assert_equal [ import.documents.sole.id ], original.documents.ids
      click_link "Editar brief"
      assert_selector ".brand-document", text: "dossier-marca.md"
      find("button[aria-label='Quitar dossier-marca.md del contexto']").click
      click_button "Guardar nueva versión"
      assert_text "Descubre dónde estás hoy."
      assert_empty brand.reload.documents
      assert_equal [ import.documents.sole.id ], original.reload.documents.ids
      assert_empty brand.current_brief.documents
    end
  end

  test "study controls pause resume and cancel through the real forms" do
    with_browser_github do
      sign_in
      brand=visibility_brand(user: User.find_by!(github_id: 93001))
      study=visibility_study(brand: brand)
      study.update!(status: "researching", stage: "researching")
      45.times { |index| study.record_event!("Contrastando la fuente #{index} del mercado.", kind: "research") }
      visit brand_path(brand)
      within ".agent-activity" do
        assert_text "Actividad del agente"
        assert_text "En directo"
        assert_no_selector ".console-toolbar, .console-current, .console-footer"
        assert_no_button "Copiar actividad"
        assert_no_button "Ampliar consola"
        assert_selector ".agent-action", count: 46
      end
      assert page.evaluate_script("document.querySelector('.activity-output').scrollTop > 0")
      page.execute_script("const output = document.querySelector('.activity-output'); output.scrollTop = 0; output.dispatchEvent(new Event('scroll'))")
      study.record_event!("Competidor contrastado con una fuente independiente.", kind: "research")
      assert_selector ".agent-action", text: "Competidor contrastado con una fuente independiente.", visible: :all, wait: 10
      assert_equal 0, page.evaluate_script("document.querySelector('.activity-output').scrollTop")
      find("button[aria-label='Ir a las últimas acciones']").click
      assert page.evaluate_script("document.querySelector('.activity-output').scrollTop > 0")
      screenshot("visibility-agent-desktop")
      click_button "Pausar", exact: true
      assert_text "Terminando la tarea en curso…"
      VisibilityStudyJob.perform_now(study.id)
      assert_text "Estudio en pausa.", wait: 10
      assert_selector ".agent-activity[data-console-state='paused']"
      page.current_window.resize_to(390, 844)
      assert_no_horizontal_overflow
      screenshot("visibility-agent-mobile")
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
    assert_selector "h1", text: "Te damos la bienvenida"
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
    GithubAccessGrant.find_or_create_by!(github_id: 93001) { |grant| grant.login = "brand-builder" }
    oauth=Object.new
    oauth.define_singleton_method(:authorize_url) { |state:, code_verifier:| "/auth/github/callback?#{URI.encode_www_form(code: 'visibility-test', state: state)}" }
    oauth.define_singleton_method(:exchange) { |**| { token: "ghu_test_only", refresh_token: "ghr_test_only", expires_at: 8.hours.from_now } }
    client=Object.new
    client.define_singleton_method(:user) { { "id"=>93001, "login"=>"brand-builder", "name"=>"Brand Builder" } }
    Visibility::GoogleClient.stub(:new, FakeVisibilityClient.new) do
      Github::App.stub(:configured?, true) do
        Github::OAuth.stub(:new, oauth) { Github::Client.stub(:new, client) { yield } }
      end
    end
  end
end
