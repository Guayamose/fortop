require "test_helper"
require_relative "../../support/visibility_fixtures"

class VisibilityExtractionTest < ActiveSupport::TestCase
  include VisibilityFixtures

  def setup
    @study = visibility_study
    @study.update!(entities: [ { "key" => "brand", "name" => "Nébula" } ], panel: [ { "key" => "q1", "text" => "¿Qué proveedores hay?" } ])
    @observation = @study.visibility_observations.create!(question_key: "q1", repetition: 1, status: "answered", answer: "**Nebula:** Ofrece facturación sencilla.")
  end

  def extraction(quote)
    { "brand_status" => "present", "brand_reason" => "Mismo negocio de facturación.", "brand_recognition" => "identified", "recognition_quote" => "Ofrece facturación sencilla.", "answer_kind" => "providers",
      "mentions" => [ { "entity_key" => "brand", "name" => "Nébula", "name_quote" => "Nebula", "quote" => quote, "identity_reason" => "La actividad y el contexto identifican el negocio.", "certainty" => "confirmed", "role" => "mentioned", "sentiment" => "neutral" } ], "claims_to_review" => [] }
  end

  def gateway(*responses)
    @keys = []
    keys, test_case = @keys, self
    handler = ->(key, **options) do
      keys << key
      test_case.assert_includes options[:prompt], "surface form"
      raise "Unexpected additional request" if responses.empty?
      value = responses.shift
      raise value if value.is_a?(Exception)
      value
    end
    Object.new.tap { |object| object.define_singleton_method(:json, &handler) }
  end

  test "valid formatting variants do not buy an extra extraction" do
    result = Visibility::Extraction.new(@study, @observation, gateway: gateway(extraction("Nebula: Ofrece facturación sencilla."))).call
    assert_equal "present", result["brand_status"]
    assert_equal [ "extract:#{@observation.id}" ], @keys
  end

  test "unanchored evidence gets one corrective extraction without requesting a new answer" do
    result = Visibility::Extraction.new(@study, @observation, gateway: gateway(extraction("Nebula es una plataforma barata."), extraction("Nebula: Ofrece facturación sencilla."))).call
    assert_equal "present", result["brand_status"]
    assert_empty result["evidence_issues"]
    assert_equal [ "extract:#{@observation.id}", "extract:#{@observation.id}:repair:#{Visibility::Evidence::VERSION}" ], @keys
  end

  test "repeated invalid evidence remains unverified and is not retried indefinitely" do
    bad = extraction("Nebula es una plataforma barata.")
    result = Visibility::Extraction.new(@study, @observation, gateway: gateway(bad, bad)).call
    assert_equal 2, @keys.size
    assert_equal "ambiguous", result["brand_status"]
    assert_equal "unverified", result["answer_kind"]
    assert result["evidence_issues"].any?
  end

  test "dropping the disputed brand cannot turn invalid extraction into measured absence" do
    absent = extraction("").merge("brand_status" => "absent", "mentions" => [])
    result = Visibility::Extraction.new(@study, @observation, gateway: gateway(extraction("Nebula es barata."), absent)).call
    assert_equal "ambiguous", result["brand_status"]
  end

  test "a failed corrective request preserves the original reviewable result" do
    result = Visibility::Extraction.new(@study, @observation, gateway: gateway(extraction("Nebula es barata."), Visibility::Error.new("Respuesta no válida"))).call
    assert_equal "ambiguous", result["brand_status"]
    assert_equal "Respuesta no válida", result["evidence_repair_error"]
  end

  test "saved evidence can be previewed and repaired without resuming or charging a cancelled study" do
    @study.update!(status: "cancelled")
    @observation.update!(status: "completed", analysis: { "brand_status" => "ambiguous", "mentions" => [] })
    @study.visibility_calls.create!(task_key: "extract:#{@observation.id}", model: "fixture", status: "succeeded", response_text: JSON.generate(extraction("Nebula: Ofrece facturación sencilla.")))
    revalidator = Visibility::RevalidateEvidence.new(@study)
    preview = revalidator.call
    assert_equal 1, preview["after_present"]
    assert_equal "ambiguous", @observation.reload.analysis["brand_status"]
    assert_no_difference([ "VisibilityCall.count", "@study.reload.request_count", "@study.reload.spent_usd" ]) do
      revalidator.call(apply: true)
      assert_empty revalidator.call(apply: true)["changed"]
    end
    assert_equal "present", @observation.reload.analysis["brand_status"]
    assert @study.reload.cancelled?
  end

  test "revalidation does not race a running study or invalidate an existing final diagnosis" do
    assert_raises(Visibility::Error) { Visibility::RevalidateEvidence.new(@study).call(apply: true) }
    @study.update!(status: "completed", report: { "summary" => "Diagnóstico anterior." })
    assert_raises(Visibility::Error) { Visibility::RevalidateEvidence.new(@study).call(apply: true) }
  end
end
