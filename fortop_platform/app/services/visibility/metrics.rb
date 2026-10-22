module Visibility
  class Metrics
    attr_reader :study, :questions, :observations, :filters

    def initialize(study, filters: {})
      @study = study
      @filters = filters.stringify_keys.slice("market", "language", "intent", "topic", "scope", "source", "lane")
      @filters["scope"] = "unbranded" unless %w[unbranded branded all].include?(@filters["scope"])
      @questions = study.panel.select do |question|
        %w[market language intent topic lane].all? { |key| @filters[key].blank? || question[key] == @filters[key] } &&
          (@filters["scope"] == "all" || (@filters["scope"] == "branded") == question["branded"])
      end
      @question_map = @questions.index_by { |question| question["key"] }
      @observations = study.visibility_observations.where(question_key: @question_map.keys).select(:id, :visibility_study_id, :question_key, :repetition, :status, :analysis, :citations, :model_version, :observed_at).to_a
      if @filters["source"].present?
        @observations.select! { |observation| observation.citations.any? { |source| source["domain"] == @filters["source"] && source["cited"] } }
      end
    end

    def valid
      @valid ||= observations.select { |observation| observation.status == "completed" && !ambiguous?(observation) }
    end

    def ambiguous?(observation, entity_key = "brand")
      (entity_key == "brand" && observation.analysis["brand_status"] == "ambiguous") ||
        observation.analysis.fetch("uncertain_entities", []).include?(entity_key) ||
        observation.analysis.fetch("mentions", []).any? { |mention| mention["entity_key"] == entity_key && mention["certainty"] == "uncertain" }
    end

    def mentions(observation, entity_key = "brand")
      observation.analysis.fetch("mentions", []).select { |item| item["entity_key"] == entity_key && item["certainty"] == "confirmed" }
    end

    def pct(numerator, denominator)
      denominator.positive? ? (100.0 * numerator / denominator).round(1) : nil
    end

    def summary
      @summary ||= begin
        present = valid.count { |observation| mentions(observation).any? }
        recommended = valid.count { |observation| mentions(observation).any? { |item| item["recommended"] } }
        resolved = if study.brand_brief.context["website"].present?
          valid.select { |observation| observation.citations.select { |source| source["cited"] }.all? { |source| source["resolved"] } }
        else
          []
        end
        cited = resolved.count { |observation| observation.citations.any? { |source| source["cited"] && Urls.same_domain?(source["canonical_url"], study.brand_brief.context["website"]) } }
        repeated = valid.group_by(&:question_key).values.select { |group| group.size >= 2 }
        stable = repeated.count { |group| group.map { |observation| mentions(observation).any? }.uniq.size == 1 }
        rounds = valid.group_by(&:repetition).values.filter_map { |group| pct(group.count { |observation| mentions(observation).any? }, group.size) }
        { "valid" => valid.size, "expected" => questions.size * study.settings.fetch("repetitions", 2), "failed" => observations.count { |observation| observation.status == "failed" },
          "ambiguous" => observations.count { |observation| observation.status == "completed" && ambiguous?(observation) },
          "present" => present, "presence" => pct(present, valid.size), "recommended" => recommended, "recommendation" => pct(recommended, valid.size),
          "cited" => cited, "citation_denominator" => resolved.size, "citation" => pct(cited, resolved.size), "stability" => pct(stable, repeated.size),
          "repeated_questions" => repeated.size, "round_range" => rounds.any? ? [ rounds.min, rounds.max ] : nil,
          "coverage" => pct(valid.size, questions.size * study.settings.fetch("repetitions", 2)),
          "provider_answers" => valid.count { |observation| observation.analysis["answer_kind"] == "providers" },
          "recognized" => valid.count { |observation| observation.analysis["brand_recognition"] == "identified" },
          "recognition" => pct(valid.count { |observation| observation.analysis["brand_recognition"] == "identified" }, valid.size),
          "no_provider_answers" => valid.count { |observation| %w[guidance insufficient_information].include?(observation.analysis["answer_kind"]) },
          "searched_answers" => valid.count { |observation| observation.citations.any? { |source| source["cited"] } } }
      end
    end

    def ranking
      entities = study.entities.reject { |entity| entity["kind"] == "reference" }
      eligible = entities.to_h { |entity| [ entity["key"], observations.select { |observation| observation.status == "completed" && !ambiguous?(observation, entity["key"]) } ] }
      counts = entities.to_h { |entity| [ entity["key"], eligible.fetch(entity["key"]).count { |observation| mentions(observation, entity["key"]).any? } ] }
      total = counts.values.sum
      entities.map do |entity|
        count = counts.fetch(entity["key"])
        sample = eligible.fetch(entity["key"])
        entity.merge("count" => count, "valid" => sample.size, "presence" => pct(count, sample.size), "share" => pct(count, total),
          "recommendation" => pct(sample.count { |observation| mentions(observation, entity["key"]).any? { |item| item["recommended"] } }, sample.size))
      end.sort_by { |entity| [ -entity["count"], entity["name"].to_s ] }
    end

    def lanes
      %w[category qualified brand].filter_map do |lane|
        next unless study.panel.any? { |question| question["lane"] == lane }
        metrics = self.class.new(study, filters: filters.merge("scope" => "all", "lane" => lane))
        metrics.summary.merge("lane" => lane)
      end
    end

    def emerging_providers
      data = {}
      valid.each do |observation|
        observation.analysis.fetch("mentions", []).select { |item| item["discovered"] && item["certainty"] == "confirmed" }.each do |mention|
          key = mention["entity_key"]
          data[key] ||= mention.slice("name", "website").merge("count" => 0, "observation_ids" => [])
          data[key]["count"] += 1
          data[key]["observation_ids"] << observation.id
        end
      end
      data.values.sort_by { |item| [ -item["count"], item["name"] ] }
    end

    def breakdown(key)
      questions.map { |question| question[key] }.uniq.map do |value|
        keys = questions.select { |question| question[key] == value }.pluck("key")
        group = valid.select { |observation| keys.include?(observation.question_key) }
        present = group.count { |observation| mentions(observation).any? }
        { "name" => value, "valid" => group.size, "present" => present, "presence" => pct(present, group.size) }
      end
    end

    def heatmap
      breakdown("market").map do |market|
        market.merge("cells" => %w[discovery consideration decision].map do |intent|
          keys = questions.select { |question| question["market"] == market["name"] && question["intent"] == intent }.pluck("key")
          group = valid.select { |observation| keys.include?(observation.question_key) }
          { "intent" => intent, "valid" => group.size, "presence" => pct(group.count { |observation| mentions(observation).any? }, group.size) }
        end)
      end
    end

    def question_rows
      questions.map do |question|
        group = valid.select { |observation| observation.question_key == question["key"] }
        present = group.count { |observation| mentions(observation).any? }
        question.merge("valid" => group.size, "present" => present, "presence" => pct(present, group.size),
          "competitors" => group.flat_map { |observation| observation.analysis.fetch("mentions", []).select { |item| item["entity_key"] != "brand" && item["certainty"] == "confirmed" }.filter_map { |item| item["name"] || study.entities.find { |entity| entity["key"] == item["entity_key"] }&.dig("name") } }.uniq,
          "observations" => observations.select { |observation| observation.question_key == question["key"] })
      end
    end

    def sources
      data = {}
      valid.each do |observation|
        observation.citations.select { |source| source["cited"] }.uniq { |source| source["canonical_url"].presence || source["url"] }.each do |source|
          key = source["canonical_url"].presence || source["url"]
          data[key] ||= source.merge("count" => 0, "observation_ids" => [], "brands" => [])
          data[key]["count"] += 1
          data[key]["observation_ids"] << observation.id
          data[key]["brands"] |= study.entities.select { |entity| mentions(observation, entity["key"]).any? }.pluck("name")
        end
      end
      data.values.sort_by { |source| -source["count"] }
    end

    def traits
      result = {}
      valid.each do |observation|
        mentions(observation).each do |mention|
          mention.fetch("attributes", []).uniq { |attribute| Evidence.normalize(attribute["label"]) }.each do |attribute|
            key = Evidence.normalize(attribute["label"])
            result[key] ||= { "label" => attribute["label"], "count" => 0, "evidence" => [] }
            result[key]["count"] += 1
            result[key]["evidence"] << { "observation_id" => observation.id, "quote" => attribute["quote"] }
          end
        end
      end
      result.values.sort_by { |trait| -trait["count"] }
    end

    def claims
      valid.flat_map { |observation| observation.analysis.fetch("claims_to_review", []).map { |claim| claim.merge("observation_id" => observation.id) } }
    end

    def comparable_history
      return [] if study.panel_fingerprint.blank? || filters.except("scope").values.any?(&:present?) || filters["scope"] != "unbranded"
      study.brand.visibility_studies.completed.where(panel_fingerprint: study.panel_fingerprint).order(:created_at).last(12).filter_map do |previous|
        next unless previous.report["model_versions"] == study.report["model_versions"]
        metrics = previous.report["metrics"]
        next unless metrics && metrics["coverage"] == 100.0
        { "id" => previous.id, "date" => previous.created_at, "presence" => metrics["presence"], "valid" => metrics["valid"] }
      end
    end
  end
end
