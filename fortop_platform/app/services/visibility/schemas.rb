module Visibility
  module Schemas
    module_function
    def string; { type: "string" }; end
    def list(item = string); { type: "array", items: item }; end
    def object(properties); { type: "object", properties: properties, required: properties.keys }; end

    def profile
      object("business" => string, "value_proposition" => string, "audiences" => list, "products" => list,
        "needs" => list, "assumptions" => list, "summary" => string,
        "service_scope" => { type: "string", enum: %w[local regional national international online unknown] },
        "service_areas" => list, "buying_contexts" => list)
    end

    def research
      object("competitors" => list(object("name" => string, "website" => string, "aliases" => list, "kind" => { type: "string", enum: %w[direct alternative reference] }, "reason" => string, "markets" => list, "source_indexes" => list({ type: "integer" }))),
        "facts" => list(object("claim" => string, "source_indexes" => list({ type: "integer" }))),
        "public_identity" => object("status" => { type: "string", enum: %w[verified ambiguous insufficient_evidence] }, "summary" => string, "source_indexes" => list({ type: "integer" })),
        "market_summary" => string)
    end

    def panel
      object("questions" => list(object("slot" => { type: "integer" }, "text" => string,
        "intent" => { type: "string", enum: %w[discovery consideration decision] }, "topic" => string, "audience" => string, "rationale" => string)))
    end

    def panel_audit
      object("checks" => list(object("slot" => { type: "integer" }, "provider_seeking" => { type: "boolean" },
        "context_fit" => { type: "boolean" }, "neutral" => { type: "boolean" }, "brand_leak" => { type: "boolean" }, "reason" => string)))
    end

    def extraction
      object("brand_status" => { type: "string", enum: %w[present absent ambiguous] }, "brand_reason" => string,
        "brand_recognition" => { type: "string", enum: %w[identified name_only unknown ambiguous] }, "recognition_quote" => string,
        "answer_kind" => { type: "string", enum: %w[providers guidance insufficient_information] },
        "mentions" => list(object("entity_key" => string, "name" => string, "website" => string,
        "name_quote" => string, "quote" => string, "identity_reason" => string, "recommendation_quote" => string,
        "role" => { type: "string", enum: %w[recommended compared mentioned discouraged] },
        "sentiment" => { type: "string", enum: %w[positive neutral negative mixed] }, "certainty" => { type: "string", enum: %w[confirmed uncertain] },
        "attributes" => list(object("label" => string, "quote" => string)))),
        "claims_to_review" => list(object("quote" => string, "explanation" => string, "source_indexes" => list({ type: "integer" }))))
    end

    def diagnosis
      object("summary" => string, "insights" => list(object("title" => string, "description" => string, "observation_ids" => list({ type: "integer" }))),
        "actions" => list(object("title" => string, "description" => string, "kind" => { type: "string", enum: %w[technical editorial positioning] },
          "priority" => { type: "string", enum: %w[high medium low] }, "effort" => { type: "string", enum: %w[high medium low] }, "observation_ids" => list({ type: "integer" }))))
    end
  end
end
