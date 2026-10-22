require "test_helper"
require_relative "../support/github_sign_in"
require_relative "../support/visibility_fixtures"

class BrandsControllerTest < ActionDispatch::IntegrationTest
  include GithubSignIn
  include VisibilityFixtures
  include ActiveJob::TestHelper

  setup { @user=sign_in_github; @brand=visibility_brand(user: @user) }

  test "deleting an owned brand removes its reports and brief versions" do
    study = complete_visibility(visibility_study(brand: @brand))
    @brand.update!(brief: "Software de facturación para nuevas empresas de España con soporte especializado.")
    get brand_path(@brand)
    assert_select "form[action='#{brand_path(@brand)}'][data-turbo-confirm]" do
      assert_select "input[name='_method'][value='delete']"
      assert_select "button", text: "Eliminar marca"
    end

    assert_difference("Brand.count", -1) { delete brand_path(@brand) }
    assert_response :see_other
    assert_redirected_to brands_path
    assert_not BrandBrief.exists?(brand_id: @brand.id)
    assert_not VisibilityStudy.exists?(id: study.id)
    [ VisibilityObservation, VisibilityEvent, VisibilityAction, VisibilityCall ].each do |model|
      assert_not model.exists?(visibility_study_id: study.id)
    end
    follow_redirect!
    assert_includes response.body, "Marca y estudios eliminados."
  end

  test "active and paused studies prevent deletion without removing any data" do
    study = visibility_study(brand: @brand)
    VisibilityStudy::ACTIVE_STATUSES.each do |status|
      study.update!(status: status)
      assert_no_difference([ "Brand.count", "BrandBrief.count", "VisibilityStudy.count", "VisibilityEvent.count" ]) do
        delete brand_path(@brand)
      end
      assert_redirected_to brand_path(@brand)
      assert_equal "Cancela el estudio en curso antes de eliminar la marca.", flash[:alert]
    end
    study.update!(status: "cancelled")
    assert_difference("Brand.count", -1) { delete brand_path(@brand) }
    assert_redirected_to brands_path
  end

  test "deleting brands requires authentication and ownership" do
    foreign = visibility_brand
    assert_no_difference("Brand.count") { delete brand_path(foreign) }
    assert_response :not_found
    delete logout_path
    assert_no_difference("Brand.count") { delete brand_path(@brand) }
    assert_redirected_to new_session_path
  end

  test "deleting a brand preserves source documents shared with another brand" do
    import = @user.brand_imports.create!
    document = import.documents.create!(extracted_text: "Contexto compartido de las marcas.")
    document.file.attach(io: StringIO.new("Contexto compartido de las marcas."), filename: "brief.txt", content_type: "text/plain")
    import.update!(status: "completed")
    @brand.update!(document_ids: [ document.id ])
    other = visibility_brand(user: @user)
    other.update!(document_ids: [ document.id ])
    assert_no_difference([ "BrandDocument.count", "ActiveStorage::Attachment.count" ]) { delete brand_path(@brand) }
    assert_redirected_to brands_path
    assert_equal [ other.id ], document.reload.brands.ids
    assert_equal [ other.current_brief.id ], document.brand_briefs.ids
    assert document.file.attached?
  end

  test "existing brands use their website icon without a monogram" do
    get brands_path
    assert_response :success
    assert_select ".brand-row .brand-logo img[src='https://www.google.com/s2/favicons?domain=nebula.com&sz=128']"
    assert_select ".brand-monogram", count: 0
    get brand_path(@brand)
    assert_select ".brand-profile-identity .brand-logo img[src*='domain=nebula.com']"
    @brand.update!(website: "")
    get brand_path(@brand)
    assert_select ".brand-logo img[src]", count: 0
    assert_select ".brand-logo-fallback .icon"
  end

  test "logos can be uploaded replaced and removed without changing the brief" do
    post brands_path, params: { brand: { name: "Marca con logo", brief: @brand.brief, markets_text: "España | es", logo: logo_upload } }
    brand = @user.brands.order(:id).last
    assert_redirected_to brand_path(brand)
    assert brand.logo.attached?
    get brands_path
    assert_select ".brand-row .brand-logo img[src='#{logo_brand_path(brand, v: brand.logo.blob.id)}']"
    get logo_brand_path(brand)
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal File.binread(Rails.root.join("public/icon.png")), response.body
    assert_match(/inline/, response.headers["Content-Disposition"])
    assert_match(/private.*no-store/, response.headers["Cache-Control"])
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]

    old_blob = brand.logo.blob.id
    brief = brand.current_brief
    assert_no_difference("BrandBrief.count") { patch brand_path(brand), params: { brand: { logo: logo_upload } } }
    assert_redirected_to brand_path(brand)
    assert_not_equal old_blob, brand.reload.logo.blob.id
    assert_equal brief.id, brand.current_brief.id

    # A validation error must not remove the saved logo.
    patch brand_path(brand), params: { brand: { name: "", remove_logo: "1" } }
    assert_response :unprocessable_entity
    assert brand.reload.logo.attached?
    assert_no_difference("BrandBrief.count") { patch brand_path(brand), params: { brand: { remove_logo: "1", logo: "" } } }
    assert_redirected_to brand_path(brand)
    assert_not brand.reload.logo.attached?
    get logo_brand_path(brand)
    assert_response :not_found
  end

  test "private logos cannot be read or attached by another owner" do
    foreign = visibility_brand
    File.open(Rails.root.join("public/icon.png")) do |file|
      foreign.logo.attach(io: file, filename: "logo.png", content_type: "image/png")
    end
    get logo_brand_path(foreign)
    assert_response :not_found
    assert_no_difference("ActiveStorage::Attachment.count") do
      patch brand_path(@brand), params: { brand: { logo: foreign.logo.blob.signed_id } }
    end
    assert_response :bad_request
    delete logout_path
    get logo_brand_path(foreign)
    assert_redirected_to new_session_path
  end

  test "brand creation editing and full persistent report render without new AI calls" do
    get brands_path
    assert_response :success
    assert_select "a[aria-current=page] .nav-label-full", text: "Visibilidad de marca"
    get brand_path(@brand)
    assert_response :success
    assert_select "button", text: "Iniciar estudio"
    study=complete_visibility(visibility_study(brand: @brand))
    count=study.visibility_calls.count
    get brand_path(@brand, study_id: study.id)
    assert_response :success
    assert_select "#overview"
    assert_select "#competition"
    assert_select "#actions"
    assert_select ".visibility-question", count: 5
    get brand_path(@brand, study_id: study.id, scope: "branded", format: :json)
    assert_response :success
    assert_includes response.parsed_body["html"], "¿Qué ofrece Nébula"
    assert_equal false, response.parsed_body["active"]
    assert_equal count, study.visibility_calls.count
    observation=study.visibility_observations.first
    get brand_visibility_study_observation_path(@brand, study, observation)
    assert_response :success
    assert_select "turbo-frame#visibility-evidence"
    assert_includes response.body, FakeVisibilityClient::ANSWER
    assert_select "iframe[sandbox='allow-popups allow-popups-to-escape-sandbox']"
    action=study.visibility_actions.first
    patch brand_visibility_study_action_path(@brand, study, action), params: { visibility_action: { status: "done" } }
    assert_equal "done", action.reload.status
  end

  test "brands can be created studied and edited without a website" do
    get new_brand_path
    assert_select "input[name='brand[website]'][required]", count: 0
    post brands_path, params: { brand: { name: "Marca sin web", brief: "Software de facturación para pequeños negocios de España, con soporte cercano y gestión de presupuestos.", markets_text: "España | es" } }
    brand = @user.brands.order(:id).last
    assert_redirected_to brand_path(brand)
    assert_equal "", brand.website
    study = complete_visibility(visibility_study(brand: brand))
    assert_nil Visibility::Metrics.new(study).summary["citation"]
    get brand_path(brand)
    assert_response :success
    assert_select ".brand-profile-heading h1", text: "Marca sin web"
    assert_select ".visibility-kpi small", text: "Sin sitio web indicado."
    get brands_path
    assert_response :success
    get edit_brand_path(brand)
    assert_select "input[name='brand[website]'][required]", count: 0
    patch brand_path(brand), params: { brand: { website: " " } }
    assert_redirected_to brand_path(brand)
    assert_equal "", brand.reload.website
  end

  test "start queues work and pause cancel recovery controls are owner scoped" do
    assert_enqueued_with(job: VisibilityStudyJob) { post brand_visibility_studies_path(@brand), params: { question_count: 6, repetitions: 2, budget_usd: 2 } }
    study=@brand.visibility_studies.first
    assert_redirected_to brand_path(@brand, study_id: study.id)
    post pause_brand_visibility_study_path(@brand, study)
    VisibilityStudyJob.perform_now(study.id)
    assert study.reload.paused?
    post resume_brand_visibility_study_path(@brand, study), params: { budget_usd: 4 }
    assert study.reload.queued?
    assert_equal 4, study.budget_usd
    post cancel_brand_visibility_study_path(@brand, study)
    VisibilityStudyJob.perform_now(study.id)
    assert study.reload.cancelled?
  end

  test "other owners cannot read reports observations actions or hand off to an unrelated repository" do
    foreign=visibility_brand
    study=complete_visibility(visibility_study(brand: foreign))
    get brand_path(foreign)
    assert_response :not_found
    get brand_visibility_study_observation_path(foreign, study, study.visibility_observations.first)
    assert_response :not_found
    patch brand_visibility_study_action_path(foreign, study, study.visibility_actions.first), params: { visibility_action: { status: "done" } }
    assert_response :not_found
    mine=complete_visibility(visibility_study(brand: @brand))
    repo=connected_repository(foreign.user)
    assert_no_difference("Scan.count") { post handoff_brand_visibility_study_action_path(@brand, mine, mine.visibility_actions.first), params: { repository_id: repo.id } }
    assert_response :not_found
  end

  test "technical handoff is idempotent and carries evidence into an owned repository scan" do
    study=complete_visibility(visibility_study(brand: @brand))
    action=study.visibility_actions.first
    repo=connected_repository(@user)
    assert_difference("Scan.count", 1) { post handoff_brand_visibility_study_action_path(@brand, study, action), params: { repository_id: repo.id } }
    assert_equal study.id, action.reload.scan.metadata.dig("visibility_context", "study_id")
    assert_equal action.observation_ids, action.scan.metadata.dig("visibility_context", "observation_ids")
    assert_no_difference("Scan.count") { post handoff_brand_visibility_study_action_path(@brand, study, action), params: { repository_id: repo.id } }
    assert_equal "in_progress", action.reload.status
  end

  test "model supplied markup is escaped in the report and evidence" do
    study=complete_visibility(visibility_study(brand: @brand))
    study.update!(report: study.report.merge("summary"=>"<script>alert(1)</script>"))
    observation=study.visibility_observations.first
    observation.update!(answer: "<img src=x onerror=alert(1)>")
    get brand_path(@brand)
    assert_select "#overview script", count: 0
    assert_includes response.body, "&lt;script&gt;"
    get brand_visibility_study_observation_path(@brand, study, observation)
    assert_select ".visibility-answer-text img", count: 0
    assert_includes response.body, "&lt;img"
  end

  private

  def logo_upload
    Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png")
  end
end
