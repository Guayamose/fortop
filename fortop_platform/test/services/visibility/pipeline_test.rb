require "test_helper"
require_relative "../../support/visibility_fixtures"

class VisibilityPipelineTest < ActiveSupport::TestCase
  include VisibilityFixtures

  test "complete study persists provenance exact prompts verified evidence and code calculated metrics" do
    study = visibility_study
    client = FakeVisibilityClient.new
    complete_visibility(study, client: client)
    assert_equal 12, study.visibility_observations.where(status: "completed").count
    assert_equal 6, study.panel.size
    assert_equal 100.0, study.report.dig("metrics", "presence")
    assert_equal 10, study.report.dig("metrics", "valid"), "Branded questions must be excluded by default"
    assert_equal 1, study.visibility_actions.count
    assert study.visibility_calls.all? { |call| call.status == "succeeded" && call.input_prompt.present? && call.system_instruction.present? }
    assert study.visibility_observations.all? { |observation| observation.citations.first["resolved"] && observation.observed_at.present? }
    assert study.spent_usd.positive?
    assert_operator study.spent_usd, :<, study.budget_usd
    assert_equal study.visibility_calls.sum(:cost_usd), study.spent_usd
    answers = client.requests.select { |request| request[:grounded] && !request[:prompt].start_with?("Search the public web") }
    assert_equal 12, answers.size
    unbranded = answers.reject { |request| request[:prompt].include?("Nébula") }
    assert_equal 10, unbranded.size
    unbranded.each do |request|
      assert_no_match(/Nébula|nebula\.com|Contalia|facturación sencilla|brief/, request[:system])
      assert_no_match(/Contalia|brief|ENTITIES/, request[:prompt])
    end
    assert_equal 12, study.visibility_calls.where("task_key LIKE 'answer:%'").count
    assert_no_difference("VisibilityCall.count") { VisibilityStudyJob.perform_now(study.id) }
  end

  test "pause and cancellation preserve paid answers and do not construct a provider" do
    study = visibility_study
    client = FakeVisibilityClient.new
    pipeline = Visibility::Pipeline.new(study, client: client, resolver: ->(url) { url })
    12.times do
      break if study.visibility_observations.where(status: "answered").exists?
      pipeline.step
    end
    study.update!(control_action: "pause")
    Visibility::GoogleClient.stub(:new, ->(*) { flunk "Stopping requires no provider" }) { VisibilityStudyJob.perform_now(study.id) }
    assert study.reload.paused?
    count = client.requests.size
    assert_raises(Visibility::Halted) { pipeline.step }
    assert_equal count, client.requests.size
    Visibility::Studies.control!(study, "resume")
    complete_visibility(study, client: client)
    assert_equal 12, study.visibility_calls.where("task_key LIKE 'answer:%'").where(status: "succeeded").count
    second = visibility_study(brand: study.brand)
    second.update!(control_action: "cancel")
    VisibilityStudyJob.perform_now(second.id)
    assert second.reload.cancelled?
    assert_equal 0, second.request_count
  end

  test "budget pause commits before another request and an increased budget resumes cached work" do
    study = visibility_study(budget_usd: 0.02)
    client = FakeVisibilityClient.new
    pipeline = Visibility::Pipeline.new(study, client: client)
    pipeline.step
    assert_equal "researching", study.reload.stage
    assert_raises(Visibility::Halted) { pipeline.step }
    assert study.reload.paused?, "Pause must survive the transaction"
    assert_equal 1, client.requests.size
    assert_match(/presupuesto/, study.pause_reason)
    Visibility::Studies.control!(study, "resume", budget_usd: 3)
    complete_visibility(study, client: client)
    assert_equal 1, study.visibility_calls.where(task_key: "interpret").count
  end

  test "informational questions fail independent review before buying any measured answers" do
    study = visibility_study
    client = FakeVisibilityClient.new
    client.informational_panel = true
    5.times { Visibility::Pipeline.new(study.reload, client: client).step }
    assert study.reload.failed?
    assert_match(/instrucciones para facturar/, study.error_message)
    assert_equal 2, study.visibility_calls.where("task_key LIKE 'panel-audit:%'").count
    assert_empty study.visibility_observations
    assert_empty study.visibility_calls.where("task_key LIKE 'answer:%'")
  end

  test "category qualified discovery and prompted recognition keep separate denominators" do
    study = complete_visibility(visibility_study)
    assert_equal({ "category" => 1, "qualified" => 4, "brand" => 1 }, study.panel.group_by { |question| question["lane"] }.transform_values(&:size))
    category_key = study.panel.find { |question| question["lane"] == "category" }.fetch("key")
    study.visibility_observations.where(question_key: category_key).each do |observation|
      observation.update!(analysis: { "brand_status" => "absent", "brand_reason" => "Solo da consejos genéricos.", "answer_kind" => "guidance", "mentions" => [] })
    end
    metrics = Visibility::Metrics.new(study)
    lanes = metrics.lanes.index_by { |lane| lane["lane"] }
    assert_equal 0.0, lanes["category"]["presence"]
    assert_equal 100.0, lanes["qualified"]["presence"]
    assert_equal 100.0, lanes["brand"]["presence"]
    assert_equal 80.0, metrics.summary["presence"], "Generic answers stay in the denominator"
    assert_equal 2, metrics.summary["no_provider_answers"]
    assert_equal 8, metrics.summary["provider_answers"]
  end

  test "transient failures retry up to three times and manual recovery preserves the ledger" do
    study = visibility_study
    client = FakeVisibilityClient.new
    client.failure = Visibility::ProviderError.new("Cuota temporal.", retryable: true)
    pipeline = Visibility::Pipeline.new(study, client: client)
    2.times { assert_raises(Visibility::RetryLater) { pipeline.step } }
    pipeline.step
    assert study.reload.failed?
    assert_equal 3, study.visibility_calls.count
    assert_equal 3, study.request_count
    reserved_cost = study.spent_usd
    assert reserved_cost.positive?
    Visibility::Studies.control!(study, "retry")
    client.failure = nil
    pipeline.step
    assert_equal "researching", study.reload.stage
    assert_equal 4, study.visibility_calls.count
    assert_operator study.spent_usd, :>, reserved_cost
  end

  test "invalid planning can be corrected on recovery rather than replaying a bad cached response" do
    study = visibility_study
    client = FakeVisibilityClient.new
    client.invalid_panel = true
    5.times { Visibility::Pipeline.new(study.reload, client: client).step }
    assert study.reload.failed?
    assert_equal 2, study.visibility_calls.where("task_key LIKE 'plan:%'").count
    Visibility::Studies.control!(study, "retry")
    client.invalid_panel = false
    complete_visibility(study, client: client)
    assert_equal 3, study.visibility_calls.where("task_key LIKE 'plan:%'").count
  end

  test "same panel collects new answers and comparable history is persistent" do
    study = complete_visibility(visibility_study)
    next_study = Visibility::Studies.create!(study.brand, question_count: 6, repetitions: 2, reuse_id: study.id)
    complete_visibility(next_study)
    assert_equal study.panel_fingerprint, next_study.panel_fingerprint
    assert_equal study.panel, next_study.panel
    assert_equal 12, next_study.visibility_calls.where("task_key LIKE 'answer:%'").count
    assert_equal [ study.id, next_study.id ], Visibility::Metrics.new(next_study).comparable_history.pluck("id")
    assert_empty Visibility::Metrics.new(next_study, filters: { market: "España" }).comparable_history
    assert_equal 2, study.brand.visibility_studies.count
  end
end
