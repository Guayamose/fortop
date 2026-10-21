require "test_helper"
require_relative "../../support/visibility_fixtures"

class VisibilityEvidenceTest < ActiveSupport::TestCase
  include VisibilityFixtures

  test "quotes and entity boundaries prevent fabricated mentions and negative recommendations" do
    entity = { "key"=>"brand", "name"=>"Nébula", "website"=>"https://nebula.com", "aliases"=>[] }
    answer = "No recomiendo Nébula. La opción Nebulario es distinta."
    data = { "mentions"=>[ { "entity_key"=>"brand", "quote"=>"No recomiendo Nébula.", "certainty"=>"confirmed", "recommendation_quote"=>"No recomiendo Nébula.", "attributes"=>[ { "label"=>"Rápida", "quote"=>"Nébula es rápida" } ] }, { "entity_key"=>"invented", "quote"=>answer } ], "claims_to_review"=>[ { "quote"=>"Inventado", "source_indexes"=>[ 0 ] } ] }
    result = Visibility::Evidence.extract(data, answer: answer, entities: [ entity ], sources: [ {} ])
    assert_equal 1, result["mentions"].size
    assert_equal false, result["mentions"].first["recommended"]
    assert_empty result["mentions"].first["attributes"]
    assert_empty result["claims_to_review"]
    assert_not Visibility::Evidence.names_in?("Nebulario", entity)
    assert Visibility::Evidence.names_in?("NEBULA es útil", entity)
  end

  test "ambiguous and pending observations do not become absences and unresolved origins do not reduce citation rate" do
    study=complete_visibility(visibility_study)
    first=study.visibility_observations.find_by!(question_key: study.panel.first["key"], repetition: 1)
    first.update!(analysis: { "mentions"=>[ { "entity_key"=>"brand", "certainty"=>"uncertain" } ] })
    second=study.visibility_observations.find_by!(question_key: study.panel.second["key"], repetition: 1)
    second.update!(status: "answered")
    third=study.visibility_observations.find_by!(question_key: study.panel.third["key"], repetition: 1)
    third.update!(citations: [ { "url"=>"https://vertexaisearch.cloud.google.com/grounding-api-redirect/source", "resolved"=>false, "cited"=>true } ])
    summary=Visibility::Metrics.new(study).summary
    assert_equal 8, summary["valid"]
    assert_equal 1, summary["ambiguous"]
    assert_equal 100.0, summary["presence"]
    assert_equal 80.0, summary["coverage"]
    assert_equal 7, summary["citation_denominator"]
    assert_equal 100.0, summary["citation"]
  end

  test "an unresolved retrieved source without a supporting citation does not hide a verified own-domain citation" do
    study = complete_visibility(visibility_study)
    observation = study.visibility_observations.find_by!(question_key: study.panel.first["key"], repetition: 1)
    observation.update!(citations: observation.citations + [ { "url" => "https://vertexaisearch.cloud.google.com/grounding-api-redirect/unused", "resolved" => false, "cited" => false } ])
    summary = Visibility::Metrics.new(study).summary
    assert_equal 10, summary["citation_denominator"]
    assert_equal 10, summary["cited"]
    assert_equal 100.0, summary["citation"]
  end

  test "URL resolver never contacts an arbitrary destination or a private host" do
    %w[http://localhost/a http://127.0.0.1/a http://10.0.0.1 https://server.local javascript:alert(1) file:///etc/passwd https://u:p@public.com].each { |url| assert_nil Visibility::Urls.public_url(url) }
    assert_equal "https://nebula.com/a", Visibility::Urls.resolve("https://nebula.com/a", transport: ->(*) { flunk "No arbitrary fetch allowed" })
    locations=[]
    resolved=Visibility::Urls.resolve("https://vertexaisearch.cloud.google.com/grounding-api-redirect/test", transport: ->(uri) { locations<<uri.host; { "location"=>"http://127.0.0.1/secret" } })
    assert_nil resolved
    assert_equal [ "vertexaisearch.cloud.google.com" ], locations
    assert_not Visibility::Urls.same_domain?("https://evilnebula.com", "https://nebula.com")
  end
end
