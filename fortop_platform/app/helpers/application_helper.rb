module ApplicationHelper
  ICON_PATHS = {
    trash: '<path d="M3 6h18M9 6V4h6v2M5 6l1 14h12l1-14M10 10v6M14 10v6"/>',
    chevron_down: '<path d="m6 9 6 6 6-6"/>',
    pause: '<path d="M9 5v14M15 5v14"/>',
    restart: '<path d="M3 10a9 9 0 1 1 2 8M3 4v6h6"/>',
    stop: '<rect x="6" y="6" width="12" height="12" rx="1"/>',
    terminal: '<path d="m4 6 6 6-6 6m9 0h7"/>',
    agent: '<path d="m12 3 2.6 5.4 5.9.9-4.3 4.2 1 5.9-5.2-2.8-5.2 2.8 1-5.9-4.3-4.2 5.9-.9L12 3Z"/><path d="M12 8v7m-3-5 6 3m0-3-6 3"/>',
    file: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6Zm0 0v6h6M8 13h8m-8 4h5"/>',
    folder: '<path d="M3 7V5a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z"/><path d="M3 9h18"/>',
    edit: '<path d="m16 3 5 5M4 20l4-1L21 6a2.1 2.1 0 0 0-3-3L5 16l-1 4Zm9 0h8"/>',
    shield_check: '<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Z"/><path d="m8 12 3 3 5-6"/>',
    lightbulb: '<path d="M9 18h6m-5 3h4M8.5 14.5a6 6 0 1 1 7 0C14 15.5 15 17 15 18H9c0-1 1-2.5-.5-3.5Z"/>',
    copy: '<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/>',
    expand: '<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/>',
    collapse: '<path d="M3 8h5V3m13 5h-5V3M8 21v-5H3m13 5v-5h5"/>',
    arrow_down: '<path d="M12 4v16m-6-6 6 6 6-6"/>',
    play: '<path d="m8 5 11 7-11 7V5Z"/>',
    repository: '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20M6.5 3H20v19H6.5A2.5 2.5 0 0 1 4 19.5v-14A2.5 2.5 0 0 1 6.5 3Z"/><path d="M8 7h8M8 11h5"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    arrow: '<path d="M5 12h14m-6-6 6 6-6 6"/>',
    back: '<path d="M19 12H5m6-6-6 6 6 6"/>',
    external: '<path d="M15 3h6v6m0-6L10 14M9 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-4"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    branch: '<circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="6" r="3"/><path d="M6 9v6m12-6a9 9 0 0 1-9 9"/>',
    pull_request: '<circle cx="6" cy="5" r="2"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="19" r="2"/><path d="M6 7v10m12 0V9a4 4 0 0 0-4-4h-2m3-3-3 3 3 3"/>',
    sparkles: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3ZM20 2v4m-2-2h4"/>',
    search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
    lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
    globe: '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18"/>',
    logout: '<path d="M9 4H4v16h5m5-4 4-4-4-4m-5 4h12"/>',
    alert: '<path d="m12 3 10 18H2L12 3Zm0 6v5m0 3v.1"/>',
    code: '<path d="m8 6-6 6 6 6m8-12 6 6-6 6m-3-15-2 18"/>',
    github: '<path d="M9 19c-4.3 1.3-4.3-2-6-2m12 5v-3.5c0-1 .1-1.4-.5-2 3.2-.4 6.5-1.6 6.5-7A5.4 5.4 0 0 0 19.5 6 5 5 0 0 0 19.4 2S18.2 1.6 15 3.5a13.4 13.4 0 0 0-6 0C5.8 1.6 4.6 2 4.6 2A5 5 0 0 0 4.5 6 5.4 5.4 0 0 0 3 9.5c0 5.4 3.3 6.6 6.5 7-.6.6-.6 1.2-.5 2V22"/>'
  }.freeze

  def app_icon(name, css_class: nil)
    content_tag(:svg, ICON_PATHS.fetch(name.to_sym).html_safe,
      class: [ "icon", css_class ].compact.join(" "), viewBox: "0 0 24 24", fill: "none",
      stroke: "currentColor", "stroke-width": 1.6, "stroke-linecap": "round",
      "stroke-linejoin": "round", "aria-hidden": "true")
  end

  def status_badge(scan)
    return content_tag(:span, "Sin analizar", class: "badge badge-neutral") unless scan

    tone = scan.completed? ? "success" : scan.failed? ? "error" : scan.active? ? "active" : "neutral"
    content_tag(:span, class: "badge badge-#{tone}") do
      safe_join([ content_tag(:span, "", class: "status-dot"), scan.status_label ])
    end
  end

  def scan_heading(scan)
    return { "pause" => "Pausando el análisis…", "cancel" => "Cancelando el análisis…", "restart" => "Reiniciando el análisis…" }.fetch(scan.control_action) if scan.control_action
    { "queued" => "En cola", "discovering" => "Preparando el repositorio", "analyzing" => "Analizando el código",
      "remediating" => "Preparando las mejoras", "validating" => "Verificando los cambios", "publishing" => "Publicando en GitHub",
      "paused" => "Análisis en pausa", "completed" => "Análisis completado", "failed" => "Análisis interrumpido", "cancelled" => "Análisis cancelado" }.fetch(scan.status)
  end

  def human_timestamp(time)
    time&.in_time_zone("Europe/Madrid")&.strftime("%d/%m/%Y · %H:%M") || "—"
  end

  def elapsed_time(scan)
    return "Pendiente de inicio" unless scan.started_at

    seconds = [ (scan.finished_at || Time.current) - scan.started_at, 0 ].max.to_i
    seconds < 60 ? "#{seconds} s" : "#{seconds / 60} min #{seconds % 60} s"
  end

  def severity_label(severity)
    { "critical" => "Crítica", "high" => "Alta", "medium" => "Media", "low" => "Baja", "info" => "Informativa" }.fetch(severity, severity.to_s.humanize)
  end

  def finding_status_label(status)
    { "fixed" => "Corrección propuesta", "manual" => "Revisión manual", "open" => "Pendiente" }.fetch(status, status.to_s.humanize)
  end

  def external_link(label, url, **options)
    # URLs generated by providers must never become executable links in the UI.
    uri = URI.parse(url.to_s)
    return label unless uri.is_a?(URI::HTTPS) && uri.host == "github.com"

    link_to(label, url, **options, target: "_blank", rel: "noopener noreferrer")
  rescue URI::InvalidURIError
    label
  end
end
