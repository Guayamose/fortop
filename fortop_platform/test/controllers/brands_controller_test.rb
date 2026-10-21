require "test_helper"
require_relative "../support/github_sign_in"
require_relative "../support/visibility_fixtures"

class BrandsControllerTest < ActionDispatch::IntegrationTest
  include GithubSignIn
  include VisibilityFixtures
  include ActiveJob::TestHelper

  setup { @user=sign_in_github; @brand=visibility_brand(user: @user) }

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
end
