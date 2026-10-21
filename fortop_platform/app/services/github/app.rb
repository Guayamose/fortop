require "base64"
require "json"
require "openssl"

module Github
  # App credentials authenticate the integration, never a visitor. Repository
  # operations receive short-lived tokens restricted to one authorized repo.
  class App
    def self.configured?
      new.send(:validate_configuration!)
      true
    rescue Error
      false
    end

    def self.installation_url(state: nil)
      new.installation_url(state: state)
    end

    def initialize(env: nil, http: Github::Http.new)
      @env = env || Github::Configuration.environment
      @http = http
    end

    def installation_url(state: nil)
      validate_configuration!
      uri = URI("https://github.com/apps/#{@env.fetch('GITHUB_APP_SLUG')}/installations/new")
      uri.query = URI.encode_www_form(state: state) if state.present?
      uri.to_s
    end

    def installation_token(installation_id, repository_id:)
      validate_configuration!
      id = positive_id(installation_id)
      repo_id = positive_id(repository_id)
      response = @http.request(URI("https://api.github.com/app/installations/#{id}/access_tokens"), method: :post,
        token: jwt, body: {
          repository_ids: [ repo_id ], permissions: { contents: "write", issues: "write", pull_requests: "write" }
        })
      token = response["token"] if response.is_a?(Hash)
      raise Error, "GitHub no ha concedido acceso al repositorio instalado." unless token.is_a?(String) && token.present?
      permissions = response["permissions"]
      repositories = response["repositories"]
      unless permissions.is_a?(Hash) && %w[contents issues pull_requests].all? { |permission| permissions[permission] == "write" } &&
          response["repository_selection"] == "selected" && repositories.is_a?(Array) && repositories.size == 1 &&
          repositories.first.is_a?(Hash) && repositories.first["id"].to_s == repo_id.to_s
        raise Error.new("GitHub no ha concedido los permisos de escritura limitados al repositorio autorizado.", status: 403)
      end
      token
    end

    def jwt(now: Time.current)
      validate_configuration!
      header = encode(JSON.generate(alg: "RS256", typ: "JWT"))
      payload = encode(JSON.generate(iat: now.to_i - 60, exp: now.to_i + 540, iss: @env.fetch("GITHUB_APP_ID")))
      signing_input = "#{header}.#{payload}"
      signature = private_key.sign(OpenSSL::Digest::SHA256.new, signing_input)
      "#{signing_input}.#{encode(signature)}"
    end

    private

    def validate_configuration!
      unless @env["GITHUB_APP_ID"].to_s.match?(/\A[1-9]\d*\z/) &&
          @env["GITHUB_APP_SLUG"].to_s.match?(/\A[a-z0-9][a-z0-9-]{0,99}\z/) &&
          @env["GITHUB_CLIENT_ID"].present? && @env["GITHUB_CLIENT_SECRET"].present? && private_key.private?
        raise Error, "La GitHub App todavía no está configurada."
      end
    end

    def private_key
      @private_key ||= begin
        raw = @env["GITHUB_APP_PRIVATE_KEY"].to_s
        pem = raw.include?("-----BEGIN") ? raw.gsub('\\n', "\n") : Base64.strict_decode64(raw)
        OpenSSL::PKey::RSA.new(pem)
      end
    rescue OpenSSL::PKey::RSAError, OpenSSL::PKey::PKeyError, ArgumentError
      raise Error, "La clave privada de la GitHub App no está configurada correctamente."
    end

    def positive_id(value)
      number = Integer(value)
      raise ArgumentError unless number.positive?
      number
    rescue ArgumentError, TypeError
      raise Error, "El identificador de instalación de GitHub no es válido."
    end

    def encode(value)
      Base64.urlsafe_encode64(value, padding: false)
    end
  end
end
