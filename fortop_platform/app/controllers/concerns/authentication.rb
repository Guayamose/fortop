module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user
  end

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id]) if session[:user_id]
    if @current_user && !@current_user.login_allowed?
      reset_session
      @current_user = nil
    end
    @current_user
  end

  def require_authentication
    redirect_to new_session_path, alert: "Inicia sesión con GitHub para continuar.", status: :see_other unless current_user
  end

  def require_new_work_enabled
    return if PlatformSetting.new_work_enabled?
    redirect_back fallback_location: root_path, alert: "Las nuevas ejecuciones están pausadas por el administrador.", status: :see_other
  end
end
