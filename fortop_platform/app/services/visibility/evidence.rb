module Visibility
  module Evidence
    module_function

    def normalize(value)
      value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase
    end

    def names(entity)
      ([ entity["name"], Urls.domain(entity["website"]) ] + Array(entity["aliases"])).select { |name| name.is_a?(String) && name.present? }.uniq
    end

    def names_in?(text, entity)
      normalized = normalize(text)
      names(entity).any? { |name| normalized.match?(/(?<![\p{L}\p{N}])#{Regexp.escape(normalize(name))}(?![\p{L}\p{N}])/u) }
    end

    def quote?(answer, quote)
      quote.is_a?(String) && quote.length.between?(3, 3000) && answer.include?(quote)
    end

    def extract(data, answer:, entities:, sources:)
      mentions = Array(data["mentions"]).filter_map do |item|
        next unless item.is_a?(Hash) && (entity = entities.find { |entry| entry["key"] == item["entity_key"] })
        next unless quote?(answer, item["quote"]) && names_in?(item["quote"], entity)
        recommendation = item["recommendation_quote"]
        recommended = quote?(answer, recommendation) && names_in?(recommendation, entity) && !normalize(recommendation).match?(/\b(?:no recomiendo|no recomendamos|not recommend|do not|never|avoid|evita|ne recommande pas)\b/)
        attributes = Array(item["attributes"]).filter_map do |attribute|
          next unless attribute.is_a?(Hash) && quote?(answer, attribute["quote"]) && names_in?(attribute["quote"], entity)
          { "label" => attribute["label"].to_s.truncate(80), "quote" => attribute["quote"] }
        end
        { "entity_key" => entity["key"], "quote" => item["quote"], "certainty" => item["certainty"] == "confirmed" ? "confirmed" : "uncertain",
          "recommended" => !!recommended, "recommendation_quote" => recommended ? recommendation : nil,
          "sentiment" => %w[positive neutral negative mixed].include?(item["sentiment"]) ? item["sentiment"] : "neutral", "attributes" => attributes }
      end.uniq { |item| item["entity_key"] }
      reviews = Array(data["claims_to_review"]).filter_map do |item|
        next unless item.is_a?(Hash) && quote?(answer, item["quote"])
        indexes = Array(item["source_indexes"]).select { |index| index.is_a?(Integer) && index >= 0 && index < sources.size }
        next if indexes.empty?
        { "quote" => item["quote"], "explanation" => item["explanation"].to_s.truncate(1200), "source_indexes" => indexes }
      end
      { "mentions" => mentions, "claims_to_review" => reviews }
    end
  end
end
