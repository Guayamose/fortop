module Github
  class InstallationsController < ApplicationController
    def create
      state = SecureRandom.hex(32)
      session[:github_installation] = { "state" => state, "expires_at" => 20.minutes.from_now.to_i }
      redirect_to Github::App.installation_url(state: state), allow_other_host: true, status: :see_other
    rescue Github::Error => error
      redirect_to repositories_path, alert: error.message
    end

    def callback
      # An installation_id from the browser is never proof of access. Verify
      # it using this visitor's GitHub App user token, including direct visits.
      id = params[:installation_id].to_s
      return redirect_to new_repository_path unless id.match?(/\A[1-9]\d*\z/)

      handshake = session.delete(:github_installation)
      if handshake && !valid_state?(handshake)
        return redirect_to new_repository_path, alert: "La solicitud de instalación ha caducado. Vuelve a intentarlo."
      end
      client = Github::Access.user_client(current_user)
      found = false
      1.upto(100) do |page|
        entries = client.installations(page: page)
        found = entries.any? { |entry| entry["id"].to_s == id && entry["suspended_at"].blank? }
        break if found || entries.size < 100
      end
      unless found
        return redirect_to new_repository_path, alert: "La instalación no está autorizada para tu cuenta."
      end
      redirect_to new_repository_path(installation_id: id), notice: "Instalación conectada. Elige un repositorio autorizado."
    rescue Github::Error => error
      redirect_to new_repository_path, alert: error.message
    end

    private

    def valid_state?(handshake)
      return false unless handshake["expires_at"].to_i > Time.current.to_i
      expected = handshake["state"].to_s
      actual = params[:state].to_s
      expected.bytesize == 64 && actual.bytesize == 64 && ActiveSupport::SecurityUtils.secure_compare(expected, actual)
    end
  end
end
