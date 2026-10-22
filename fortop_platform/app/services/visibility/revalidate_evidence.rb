module Visibility
  # Replay saved extraction data only: no provider, new answer, job or charge.
  # Final diagnoses require a separate regeneration, so don't silently change
  # their measurements underneath existing written conclusions.
  class RevalidateEvidence
    def initialize(study)
      @study = study
    end

    def call(apply: false)
      @study.with_lock do
        raise Error, "Detén el estudio antes de revalidar sus evidencias." if @study.work_pending?
        raise Error, "Este estudio tiene un diagnóstico final; requiere regenerarlo junto con sus métricas." if apply && @study.report.present?
        result = { "study_id" => @study.id, "changed" => [], "skipped" => [], "before_present" => 0, "after_present" => 0 }
        @study.visibility_observations.where(status: "completed").order(:id).each do |observation|
          result["before_present"] += 1 if observation.analysis["brand_status"] == "present"
          key = "extract:#{observation.id}"
          call = @study.visibility_calls.where(task_key: key, status: "succeeded").order(attempt: :desc).first
          unless call
            result["skipped"] << observation.id
            result["after_present"] += 1 if observation.analysis["brand_status"] == "present"
            next
          end
          data = JSON.parse(call.response_text)
          analysis = Evidence.extract(data, answer: observation.answer, entities: @study.entities, sources: @study.research_sources)
          repair = @study.visibility_calls.where(task_key: "#{key}:repair:#{Evidence::VERSION}", status: "succeeded").order(attempt: :desc).first
          if repair
            repaired = Evidence.extract(JSON.parse(repair.response_text), answer: observation.answer, entities: @study.entities, sources: @study.research_sources)
            analysis = Extraction.preferred(analysis, repaired)
          end
          result["after_present"] += 1 if analysis["brand_status"] == "present"
          next if observation.analysis == analysis
          result["changed"] << observation.id
          observation.update!(analysis: analysis) if apply
        end
        if apply && result["changed"].any?
          @study.record_event!("Evidencias guardadas revalidadas: #{result['changed'].size} respuestas; #{result['after_present']} identifican la marca. Sin nuevas consultas a Google.", kind: "validation", metadata: result.merge("evidence_version" => Evidence::VERSION))
        end
        result
      end
    end
  end
end
