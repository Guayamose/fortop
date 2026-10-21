require "fileutils"
require "securerandom"

module Github
  class AppManifest
    CREDENTIAL_KEYS = Github::Configuration::KEYS

    def initialize(env: ENV, http: Github::Http.new, env_path: Rails.root.join(".env"))
      @env = env
      @http = http
      @env_path = Pathname(env_path)
    end

    def manifest
      origin = base_url
      {
        name: "Fortop-#{SecureRandom.hex(4)}", url: origin,
        description: "Análisis GEO y remediación mediante agentes de Fortop.", public: true,
        redirect_url: "#{origin}/github/app/manifest/callback",
        callback_urls: [ "#{origin}/auth/github/callback" ],
        setup_url: "#{origin}/github/installations/callback",
        request_oauth_on_install: false, setup_on_update: true,
        # GitHub validates a nonempty webhook URL even when inactive. There is
        # no webhook receiver in this flow, so keep the required field empty.
        hook_attributes: { url: "", active: false }, default_events: [],
        default_permissions: { contents: "write", issues: "write", pull_requests: "write", metadata: "read" }
      }
    end

    def register!(code:)
      unless code.is_a?(String) && code.match?(/\A[A-Za-z0-9_-]{10,200}\z/)
        raise Error, "El código de registro de la GitHub App no es válido."
      end
      response = @http.request(URI("https://api.github.com/app-manifests/#{code}/conversions"), method: :post)
      raise Error, "GitHub ha devuelto una configuración incompleta." unless response.is_a?(Hash)
      credentials = {
        "GITHUB_APP_ID" => response.fetch("id").to_s, "GITHUB_APP_SLUG" => response.fetch("slug"),
        "GITHUB_CLIENT_ID" => response.fetch("client_id"), "GITHUB_CLIENT_SECRET" => response.fetch("client_secret"),
        "GITHUB_APP_PRIVATE_KEY" => response.fetch("pem")
      }
      unless credentials.values.all? { |value| value.is_a?(String) && value.present? } && Github::App.new(env: credentials).send(:validate_configuration!) != false
        raise Error, "GitHub ha devuelto una configuración incompleta."
      end
      # GitHub can omit the secret when the app has no active webhook. It is
      # unrelated to App authentication and must not discard valid credentials.
      webhook_secret = response["webhook_secret"]
      credentials["GITHUB_WEBHOOK_SECRET"] = webhook_secret if webhook_secret.is_a?(String) && webhook_secret.present?
      persist!(credentials)
      credentials.each { |key, value| @env[key] = value }
      true
    rescue KeyError
      raise Error, "GitHub ha devuelto una configuración incompleta."
    end

    private

    def base_url
      value = (@env["APP_URL"].presence || "http://localhost:3000").delete_suffix("/")
      uri = URI(value)
      unless %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil? &&
          uri.query.nil? && uri.fragment.nil? && uri.path.empty?
        raise Error, "Configura una dirección válida para la plataforma antes de registrar la GitHub App."
      end
      value
    rescue URI::InvalidURIError
      raise Error, "La dirección de la plataforma no es válida."
    end

    def persist!(credentials)
      if @env_path.symlink? || (@env_path.exist? && !@env_path.file?)
        raise Error, "No se puede guardar la configuración en el archivo de entorno."
      end
      original = @env_path.exist? ? @env_path.read : ""
      key_pattern = CREDENTIAL_KEYS.join("|")
      kept = original.lines.reject { |line| line.match?(/\A\s*(?:export\s+)?(?:#{key_pattern})\s*=/) }.join
      escaped = credentials.map do |key, value|
        value = Base64.strict_encode64(value) if key == "GITHUB_APP_PRIVATE_KEY"
        replacements = { "\\" => "\\\\", '"' => '\\"', "\n" => '\\n', "\r" => '\\r', "$" => '\\$' }
        encoded = value.gsub(/[\\"\n\r$]/) { |character| replacements.fetch(character) }
        "#{key}=\"#{encoded}\"\n"
      end.join
      temporary = @env_path.dirname.join(".env.fortop-#{SecureRandom.hex(8)}")
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(kept)
        file.write("\n") unless kept.empty? || kept.end_with?("\n")
        file.write(escaped)
        file.flush
        file.fsync
      end
      File.rename(temporary, @env_path)
    rescue SystemCallError, IOError
      raise Error, "No se han podido guardar las credenciales de la GitHub App en el servidor."
    ensure
      File.delete(temporary) if temporary && File.exist?(temporary)
    end
  end
end
