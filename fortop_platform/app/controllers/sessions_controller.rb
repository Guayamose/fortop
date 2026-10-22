require "securerandom"

class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create callback], raise: false
  before_action :no_store
  rescue_from ActionController::InvalidAuthenticityToken, with: :recover_expired_login

  def new
    redirect_to root_path if current_user
  end

  def create
    return redirect_to root_path if current_user

    state = SecureRandom.hex(32)
    verifier = SecureRandom.urlsafe_base64(48, false)
    url = Github::OAuth.new.authorize_url(state: state, code_verifier: verifier)
    session[:github_oauth] = { "state" => state, "verifier" => verifier, "expires_at" => 10.minutes.from_now.to_i }
    redirect_to url, allow_other_host: true, status: :see_other
  rescue Github::Error => error
    redirect_to new_session_path, alert: error.message
  end

  def callback
    handshake = session.delete(:github_oauth)
    unless valid_handshake?(handshake)
      return redirect_to new_session_path, alert: "La solicitud de acceso ha caducado o no es válida. Vuelve a iniciar sesión."
    end
    if params[:error].present? || params[:code].blank? || params[:code].to_s.bytesize > 500
      return redirect_to new_session_path, alert: "No se ha autorizado el acceso con GitHub."
    end

    credentials = Github::OAuth.new.exchange(code: params[:code].to_s, code_verifier: handshake["verifier"])
    profile = Github::Client.new(token: credentials.fetch(:token)).user
    unless User.github_allowed?(profile.fetch("id"))
      reset_session
      return redirect_to new_session_path, alert: "Tu cuenta de GitHub no tiene acceso a Fortop. Solicita acceso al administrador."
    end
    user = User.from_github(profile, **credentials)
    reset_session
    session[:user_id] = user.id
    redirect_to root_path
  rescue Github::Error => error
    redirect_to new_session_path, alert: error.message
  rescue ActiveRecord::RecordInvalid
    redirect_to new_session_path, alert: "No se ha podido guardar tu cuenta de GitHub. Vuelve a intentarlo."
  end

  def destroy
    reset_session
    redirect_to new_session_path, notice: "Has cerrado la sesión.", status: :see_other
  end

  private

  def recover_expired_login(error)
    raise error unless action_name == "create"

    no_store
    redirect_to new_session_path, status: :see_other,
      alert: "El formulario de acceso ha caducado. Vuelve a pulsar «Continuar con GitHub»."
  end

  def valid_handshake?(handshake)
    return false unless handshake.is_a?(Hash) && handshake["expires_at"].to_i > Time.current.to_i
    expected = handshake["state"].to_s
    received = params[:state].to_s
    return false unless expected.bytesize == 64 && received.bytesize == 64 && handshake["verifier"].present?
    ActiveSupport::SecurityUtils.secure_compare(expected, received)
  end
end
