module Visibility
  module Schemas
    module_function
    def string; { type: "string" }; end
    def list(item = string); { type: "array", items: item }; end
    def object(properties); { type: "object", properties: properties, required: properties.keys }; end

    def profile
      object("business" => string, "value_proposition" => string, "audiences" => list, "products" => list,
        "needs" => list, "assumptions" => list, "summary" => string)
    end

    def research
      object("competitors" => list(object("name" => string, "website" => string, "aliases" => list, "kind" => { type: "string", enum: %w[direct alternative reference] }, "reason" => string, "markets" => list, "source_indexes" => list({ type: "integer" }))),
        "facts" => list(object("claim" => string, "source_indexes" => list({ type: "integer" }))),
        "market_summary" => string)
    end

    def panel
      object("questions" => list(object("text" => string, "intent" => { type: "string", enum: %w[discovery consideration decision] }, "topic" => string, "audience" => string, "branded" => { type: "boolean" })))
    end

    def extraction
      object("mentions" => list(object("entity_key" => string, "quote" => string, "recommendation_quote" => string,
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
