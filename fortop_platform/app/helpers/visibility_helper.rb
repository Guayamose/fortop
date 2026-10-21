module VisibilityHelper
  INTENT_LABELS = { "discovery" => "Descubrimiento", "consideration" => "Consideración", "decision" => "Decisión" }.freeze
  ACTION_LABELS = { "planned" => "Pendiente", "in_progress" => "En curso", "done" => "Completada", "dismissed" => "Descartada" }.freeze

  def visibility_percent(value)
    value.nil? ? "—" : "#{number_with_precision(value, precision: 1, strip_insignificant_zeros: true)}%"
  end

  def visibility_usd(value)
    "US$ #{number_with_precision(value || 0, precision: 3)}"
  end

  def visibility_link(label, url, **options)
    safe = Visibility::Urls.public_url(url)
    safe ? link_to(label, safe, **options, target: "_blank", rel: "noopener noreferrer nofollow") : content_tag(:span, label)
  end

  def evidence_link(id, label = "Ver respuesta")
    link_to(safe_join([ label, app_icon(:arrow) ]), brand_visibility_study_observation_path(@brand, @study, id), class: "visibility-evidence-link", data: { action: "visibility-report#openEvidence" })
  end

  def visibility_ring(value)
    amount = value.to_f.clamp(0, 100)
    content_tag(:svg, viewBox: "0 0 120 120", class: "visibility-ring", role: "img", aria: { label: "Presencia: #{visibility_percent(value)}" }) do
      safe_join([
        tag.circle(cx: 60, cy: 60, r: 49, fill: "none", stroke: "#edf0f4", "stroke-width": 7),
        tag.circle(cx: 60, cy: 60, r: 49, fill: "none", stroke: "#6054d6", "stroke-width": 7, "stroke-linecap": "round", "stroke-dasharray": "#{amount * 3.079} 307.9", transform: "rotate(-90 60 60)"),
        content_tag(:text, visibility_percent(value), x: 60, y: 64, "text-anchor": "middle", class: "visibility-ring-value"),
        content_tag(:text, "presencia", x: 60, y: 81, "text-anchor": "middle", class: "visibility-ring-label")
      ])
    end
  end

  def visibility_trend(history)
    points = history.each_with_index.map { |entry, index| [ 24 + index * 552.0 / (history.size - 1), 140 - entry["presence"].to_f * 1.15 ] }
    content_tag(:svg, viewBox: "0 0 600 172", class: "visibility-trend", role: "img", aria: { label: "Evolución de la presencia entre estudios comparables" }) do
      safe_join([ 25, 82, 140 ].map { |y| tag.line(x1: 24, x2: 576, y1: y, y2: y, stroke: "#e8ecf2", "stroke-dasharray": "3 5") } + [
        tag.polyline(points: points.map { |point| point.join(",") }.join(" "), fill: "none", stroke: "#6054d6", "stroke-width": 2.5)
      ] + points.each_with_index.flat_map { |point, index| [ tag.circle(cx: point[0], cy: point[1], r: 4, fill: "#6054d6"), content_tag(:text, visibility_percent(history[index]["presence"]), x: point[0], y: point[1] - 10, "text-anchor": "middle"), content_tag(:text, "##{history[index]['id']}", x: point[0], y: 164, "text-anchor": "middle") ] })
    end
  end

  def visibility_search_widget(html)
    return if html.blank?
    fragment = Nokogiri::HTML.fragment(html)
    fragment.css("script, iframe, object, embed, form, meta, link, base").remove
    fragment.traverse do |node|
      next unless node.element?
      node.attribute_nodes.each { |attribute| node.remove_attribute(attribute.name) if attribute.name.start_with?("on") || %w[srcdoc formaction action].include?(attribute.name) }
      if node.name == "a"
        node["href"] = Visibility::Urls.public_url(node["href"]).to_s
        node["target"] = "_blank"
        node["rel"] = "noopener noreferrer"
      end
    end
    csp = "default-src 'none'; style-src 'unsafe-inline'; img-src https://www.gstatic.com https://www.google.com data:; base-uri 'none'; form-action 'none'"
    document = "<!doctype html><html lang='es'><head><meta http-equiv='Content-Security-Policy' content=\"#{csp}\"></head><body>#{fragment}</body></html>"
    tag.iframe(srcdoc: document, sandbox: "allow-popups allow-popups-to-escape-sandbox", title: "Sugerencias de búsqueda de Google", class: "visibility-search-widget", referrerpolicy: "no-referrer")
  end

  def visibility_console_phase(study)
    return { title: "Terminando la tarea en curso", description: "Tu solicitud está guardada. La respuesta en curso se conservará antes de detenernos.", icon: :clock, tone: "neutral", state: "stopping", actor: "Control de ejecución" } if study.control_action
    icon = { "researching" => :globe, "planning" => :lightbulb, "measuring" => :search, "diagnosing" => :sparkles, "paused" => :pause, "failed" => :alert, "completed" => :check, "cancelled" => :stop }.fetch(study.status, :agent)
    state = { "queued" => "waiting", "paused" => "paused", "failed" => "failed", "completed" => "completed", "cancelled" => "cancelled" }.fetch(study.status, "live")
    { title: study.status_label, description: study.pause_reason.presence || study.error_message.presence || "Investigación, respuestas y evidencia. Cada paso queda guardado.", icon: icon, tone: study.failed? ? "amber" : study.completed? ? "green" : "violet", state: state, actor: "Equipo de visibilidad" }
  end
end
