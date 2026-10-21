module Visibility
  class Gateway
    def initialize(study, client: GoogleClient.new)
      @study, @client = study, client
    end

    def call(key, system:, prompt:, grounded: false, schema: nil, temperature: 0.2)
      Studies.checkpoint!(@study)
      previous = @study.visibility_calls.where(task_key: key).order(attempt: :desc).first
      return previous if previous&.status == "succeeded"
      if previous&.status == "running"
        previous.update!(status: "uncertain", error_message: "El ejecutor perdió la respuesta de esta solicitud. Su coste reservado se conserva.")
      end
      epoch = @study.settings["retry_epoch"] ? Time.iso8601(@study.settings["retry_epoch"]) : @study.created_at
      epoch_attempts = @study.visibility_calls.where(task_key: key).where(created_at: epoch..).count
      raise ProviderError, "Esta tarea ha agotado sus tres intentos. Los resultados anteriores se conservan." if epoch_attempts >= 3

      output_limit = schema&.dig(:properties, "questions") ? [ @study.settings.fetch("max_output_tokens"), @study.settings.fetch("question_count") * 220 ].max : @study.settings.fetch("max_output_tokens")
      request_config = @study.settings.merge("max_output_tokens" => output_limit)
      reservation = BigDecimal(Settings.reservation(request_config, input_bytes: prompt.bytesize + system.bytesize + 1000, grounded: grounded).to_s).round(6)
      reserved_tokens = prompt.bytesize + system.bytesize + 1000 + output_limit
      call = reserve!(key, previous ? previous.attempt + 1 : 1, reservation, reserved_tokens, grounded)
      call.update!(input_prompt: prompt, system_instruction: system, request_settings: { "temperature" => temperature, "max_output_tokens" => output_limit, "schema" => schema })
      result = @client.generate(model: call.model, system: system, prompt: prompt, grounded: grounded, schema: schema,
        max_output_tokens: output_limit, temperature: temperature)
      actual_cost = BigDecimal(Settings.cost(@study.settings, result.usage, grounded: grounded).to_s).round(6)
      @study.with_lock do
        call.update!(status: "succeeded", response_text: result.text, citations: result.citations, search_queries: result.search_queries,
          search_entry_point: result.search_entry_point, usage: result.usage, cost_usd: actual_cost, model_version: result.model_version, observed_at: Time.current)
        @study.update!(spent_usd: @study.spent_usd - reservation + actual_cost,
          token_count: @study.token_count - reserved_tokens + result.usage.fetch("total_tokens"), search_count: @study.search_count + result.usage.fetch("search_queries"))
      end
      call
    rescue ProviderError => error
      if call
        call.update!(status: "failed", error_message: error.message, retryable: error.retryable)
        if error.retryable && epoch_attempts < 2
          @study.record_event!("Google no ha completado la tarea. Reintento #{epoch_attempts + 2}/3 programado; se conserva todo lo anterior.", kind: "warning")
          raise RetryLater, 2**(epoch_attempts + 1)
        end
      end
      raise
    end

    def json(key, system:, prompt:, schema:)
      record = call(key, system: system, prompt: prompt, schema: schema)
      data = JSON.parse(record.response_text)
      raise JSON::ParserError unless valid_json?(data, schema)
      data
    rescue JSON::ParserError
      record&.update!(status: "failed", error_message: "La respuesta estructurada de esta tarea no es válida.")
      raise Error, "Una tarea ha devuelto datos no válidos. Puedes recuperar el estudio conservando las respuestas anteriores."
    end

    def invalidate!(key)
      @study.visibility_calls.where(task_key: key, status: "succeeded").update_all(status: "failed", error_message: "La respuesta necesita una corrección de contenido.")
    end

    private

    def valid_json?(value, schema)
      return false if schema[:enum] && !schema[:enum].include?(value)
      case schema[:type]
      when "object" then value.is_a?(Hash) && schema[:required].all? { |key| value.key?(key) && valid_json?(value[key], schema[:properties].fetch(key)) }
      when "array" then value.is_a?(Array) && value.size <= 500 && value.all? { |item| valid_json?(item, schema[:items]) }
      when "string" then value.is_a?(String) && value.length <= 50_000
      when "integer" then value.is_a?(Integer)
      when "boolean" then [ true, false ].include?(value)
      else false
      end
    end

    def reserve!(key, attempt, reservation, tokens, grounded)
      paused = false
      result = @study.brand.user.with_lock do
        @study.with_lock do
          raise Halted if @study.control_action.present? || !@study.work_pending?
          if @study.request_count >= @study.settings.fetch("max_requests") || @study.token_count + tokens > @study.settings.fetch("max_tokens")
            raise Error, "Se ha alcanzado el límite de solicitudes o tokens del estudio. Conserva este informe y crea otro con un alcance menor."
          end
          daily = VisibilityCall.joins(visibility_study: :brand).where(brands: { user_id: @study.brand.user_id }).where(created_at: Time.current.in_time_zone("Europe/Madrid").beginning_of_day..).sum(:cost_usd)
          daily += @study.brand.user.brand_imports.where(updated_at: Time.current.in_time_zone("Europe/Madrid").beginning_of_day..).sum(:spent_usd)
          daily_limit = BigDecimal(ENV.fetch("VISIBILITY_DAILY_BUDGET_USD", "10"))
          if @study.spent_usd + reservation > @study.budget_usd || daily + reservation > daily_limit
            message = daily + reservation > daily_limit ? "Se ha alcanzado el presupuesto diario configurado. Puedes continuar otro día." : "El presupuesto disponible no cubre la reserva de la siguiente tarea. Puedes ampliarlo y continuar."
            @study.update!(status: "paused", pause_reason: message)
            @study.record_event!(message, kind: "control")
            paused = true
            next
          end
          record = @study.visibility_calls.create!(task_key: key, attempt: attempt, model: @study.settings.fetch("model"), grounded: grounded,
            cost_usd: reservation, usage: { "reserved_tokens" => tokens, "estimated" => true })
          @study.update!(spent_usd: @study.spent_usd + reservation, request_count: @study.request_count + 1, token_count: @study.token_count + tokens)
          record
        end
      end
      raise Halted if paused
      result
    end
  end
end
