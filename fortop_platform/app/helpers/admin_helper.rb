module AdminHelper
  ADMIN_SECTIONS = [ [ "Resumen", :admin_root_path, "dashboard" ], [ "Accesos", :admin_access_grants_path, "access_grants" ],
    [ "Usuarios", :admin_users_path, "users" ], [ "Repositorios", :admin_repositories_path, "repositories" ],
    [ "Marcas", :admin_brands_path, "brands" ], [ "Actividad", :admin_activity_path, "activity" ],
    [ "Configuración", :admin_settings_path, "settings" ], [ "Registro", :admin_audit_events_path, "audit_events" ] ].freeze
  ADMIN_OPERATIONS = { "pause" => "Pausar", "resume" => "Continuar", "cancel" => "Cancelar", "restart" => "Reiniciar",
    "retry" => "Reintentar", "retry_publication" => "Reintentar publicación", "expire" => "Marcar interrumpida" }.freeze
  ADMIN_AUDIT_LABELS = { "access.grant" => "Acceso autorizado", "access.revoke" => "Acceso retirado", "user.delete" => "Cuenta eliminada",
    "repository.disconnect" => "Repositorio desconectado", "brand.delete" => "Marca eliminada", "settings.update" => "Configuración actualizada", "settings.reset" => "Configuración restablecida" }.freeze

  def admin_execution_title(record)
    case record
    when Scan then record.repository.full_name
    when VisibilityStudy then record.brand.name
    when BrandImport then "Documentos ##{record.id}"
    end
  end

  def admin_execution_owner(record)
    case record
    when Scan then record.repository.user
    when VisibilityStudy then record.brand.user
    when BrandImport then record.user
    end
  end

  def admin_execution_type(record)
    { "scans" => "Análisis de repositorio", "studies" => "Estudio de visibilidad", "imports" => "Lectura de documentos" }.fetch(Admin::ExecutionCatalog.kind(record))
  end

  def admin_status(record)
    label = record.respond_to?(:status_label) ? record.status_label : { "queued" => "En cola", "extracting" => "Extrayendo", "interpreting" => "Interpretando", "completed" => "Completado", "failed" => "Interrumpido" }.fetch(record.status)
    tone = record.completed? ? "success" : record.failed? ? "error" : record.active? ? "active" : "neutral"
    tag.span(class: "badge badge-#{tone}") { safe_join([ tag.span(class: "status-dot"), label ]) }
  end

  def admin_usd(value)
    number_to_currency(value, unit: "US$ ", precision: 4, separator: ",", delimiter: ".")
  end

  def admin_safe_message(value)
    text = value.to_s
    %w[GOOGLE_AI_STUDIO_API_KEY GEMINI_API_KEY GOOGLE_API_KEY GITHUB_CLIENT_SECRET GITHUB_WEBHOOK_SECRET GITHUB_APP_PRIVATE_KEY].each do |key|
      secret = ENV[key]
      text = text.gsub(secret, "[OCULTO]") if secret.present?
    end
    text.gsub(/\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|AIza[A-Za-z0-9_-]{20,})\b/, "[OCULTO]")
  end

  def admin_number(value)
    number_with_delimiter(value, delimiter: ".")
  end

  def admin_audit_label(event)
    return "Ejecución: #{ADMIN_OPERATIONS.fetch(event.action.delete_prefix('execution.'), event.action)}" if event.action.start_with?("execution.")
    ADMIN_AUDIT_LABELS.fetch(event.action, event.action)
  end
end
