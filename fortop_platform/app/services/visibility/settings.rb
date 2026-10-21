module Visibility
  module Settings
    METHOD_VERSION = "fortop-visibility-v1".freeze
    PRICING = {
      "gemini-3.1-flash-lite" => { "input" => 0.25, "output" => 1.50, "search" => 0.014, "search_unit" => "query" },
      "gemini-3.5-flash-lite" => { "input" => 0.30, "output" => 2.50, "search" => 0.014, "search_unit" => "query" },
      "gemini-2.5-flash-lite" => { "input" => 0.10, "output" => 0.40, "search" => 0.035, "search_unit" => "prompt" }
    }.freeze
    module_function

    def build(question_count: 12, repetitions: 2)
      count, repeats = Integer(question_count), Integer(repetitions)
      raise Error, "Elige entre 6 y 50 preguntas y entre 1 y 5 repeticiones." unless count.between?(6, 50) && repeats.between?(1, 5)
      model = ENV["VISIBILITY_GEMINI_MODEL"].presence || ENV.fetch("GEMINI_MODEL", "gemini-3.1-flash-lite")
      rates = PRICING[model]
      raise Error, "El modelo de visibilidad no tiene una tarifa configurada. Selecciona un modelo compatible en VISIBILITY_GEMINI_MODEL." unless rates
      limits = [ Integer(ENV.fetch("VISIBILITY_MAX_REQUESTS", 1500)), Integer(ENV.fetch("VISIBILITY_MAX_TOKENS", 2_000_000)) ]
      daily_budget = BigDecimal(ENV.fetch("VISIBILITY_DAILY_BUDGET_USD", "10"))
      raise Error, "Los límites de solicitudes, tokens y presupuesto diario deben ser positivos." unless limits.all?(&:positive?) && daily_budget.positive?
      { "question_count" => count, "repetitions" => repeats, "model" => model, "engine" => "Gemini API · búsqueda habilitada",
        "method_version" => METHOD_VERSION, "temperature" => 0.7, "max_output_tokens" => 4096,
        "max_requests" => limits[0], "max_tokens" => limits[1],
        "rates" => rates, "pricing_checked_at" => "2026-10-21", "pricing_source" => "https://ai.google.dev/gemini-api/docs/pricing",
        "geography" => "Contexto de mercado e idioma en la pregunta; sin geolocalización del usuario." }
    rescue ArgumentError, TypeError
      raise Error, "La configuración del estudio no es válida."
    end

    def reservation(settings, input_bytes:, grounded:)
      rates = settings.fetch("rates")
      token_cost = (input_bytes * rates.fetch("input") + settings.fetch("max_output_tokens") * rates.fetch("output")) / 1_000_000.0
      # Google Search has no per-request hard query cap. Reserve eight queries,
      # account actual returned queries, and stop before the next paid request.
      token_cost + (grounded ? rates.fetch("search") * (rates["search_unit"] == "prompt" ? 1 : 8) : 0)
    end

    def cost(settings, usage, grounded:)
      rates = settings.fetch("rates")
      queries = rates["search_unit"] == "prompt" ? (grounded ? 1 : 0) : usage.fetch("search_queries", 0)
      (usage.fetch("input_tokens", 0) * rates.fetch("input") + usage.fetch("output_tokens", 0) * rates.fetch("output")) / 1_000_000.0 + queries * rates.fetch("search")
    end
  end
end
