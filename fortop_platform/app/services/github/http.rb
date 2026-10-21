require "json"
require "net/http"
require "openssl"
require "timeout"

module Github
  # GitHub is the only destination: redirects are deliberately never followed.
  class Http
    MAX_RESPONSE_BYTES = 12.megabytes
    RETRY_STATUSES = [ 502, 503, 504 ].freeze
    NETWORK_ERRORS = [ Timeout::Error, SocketError, EOFError, IOError, SystemCallError, OpenSSL::SSL::SSLError ].freeze

    def request(uri, method: :get, token: nil, body: nil, accept: "application/vnd.github+json")
      unless uri.is_a?(URI::HTTPS) && %w[api.github.com github.com].include?(uri.host) && uri.port == 443 && !uri.userinfo
        raise Error, "La dirección de GitHub no es válida."
      end

      attempts = 0
      begin
        attempts += 1
        response, raw = perform(uri, method: method, token: token, body: body, accept: accept)
        status = response.code.to_i
        if method == :get && RETRY_STATUSES.include?(status) && attempts < 3
          sleep(0.25 * attempts)
          retry_request = true
        else
          retry_request = false
          raise Error.new(error_message(status), status: status, retryable: RETRY_STATUSES.include?(status)) unless (200..299).cover?(status)
          return {} if raw.empty?
          return JSON.parse(raw)
        end
      rescue *NETWORK_ERRORS => error
        Rails.logger.warn("GitHub network failure method=#{method} host=#{uri.host} attempt=#{attempts} cause=#{error.class.name}")
        if method == :get && attempts < 3
          sleep(0.25 * attempts)
          retry
        end
        raise Error.new("GitHub no responde. Vuelve a intentarlo en unos minutos.", retryable: true)
      rescue JSON::ParserError
        raise Error.new("GitHub ha devuelto una respuesta que no se puede interpretar.", retryable: true)
      end while retry_request
    end

    private

    def perform(uri, method:, token:, body:, accept:)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
      request = klass.new(uri)
      request["Accept"] = accept
      request["User-Agent"] = "Fortop"
      request["X-GitHub-Api-Version"] = "2026-03-10"
      request["Authorization"] = "Bearer #{token}" if token
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 35
      http.write_timeout = 15
      http.max_retries = 0 # Never retry POST/PATCH implicitly after a connection error.
      raw = +""
      response = http.start do |connection|
        connection.request(request) do |result|
          result.read_body do |chunk|
            raw << chunk
            raise Error, "La respuesta de GitHub supera el tamaño permitido." if raw.bytesize > MAX_RESPONSE_BYTES
          end
        end
      end
      [ response, raw ]
    end

    def error_message(status)
      case status
      when 401 then "La autorización de GitHub ha caducado. Inicia sesión de nuevo."
      when 403, 429 then "GitHub ha limitado el acceso o faltan permisos. Revisa la autorización y vuelve a intentarlo."
      when 404 then "El recurso no existe en GitHub o ya no tienes acceso."
      when 409 then "El repositorio ha cambiado durante la operación. Inicia una nueva ejecución."
      when 422 then "GitHub no ha aceptado los cambios. Revisa el repositorio y vuelve a intentarlo."
      else "GitHub no ha podido completar la operación (HTTP #{status})."
      end
    end
  end
end
