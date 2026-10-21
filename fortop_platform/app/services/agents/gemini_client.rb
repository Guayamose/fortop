require "net/http"
require "json"

module Agents
  class GeminiClient
    RETRYABLE_STATUSES = [ 429, 500, 502, 503, 504 ].freeze

    attr_reader :model, :usage

    def initialize(api_key: ENV["GOOGLE_AI_STUDIO_API_KEY"].presence || ENV["GEMINI_API_KEY"], model: ENV.fetch("GEMINI_MODEL", "gemini-3.1-flash-lite"), transport: nil, sleeper: ->(seconds) { sleep(seconds) }, max_output_tokens: ENV.fetch("AGENT_MAX_OUTPUT_TOKENS", 4096), max_total_tokens: ENV.fetch("AGENT_MAX_TOTAL_TOKENS", 120_000))
      raise ConfigurationError, "Falta configurar GOOGLE_AI_STUDIO_API_KEY o GEMINI_API_KEY." if api_key.blank?
      raise ConfigurationError, "GEMINI_MODEL no es válido." unless model.match?(/\Agemini-[a-zA-Z0-9.\-]+\z/)

      @api_key, @model, @transport, @sleeper = api_key, model, transport, sleeper
      @usage = { "requests" => 0, "input_tokens" => 0, "output_tokens" => 0, "total_tokens" => 0 }
      @max_output_tokens = Integer(max_output_tokens).clamp(256, 8192)
      @max_total_tokens = Integer(max_total_tokens).clamp(5000, 500_000)
      @previous_total_tokens = 0
    rescue ArgumentError, TypeError
      raise ConfigurationError, "Los límites de tokens del agente deben ser números enteros."
    end

    def account_for_previous_usage(usage)
      @previous_total_tokens = usage.fetch("total_tokens", 0).to_i.clamp(0, 500_000)
    end

    def generate(system:, contents:, declarations:)
      body = {
        systemInstruction: { parts: [ { text: system } ] },
        contents: contents,
        tools: [ { functionDeclarations: declarations } ],
        toolConfig: { functionCallingConfig: { mode: "AUTO" } },
        generationConfig: { temperature: 0.2, maxOutputTokens: @max_output_tokens }
      }
      # Conservative preflight bounds growing history before spending another request.
      estimated_input = (JSON.generate(body).bytesize / 3.0).ceil
      if @previous_total_tokens + @usage["total_tokens"] + estimated_input + @max_output_tokens > @max_total_tokens
        raise BudgetExceeded, "El análisis ha alcanzado el presupuesto total de tokens configurado."
      end
      attempts = 0
      begin
        @usage["requests"] += 1
        response = request(body)
        status = response.code.to_i
        if RETRYABLE_STATUSES.include?(status) && attempts < 2
          attempts += 1
          @sleeper.call(2**attempts)
          retry_request = true
        else
          retry_request = false
        end
      end while retry_request

      unless status.between?(200, 299)
        message = case status
        when 400 then "Gemini ha rechazado la solicitud del agente (HTTP 400)."
        when 401, 403 then "Gemini no ha autorizado la clave o el proyecto (HTTP #{status})."
        when 404 then "El modelo #{model} no está disponible en este proyecto. Revisa GEMINI_MODEL."
        when 429 then "Gemini ha agotado la cuota o el límite de solicitudes."
        else "Gemini no está disponible temporalmente (HTTP #{status})."
        end
        # Provider bodies can contain echoed prompts and credentials: never log them.
        raise Error, message
      end

      data = JSON.parse(response.body)
      token_usage = data.fetch("usageMetadata", {})
      @usage["input_tokens"] += token_usage.fetch("promptTokenCount", estimated_input)
      @usage["output_tokens"] += token_usage.fetch("candidatesTokenCount", 0) + token_usage.fetch("thoughtsTokenCount", 0)
      @usage["total_tokens"] += token_usage.fetch("totalTokenCount", estimated_input + @max_output_tokens)
      raise BudgetExceeded, "El análisis ha alcanzado el presupuesto total de tokens configurado." if @previous_total_tokens + @usage["total_tokens"] > @max_total_tokens
      candidate = data.fetch("candidates", []).first
      unless candidate && candidate.dig("content", "parts").present?
        raise Error, "Gemini no ha devuelto una respuesta utilizable. Revisa los filtros o la cuota del proveedor."
      end
      if candidate["finishReason"] == "MAX_TOKENS"
        raise BudgetExceeded, "El agente ha alcanzado el límite de salida del modelo."
      end

      # Preserve every part, including Gemini thoughtSignature, across tool turns.
      candidate.fetch("content")
    rescue JSON::ParserError
      raise Error, "Gemini ha devuelto una respuesta no válida."
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET, OpenSSL::SSL::SSLError
      raise Error, "No se ha podido completar la conexión con Gemini."
    end

    private

    def request(body)
      uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["x-goog-api-key"] = @api_key
      request.body = JSON.generate(body)
      return @transport.call(uri, request) if @transport

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 90, write_timeout: 15) do |http|
        http.request(request)
      end
    end
  end
end
