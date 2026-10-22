module Admin
  class SettingsController < BaseController
    def show
      @overrides = PlatformSetting.pluck(:key, :value).to_h
    end

    def update
      values = params.require(:settings).permit(*PlatformSetting::DEFINITIONS.keys).to_h
      raise ActionController::BadRequest if values.empty?
      PlatformSetting.transaction do
        values.each { |key, value| PlatformSetting.find_or_initialize_by(key: key).update!(value: value) }
        audit!("settings.update", "Platform", values)
      end
      redirect_to admin_settings_path, notice: "Configuración guardada. Se aplicará al iniciar o recuperar los agentes; los estudios conservan su configuración guardada."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to admin_settings_path, alert: error.record.errors.full_messages.to_sentence
    end

    def destroy
      PlatformSetting.transaction do
        PlatformSetting.delete_all
        audit!("settings.reset", "Platform")
      end
      redirect_to admin_settings_path, notice: "Se han recuperado los valores del entorno de despliegue."
    end
  end
end
