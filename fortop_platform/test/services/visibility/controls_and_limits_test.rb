require "test_helper"
require_relative "../../support/visibility_fixtures"

class VisibilityControlsAndLimitsTest < ActiveSupport::TestCase
  include VisibilityFixtures

  test "the daily user budget covers all brands and commits a pause without contacting Google" do
    first=visibility_study
    second=visibility_study(brand: visibility_brand(user: first.brand.user))
    limit=BigDecimal(ENV.fetch("VISIBILITY_DAILY_BUDGET_USD", "10"))
    first.visibility_calls.create!(task_key: "existing-paid-call", model: "gemini-test", status: "failed", cost_usd: limit, attempt: 1)
    client=FakeVisibilityClient.new
    assert_raises(Visibility::Halted) { Visibility::Pipeline.new(second, client: client).step }
    assert second.reload.paused?
    assert_match(/diario/, second.pause_reason)
    assert_empty client.requests
    assert_equal 0, second.request_count
  end

  test "request and token limits stop before a paid call and preserve partial data" do
    study=visibility_study
    study.update!(settings: study.settings.merge("max_tokens"=>10))
    client=FakeVisibilityClient.new
    Visibility::Pipeline.new(study, client: client).step
    assert study.reload.failed?
    assert_empty client.requests
    assert_equal 0, study.request_count
    assert_match(/límite/, study.error_message)
  end

  test "scope that cannot fit request limits is rejected before starting" do
    brand=visibility_brand
    brand.update!(markets_text: "España | es\nMéxico | es\nChile | es\nColombia | es\nPerú | es\nArgentina | es\nUruguay | es\nEcuador | es")
    assert_no_difference("VisibilityStudy.count") do
      assert_raises(Visibility::Error) { Visibility::Studies.create!(brand, question_count: 50, repetitions: 5) }
    end
  end

  test "a failed evaluation recovers a saved answer without buying it again" do
    study=visibility_study
    client=FakeVisibilityClient.new
    12.times do
      break if study.visibility_observations.where(status: "answered").exists?
      Visibility::Pipeline.new(study.reload, client: client, resolver: ->(url) { url }).step
    end
    observation=study.visibility_observations.find_by!(status: "answered")
    client.failure=Visibility::ProviderError.new("Configuración temporalmente inválida.")
    Visibility::Pipeline.new(study, client: client).step
    assert study.reload.failed?
    assert_equal "answered", observation.reload.status
    Visibility::Studies.control!(study, "retry")
    client.failure=nil
    complete_visibility(study, client: client)
    assert_equal 1, study.visibility_calls.where(task_key: "answer:#{observation.question_key}:#{observation.repetition}").count
  end

  test "history excludes a different returned model version and reused competitors retain their source provenance" do
    first=complete_visibility(visibility_study)
    original_source=first.competitors.first["sources"].first
    second=Visibility::Studies.create!(first.brand, question_count: 6, repetitions: 2, reuse_id: first.id)
    complete_visibility(second)
    assert_equal original_source, second.competitors.first["sources"].first
    second.update!(report: second.report.merge("model_versions"=>[ "different-version" ]))
    assert_equal [ second.id ], Visibility::Metrics.new(second).comparable_history.pluck("id")
    first.brand.update!(brief: "Ahora solo vendemos a asesorías fiscales con equipos grandes y necesidades de integración avanzada.")
    assert_raises(Visibility::Error) { Visibility::Studies.create!(first.brand, reuse_id: first.id) }
  end
end
