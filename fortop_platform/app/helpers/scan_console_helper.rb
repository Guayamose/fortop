module ScanConsoleHelper
  CONSOLE_ACTORS = {
    "research" => { label: "Investigación web", icon: :globe, tone: "blue" },
    "planning" => { label: "Diseño de la medición", icon: :lightbulb, tone: "violet" },
    "observation" => { label: "Respuestas de Gemini", icon: :search, tone: "violet" },
    "system" => { label: "Fortop", icon: :agent, tone: "neutral" },
    "analysis" => { label: "Agente de análisis", icon: :search, tone: "blue" },
    "remediation" => { label: "Agente de remediación", icon: :edit, tone: "violet" },
    "validation" => { label: "Verificación", icon: :shield_check, tone: "green" },
    "publication" => { label: "GitHub", icon: :github, tone: "neutral" },
    "control" => { label: "Control de ejecución", icon: :pause, tone: "neutral" }
  }.freeze

  CONSOLE_TOOLS = {
    "list_files" => { label: "Explorar archivos", icon: :folder, category: "code" },
    "read_file" => { label: "Leer código", icon: :file, category: "code" },
    "search" => { label: "Buscar referencias", icon: :search, category: "code" },
    "report_finding" => { label: "Documentar hallazgo", icon: :lightbulb, category: "finding" },
    "replace_text" => { label: "Editar código", icon: :edit, category: "code" },
    "write_file" => { label: "Preparar archivo", icon: :file, category: "code" },
    "validate_changes" => { label: "Verificar cambios", icon: :shield_check, category: "code" },
    "explain_remediation" => { label: "Explicar corrección", icon: :lightbulb, category: "finding" },
    "mark_manual" => { label: "Solicitar revisión", icon: :alert, category: "finding" },
    "discard_changes" => { label: "Descartar cambio", icon: :restart, category: "code" }
  }.freeze

  def console_event_actor(event)
    return event.kind if %w[research planning observation].include?(event.kind)
    agent = event.metadata["agent"]
    return agent if %w[analysis remediation].include?(agent)
    return "analysis" if event.kind == "finding" || event.message.start_with?("Análisis:")
    return "remediation" if event.message.start_with?("Remediación:")
    %w[validation publication control].include?(event.kind) ? event.kind : "system"
  end

  def console_event_groups(events)
    events.chunk { |event| console_event_actor(event) }.to_a
  end

  def console_event_style(event)
    tool = CONSOLE_TOOLS[event.metadata["tool"]]
    return tool if tool
    case event.kind
    when "research" then { label: "Fuente contrastada", icon: :globe, category: "research" }
    when "planning" then { label: "Panel de preguntas", icon: :lightbulb, category: "research" }
    when "observation" then { label: "Respuesta guardada", icon: :search, category: "observation" }
    when "finding" then { label: "Hallazgo", icon: :lightbulb, category: "finding" }
    when "validation" then { label: "Comprobación", icon: :shield_check, category: "code" }
    when "publication" then { label: "Publicación", icon: :github, category: "github" }
    when "warning" then { label: "Aviso", icon: :alert, category: "system" }
    when "control" then { label: "Ejecución", icon: :pause, category: "system" }
    when "tool" then { label: "Herramienta", icon: :code, category: "code" }
    else { label: "Estado", icon: :terminal, category: "system" }
    end
  end

  def console_event_checks(event)
    Array(event.metadata["checks"]).select { |check| check.is_a?(Hash) && [ true, false ].include?(check["passed"]) }
  end

  def console_event_message(event)
    return event.message unless CONSOLE_TOOLS.key?(event.metadata["tool"])
    message = event.message.delete_prefix("Análisis: ").delete_prefix("Remediación: ")
    path = event.metadata["path"]
    message = message.delete_suffix(" (#{path}).") if path.is_a?(String) && path.present?
    message.present? ? message[0].upcase + message[1..] : event.message
  end

  def console_file_type(path)
    extension = File.extname(path.to_s).delete_prefix(".").downcase
    %w[html htm erb rb js jsx ts tsx json css scss md mdx xml yaml yml vue svelte astro txt].include?(extension) ? extension : "file"
  end

  def console_phase(scan)
    if scan.control_action
      return { title: scan_heading(scan), description: "Terminando la operación en curso antes de detener el agente.", icon: :clock, tone: "neutral", state: "stopping", actor: "Ejecución" }
    end
    {
      "queued" => { title: "Listo para empezar", description: "Esperando a que el ejecutor recoja el análisis.", icon: :clock, tone: "blue", state: "waiting", actor: "Fortop" },
      "discovering" => { title: "Preparando el repositorio", description: "Recuperando el código y comprobando los permisos.", icon: :folder, tone: "blue", state: "live", actor: "Fortop" },
      "analyzing" => { title: "Explorando tu código", description: "Contrastando cada oportunidad con los archivos del repositorio.", icon: :search, tone: "blue", state: "live", actor: "Agente de análisis" },
      "remediating" => { title: "Dando forma a las mejoras", description: "Preparando correcciones a partir de los hallazgos contrastados.", icon: :edit, tone: "violet", state: "live", actor: "Agente de remediación" },
      "validating" => { title: "Comprobando los cambios", description: "Verificación independiente de las correcciones propuestas.", icon: :shield_check, tone: "green", state: "live", actor: "Verificación" },
      "publishing" => { title: "Llevando el trabajo a GitHub", description: "Publicando los hallazgos y las correcciones verificadas.", icon: :github, tone: "blue", state: "live", actor: "GitHub" },
      "paused" => { title: "Lo dejamos justo aquí", description: "El contexto y los cambios están guardados para continuar.", icon: :pause, tone: "neutral", state: "paused", actor: "En pausa" },
      "completed" => { title: "Trabajo terminado", description: "La actividad y los resultados de esta ejecución quedan guardados.", icon: :check, tone: "green", state: "completed", actor: "Completado" },
      "failed" => { title: "La ejecución necesita atención", description: "Consulta el error y las últimas acciones para ver qué ocurrió.", icon: :alert, tone: "amber", state: "failed", actor: "Interrumpido" },
      "cancelled" => { title: "Análisis cancelado", description: "Se conserva la actividad registrada hasta la cancelación.", icon: :stop, tone: "neutral", state: "cancelled", actor: "Cancelado" }
    }.fetch(scan.status)
  end
end
