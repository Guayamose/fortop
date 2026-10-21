require "base64"
require "digest"
require "uri"

module Github
  class OAuth
    CALLBACK_PATH = "/auth/github/callback"

    def self.configured?
      return false unless Github::App.configured?
      new.send(:validate_configuration!)
      true
    rescue Github::Error
      false
    end

    def initialize(env: nil, http: Github::Http.new)
      @env = env || Github::Configuration.environment
      @http = http
    end

    def authorize_url(state:, code_verifier:)
      validate_configuration!
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
      uri = URI("https://github.com/login/oauth/authorize")
      uri.query = URI.encode_www_form(
        client_id: @env["GITHUB_CLIENT_ID"], redirect_uri: callback_url,
        state: state,
        code_challenge: challenge, code_challenge_method: "S256"
      )
      uri.to_s
    end

    def exchange(code:, code_verifier:)
      validate_configuration!
      result = @http.request(URI("https://github.com/login/oauth/access_token"), method: :post, accept: "application/json", body: {
        client_id: @env["GITHUB_CLIENT_ID"], client_secret: @env["GITHUB_CLIENT_SECRET"],
        code: code, code_verifier: code_verifier, redirect_uri: callback_url
      })
      validate_tokens!(result)
    end

    def refresh(refresh_token:)
      validate_configuration!
      raise Error, "Inicia sesión de nuevo con GitHub." if refresh_token.blank?
      result = @http.request(URI("https://github.com/login/oauth/access_token"), method: :post, accept: "application/json", body: {
        client_id: @env["GITHUB_CLIENT_ID"], client_secret: @env["GITHUB_CLIENT_SECRET"],
        grant_type: "refresh_token", refresh_token: refresh_token
      })
      validate_tokens!(result)
    end

    private

    def validate_tokens!(result)
      unless result.is_a?(Hash) && result["access_token"].is_a?(String) && result["access_token"].present? && result["error"].blank?
        raise Error, "GitHub no ha autorizado la sesión. Vuelve a iniciar sesión."
      end
      {
        token: result.fetch("access_token"), refresh_token: result["refresh_token"],
        expires_at: result["expires_in"].present? ? Time.current + result["expires_in"].to_i.seconds : nil
      }
    end

    def callback_url
      "#{app_url}#{CALLBACK_PATH}"
    end

    def app_url
      (@env["APP_URL"].presence || "http://localhost:3000").delete_suffix("/")
    end

    def validate_configuration!
      if @env["GITHUB_CLIENT_ID"].blank? || @env["GITHUB_CLIENT_SECRET"].blank?
        raise Error, "El acceso con GitHub todavía no está configurado."
      end

      uri = URI.parse(app_url)
      valid_local = uri.scheme == "http" && %w[localhost 127.0.0.1 ::1].include?(uri.host)
      unless (uri.scheme == "https" || valid_local) && uri.host.present? && uri.userinfo.nil? &&
          uri.query.nil? && uri.fragment.nil? && uri.path.empty?
        raise Error, "La dirección de la aplicación para GitHub no está configurada correctamente."
      end
    rescue URI::InvalidURIError
      raise Error, "La dirección de la aplicación para GitHub no está configurada correctamente."
    end
  end
end
