require "net/http"
require "json"

module Visibility
  class GoogleClient
    Result = Data.define(:text, :citations, :search_queries, :search_entry_point, :usage, :model_version)

    def initialize(api_key: ENV["GOOGLE_AI_STUDIO_API_KEY"].presence || ENV["GEMINI_API_KEY"], transport: nil)
      raise Error, "Falta configurar la clave de Google AI Studio." if api_key.blank?
      @api_key, @transport = api_key, transport
    end

    def generate(model:, system:, prompt:, grounded:, max_output_tokens:, temperature:, schema: nil)
      raise Error, "El modelo de Google no es válido." unless model.match?(/\Agemini-[a-zA-Z0-9.\-]+\z/)
      config = { temperature: temperature, maxOutputTokens: max_output_tokens }
      config[:thinkingConfig] = model.start_with?("gemini-3") ? { thinkingLevel: "MINIMAL" } : { thinkingBudget: 0 }
      config.merge!(responseMimeType: "application/json", responseJsonSchema: schema) if schema
      body = { systemInstruction: { parts: [ { text: system } ] }, contents: [ { role: "user", parts: [ { text: prompt } ] } ], generationConfig: config }
      body[:tools] = [ { googleSearch: {} } ] if grounded
      uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["x-goog-api-key"] = @api_key
      request.body = JSON.generate(body)
      response = if @transport
        @transport.call(uri, request)
      else
        Net::HTTP.start(uri.host, 443, use_ssl: true, open_timeout: 10, read_timeout: 100, write_timeout: 15) { |http| http.request(request) }
      end
      unless response.code.to_i.between?(200, 299)
        code = response.code.to_i
        message = case code
        when 401, 403 then "Google no ha autorizado la clave o el acceso a búsqueda (HTTP #{code})."
        when 429 then "Google ha agotado la cuota o el límite de solicitudes. Se conservarán los resultados recogidos."
        when 404 then "El modelo de visibilidad no está disponible en este proyecto. Revisa VISIBILITY_GEMINI_MODEL."
        when 400 then "Google ha rechazado la configuración de búsqueda o del modelo (HTTP 400)."
        else "Google no está disponible temporalmente (HTTP #{code})."
        end
        raise ProviderError.new(message, retryable: [ 429, 500, 502, 503, 504 ].include?(code))
      end
      data = JSON.parse(response.body)
      candidate = data.fetch("candidates", []).first || {}
      text = candidate.dig("content", "parts").to_a.reject { |part| part["thought"] }.filter_map { |part| part["text"] }.join("\n")
      metadata = candidate.fetch("groundingMetadata", {})
      supports = metadata.fetch("groundingSupports", [])
      citations = metadata.fetch("groundingChunks", []).each_with_index.filter_map do |chunk, index|
        web = chunk["web"]
        next unless web && Urls.public_url(web["uri"])
        excerpts = supports.filter_map do |support|
          quote = support.dig("segment", "text")
          quote if support.fetch("groundingChunkIndices", []).include?(index) && quote.is_a?(String) && text.include?(quote)
        end.uniq
        { "url" => web["uri"], "title" => web["title"].to_s.truncate(300), "excerpts" => excerpts, "cited" => excerpts.any? }
      end
      raw = data.fetch("usageMetadata", {})
      queries = metadata.fetch("webSearchQueries", []).select { |query| query.is_a?(String) && query.present? }
      usage = { "input_tokens" => raw.fetch("promptTokenCount", request.body.bytesize), "output_tokens" => raw.fetch("candidatesTokenCount", 0) + raw.fetch("thoughtsTokenCount", 0), "total_tokens" => raw.fetch("totalTokenCount", request.body.bytesize + max_output_tokens), "search_queries" => queries.size }
      raise ProviderError, "Google ha devuelto una respuesta incompleta o filtrada. Reduce el alcance o reintenta la tarea." if text.blank? || candidate["finishReason"] != "STOP"
      Result.new(text: text, citations: citations, search_queries: queries, search_entry_point: metadata.dig("searchEntryPoint", "renderedContent"), usage: usage, model_version: data["modelVersion"].presence || model)
    rescue JSON::ParserError, KeyError, TypeError
      raise ProviderError, "Google ha devuelto una respuesta no válida."
    rescue IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError
      # A lost HTTP response can still be billed. The ledger reserves its cost.
      raise ProviderError.new("La conexión con Google se ha interrumpido. La solicitud puede haber consumido cuota.", retryable: true)
    end
  end
end
