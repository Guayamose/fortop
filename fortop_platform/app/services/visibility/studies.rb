module Visibility
  module Studies
    module_function

    def create!(brand, question_count: 12, repetitions: 2, budget_usd: 3, reuse_id: nil)
      brand.with_lock do
        active = brand.visibility_studies.active.first
        return active if active
        settings = Settings.build(question_count: question_count, repetitions: repetitions)
        previous = brand.visibility_studies.completed.find(reuse_id) if reuse_id.present?
        if previous && (previous.brand_brief_id != brand.current_brief.id || previous.settings.values_at("model", "method_version") != settings.values_at("model", "method_version"))
          raise Error, "El brief o el método han cambiado. Inicia un panel nuevo para esta versión."
        end
        settings["question_count"] = previous.settings["question_count"] if previous
        settings["panel_source_id"] = previous.id if previous
        panel_size = previous ? previous.panel.size : settings["question_count"] * brand.markets.size
        minimum_requests = 4 + brand.markets.size * 2 + panel_size * settings["repetitions"] * 2
        if minimum_requests > settings["max_requests"]
          raise Error, "Este alcance necesita al menos #{minimum_requests} solicitudes y supera el límite configurado. Reduce preguntas, mercados o repeticiones."
        end
        study = brand.visibility_studies.create!(brand_brief: brand.current_brief, settings: settings, budget_usd: budget_usd,
          competitors: previous&.competitors || [], panel: previous&.panel || [], entities: previous&.entities || [], panel_fingerprint: previous&.panel_fingerprint)
        study.record_event!(previous ? "Estudio solicitado con el panel anterior. Las respuestas se recogerán de nuevo." : "Estudio solicitado. Preparando el equipo de investigación.")
        study
      end
    end

    def enqueue!(study)
      raise ActiveJob::EnqueueError unless VisibilityStudyJob.perform_later(study.id)
      study
    rescue StandardError
      study.update!(status: "failed", error_message: "No se ha podido avisar al ejecutor. Puedes recuperar el estudio.", finished_at: Time.current)
      study.record_event!(study.error_message, kind: "warning")
      study
    end

    def control!(study, action, budget_usd: nil)
      raise Error, "Acción no válida." unless %w[pause resume cancel retry restart].include?(action)
      replacement = nil
      study.with_lock do
        if action == "resume" || action == "retry"
          eligible = action == "resume" ? study.paused? : study.failed?
          raise Error, "El estudio no está disponible para continuar." unless eligible && study.control_action.nil?
          study.update!(budget_usd: budget_usd) if budget_usd.present?
          study.update!(status: "queued", pause_reason: nil, error_message: nil, finished_at: nil,
            settings: study.settings.merge("retry_epoch" => Time.current.iso8601(6)))
          study.record_event!("Continuación solicitada. Se recuperarán las tareas y respuestas guardadas.", kind: "control")
        elsif study.active?
          raise Error, "El estudio ya está en pausa." if action == "pause" && study.paused?
          requested = action
          unless study.control_action == requested
            study.update!(control_action: requested)
            study.record_event!({ "pause" => "Pausa solicitada", "cancel" => "Cancelación solicitada", "restart" => "Reinicio solicitado" }.fetch(action) + ". Terminando la tarea en curso.", kind: "control")
          end
        elsif action == "restart"
          replacement = study.brand.visibility_studies.active.first
        else
          raise Error, "Esta ejecución ya ha terminado."
        end
      end
      if action == "restart" && !study.active?
        replacement ||= study.brand.visibility_studies.find_by(id: study.settings["restart_study_id"])
        replacement ||= create!(study.brand, question_count: study.settings["question_count"], repetitions: study.settings["repetitions"], budget_usd: study.budget_usd)
        study.update!(settings: study.settings.merge("restart_study_id" => replacement.id))
      end
      target = replacement || study
      enqueue!(target) if target.work_pending?
      target
    end

    def checkpoint!(study)
      study.reload
      raise Halted unless study.active?
      return unless study.control_action.present? || study.paused?
      restart = false
      study.with_lock do
        case study.control_action
        when "pause"
          study.update!(status: "paused", control_action: nil, pause_reason: "Pausa solicitada por ti.")
          study.record_event!("Estudio en pausa. Los resultados están guardados y no se harán nuevas solicitudes a Google.", kind: "control")
        when "cancel", "restart"
          restart = study.control_action == "restart"
          study.update!(status: "cancelled", control_action: nil, finished_at: Time.current)
          study.record_event!("Estudio cancelado. Las observaciones recogidas se conservan.", kind: "control")
        end
      end
      if restart
        replacement = create!(study.brand, question_count: study.settings["question_count"], repetitions: study.settings["repetitions"], budget_usd: study.budget_usd)
        study.update!(settings: study.settings.merge("restart_study_id" => replacement.id))
        enqueue!(replacement)
      end
      raise Halted
    end
  end
end
