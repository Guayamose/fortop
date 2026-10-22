require "test_helper"
require_relative "../../support/visibility_fixtures"

class VisibilityEvidenceTest < ActiveSupport::TestCase
  include VisibilityFixtures

  test "quotes and entity boundaries prevent fabricated mentions and negative recommendations" do
    entity = { "key"=>"brand", "name"=>"Nébula", "website"=>"https://nebula.com", "aliases"=>[] }
    answer = "No recomiendo Nébula. La opción Nebulario es distinta."
    data = { "brand_status" => "present", "brand_reason" => "Se menciona explícitamente la marca, con una valoración negativa.", "answer_kind" => "providers",
      "mentions"=>[ { "entity_key"=>"brand", "name" => "Nébula", "name_quote" => "Nébula", "identity_reason" => "El nombre identifica la marca.", "role" => "discouraged", "sentiment" => "negative", "quote"=>"No recomiendo Nébula.", "certainty"=>"confirmed", "recommendation_quote"=>"No recomiendo Nébula.", "attributes"=>[ { "label"=>"Rápida", "quote"=>"Nébula es rápida" } ] }, { "entity_key"=>"invented", "quote"=>answer } ], "claims_to_review"=>[ { "quote"=>"Inventado", "source_indexes"=>[ 0 ] } ] }
    result = Visibility::Evidence.extract(data, answer: answer, entities: [ entity ], sources: [ {} ])
    assert_equal 1, result["mentions"].size
    assert_equal false, result["mentions"].first["recommended"]
    assert_empty result["mentions"].first["attributes"]
    assert_empty result["claims_to_review"]
    assert_not Visibility::Evidence.names_in?("Nebulario", entity)
    assert Visibility::Evidence.names_in?("NEBULA es útil", entity)
  end

  test "semantic identity accepts a supported naming variant and attributes in the following sentence" do
    entity = { "key" => "brand", "name" => "Clínica Brisa", "website" => "https://brisasalud.es", "aliases" => [] }
    answer = "Brisa Salud atiende en Getafe. Ofrece fisioterapia deportiva y la recomiendo por su atención. Otra opción es Centro Sur."
    context = "Brisa Salud atiende en Getafe. Ofrece fisioterapia deportiva y la recomiendo por su atención."
    item = { "entity_key" => "brand", "name" => "Brisa Salud", "website" => "https://brisasalud.es", "name_quote" => "Brisa Salud", "quote" => context,
      "identity_reason" => "Mismo dominio, actividad sanitaria y ubicación declarada en Getafe.", "certainty" => "confirmed", "role" => "recommended", "sentiment" => "positive",
      "recommendation_quote" => "la recomiendo por su atención", "attributes" => [ { "label" => "Fisioterapia deportiva", "quote" => "Ofrece fisioterapia deportiva" }, { "label" => "Otra empresa", "quote" => "Centro Sur" } ] }
    data = { "brand_status" => "present", "brand_reason" => "La respuesta utiliza el nombre comercial y el dominio de la clínica.", "answer_kind" => "providers", "mentions" => [ item ] }
    result = Visibility::Evidence.extract(data, answer: answer, entities: [ entity ], sources: [])
    refute Visibility::Evidence.names_in?(context, entity), "Identity is not decided by matching the canonical name"
    assert_equal "present", result["brand_status"]
    assert result["mentions"].first["recommended"]
    assert_equal [ "Fisioterapia deportiva" ], result["mentions"].first["attributes"].pluck("label")
  end

  test "missing or rejected identity evidence is ambiguous and never a measured absence" do
    entity = { "key" => "brand", "name" => "Brisa", "website" => "https://brisasalud.es" }
    item = { "entity_key" => "brand", "name" => "Brisa", "name_quote" => "Brisa", "quote" => "Brisa es una clínica.", "identity_reason" => "Una supuesta mención.", "certainty" => "confirmed" }
    data = { "brand_status" => "present", "brand_reason" => "Supuestamente identificada.", "answer_kind" => "providers", "mentions" => [ item ] }
    result = Visibility::Evidence.extract(data, answer: "Hay varios centros en Getafe.", entities: [ entity ], sources: [])
    assert_empty result["mentions"]
    assert_equal "ambiguous", result["brand_status"]
    assert_equal [ "brand" ], result["uncertain_entities"]
    assert_equal "insufficient_information", result["answer_kind"]
    item.merge!("quote" => "Brisa es una clínica.", "website" => "https://otra-brisa.com")
    result = Visibility::Evidence.extract(data, answer: item["quote"], entities: [ entity ], sources: [])
    assert_equal "uncertain", result["mentions"].first["certainty"]
    assert_equal "ambiguous", result["brand_status"]
  end

  test "providers outside the tracked panel retain literal evidence" do
    answer = "Recomiendo Taller Norte para reparar tu bicicleta en Getafe."
    data = { "brand_status" => "absent", "brand_reason" => "La marca objetivo no aparece.", "answer_kind" => "providers",
      "mentions" => [ { "entity_key" => "", "name" => "Taller Norte", "name_quote" => "Taller Norte", "website" => "", "quote" => answer, "identity_reason" => "Es un taller identificado en la respuesta.", "certainty" => "confirmed", "role" => "recommended", "sentiment" => "positive", "recommendation_quote" => answer } ] }
    result = Visibility::Evidence.extract(data, answer: answer, entities: [ { "key" => "brand", "name" => "Bici Sur" } ], sources: [])
    assert_equal "absent", result["brand_status"]
    assert result["mentions"].first["discovered"]
    assert_equal "Taller Norte", result["mentions"].first["name"]
  end

  test "repeating a prompted brand name is not recognition of the business" do
    answer = "No tengo información sobre Librería Brisa. Consulta directorios de tu zona."
    data = { "brand_status" => "present", "brand_reason" => "Solo repite el nombre sin identificar el negocio.", "brand_recognition" => "name_only", "recognition_quote" => "",
      "answer_kind" => "insufficient_information", "mentions" => [ { "entity_key" => "brand", "name" => "Librería Brisa", "name_quote" => "Librería Brisa", "quote" => answer, "identity_reason" => "Se refiere al nombre de la pregunta, sin más datos.", "certainty" => "confirmed", "role" => "mentioned", "sentiment" => "neutral" } ] }
    result = Visibility::Evidence.extract(data, answer: answer, entities: [ { "key" => "brand", "name" => "Librería Brisa" } ], sources: [])
    assert_equal "present", result["brand_status"]
    assert_equal "name_only", result["brand_recognition"]
    assert_nil result["recognition_quote"]
    refute result["mentions"].first["recommended"]
    data.merge!("brand_recognition" => "identified", "recognition_quote" => "Es una librería especializada en libros infantiles")
    assert_equal "unknown", Visibility::Evidence.extract(data, answer: answer, entities: [ { "key" => "brand", "name" => "Librería Brisa" } ], sources: [])["brand_recognition"]
  end

  test "an ambiguous competitor does not remove a valid brand observation" do
    study = complete_visibility(visibility_study)
    observation = study.visibility_observations.first
    competitor = study.entities.second
    observation.update!(analysis: observation.analysis.merge("mentions" => observation.analysis["mentions"] + [ { "entity_key" => competitor["key"], "certainty" => "uncertain" } ]))
    metrics = Visibility::Metrics.new(study)
    assert_equal 10, metrics.summary["valid"]
    assert_equal 9, metrics.ranking.find { |entity| entity["key"] == competitor["key"] }["valid"]
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
