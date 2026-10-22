module Visibility
  class Extraction
    def initialize(study, observation, gateway:)
      @study, @observation, @gateway = study, observation, gateway
    end

    def call
      original = evaluate(@gateway.json(key, system: Pipeline::SYSTEM, schema: Schemas.extraction, prompt: prompt))
      return original if original["evidence_issues"].empty?

      # One corrective extraction, never another search/answer. Both requests
      # use the persisted ledger, budget checks and normal transient retries.
      repaired = evaluate(@gateway.json("#{key}:repair:#{Evidence::VERSION}", system: Pipeline::SYSTEM, schema: Schemas.extraction, prompt: <<~PROMPT))
        #{prompt}
        A prior extraction could not anchor some providers in the answer. Re-extract the complete answer once.
        Copy the actual visible name (including short names/typos), and enough contiguous context to contain it.
        Do not omit parenthetical domains, dates or qualifiers inside that passage. If necessary, use a shorter exact passage containing the name.
        Recognition, attributes and recommendations need their own evidence inside the selected passage; leave them empty if unsupported.
        Keep every supported provider. Do not omit a provider just to remove a validation error.
        Do not paraphrase, join disjoint sentences, drop negations, borrow another provider's context, or invent a canonical spelling in a quote.
        VALIDATION ISSUES: #{JSON.generate(original["evidence_issues"])}
      PROMPT
      self.class.preferred(original, repaired)
    rescue Error => error
      raise unless original
      @study.record_event!("La revisión adicional de una evidencia no se ha completado. Se conservan las menciones verificadas y se señalan las pendientes.", kind: "warning", metadata: { observation_id: @observation.id })
      original.merge("evidence_repair_error" => error.message)
    end

    def self.preferred(original, repaired)
      retained = original["mentions"].select { |m| m["certainty"] == "confirmed" }.pluck("entity_key")
      corrected = repaired["mentions"].select { |m| m["certainty"] == "confirmed" }.pluck("entity_key")
      return original unless (retained - corrected).empty?
      return original if original["brand_status"] == "ambiguous" && repaired["brand_status"] == "absent"
      repaired["evidence_issues"].size < original["evidence_issues"].size ? repaired : original
    end

    private

    def key
      "extract:#{@observation.id}"
    end

    def prompt
      @prompt ||= Evidence.prompt(answer: @observation.answer, question: @observation.question.fetch("text"), entities: @study.entities,
        facts: @study.profile.fetch("facts", []), sources: @study.research_sources,
        business: @study.profile.slice("business", "audiences", "products", "service_scope", "service_areas"))
    end

    def evaluate(data)
      Evidence.extract(data, answer: @observation.answer, entities: @study.entities, sources: @study.research_sources)
    end
  end
end
