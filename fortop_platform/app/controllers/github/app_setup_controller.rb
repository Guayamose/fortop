require "ipaddr"

module Github
  class AppSetupController < ApplicationController
    skip_before_action :require_authentication
    before_action :require_local_development

    def new
      return redirect_to new_session_path, notice: "La GitHub App ya está configurada." if Github::App.configured?

      state = SecureRandom.hex(32)
      session[:github_manifest] = { "state" => state, "expires_at" => 15.minutes.from_now.to_i }
      @registration_url = "https://github.com/settings/apps/new?#{URI.encode_www_form(state: state)}"
      @manifest = Github::AppManifest.new.manifest.to_json
      render :new
    rescue Github::Error => error
      redirect_to new_session_path, alert: error.message
    end

    def callback
      handshake = session.delete(:github_manifest)
      unless valid_state?(handshake)
        return redirect_to new_session_path, alert: "El registro ha caducado o no es válido. Vuelve a iniciar la configuración."
      end
      return redirect_to new_session_path, alert: "La GitHub App ya está configurada." if Github::App.configured?

      Github::AppManifest.new.register!(code: params[:code].to_s)
      redirect_to new_session_path, notice: "GitHub App creada y conectada. Ya puedes iniciar sesión."
    rescue Github::Error => error
      redirect_to new_session_path, alert: error.message
    end

    private

    def require_local_development
      local = IPAddr.new(request.remote_ip).loopback? && IPAddr.new(request.get_header("REMOTE_ADDR").to_s).loopback?
      head :not_found unless Rails.env.development? && local
    rescue IPAddr::InvalidAddressError
      head :not_found
    end

    def valid_state?(handshake)
      return false unless handshake.is_a?(Hash) && handshake["expires_at"].to_i > Time.current.to_i
      expected = handshake["state"].to_s
      actual = params[:state].to_s
      expected.bytesize == 64 && actual.bytesize == 64 && ActiveSupport::SecurityUtils.secure_compare(expected, actual)
    end
  end
end
