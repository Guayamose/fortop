require "json"
require "ripper"
require "nokogiri"

module Scans
  class Validator
    def initialize(workspace, node_sandbox: NodeSandbox.new, scan: nil)
      @workspace, @node_sandbox, @scan = workspace, node_sandbox, scan
    end

    def call
      results = [ check("scope", true, "Correcciones sin cupo de archivos; cada ruta, contenido y vínculo con hallazgos se verifica individualmente.") ]
      @known_domains = @workspace.read_paths.flat_map { |path| domains(@workspace.original(path).to_s) }.uniq
      @workspace.changes.each do |path, content|
        begin
          @workspace.check_writable_path!(path)
          safety = safety_errors(path, content)
          results << check("safety:#{path}", safety.empty?, safety.empty? ? "Ruta y tamaño del cambio permitidos; hallazgos vinculados." : safety.join(" "))
          results << syntax_check(path, content)
          results.concat(html_semantic_checks(path, content)) if %w[.html .htm .erb].include?(File.extname(path).downcase)
        rescue Agents::ToolError => error
          results << check("safety:#{path}", false, error.message)
        end
      end
      results.concat(finding_semantic_checks) if @scan
      results << check("coverage", true, "Comprobaciones estáticas de los archivos modificados. No se ejecutaron tests ni builds del repositorio; requieren CI y revisión del PR.")
      results
    end

    private

    def check(name, passed, details)
      { "name" => name, "passed" => passed, "details" => details }
    end

    def safety_errors(path, content)
      errors = []
      errors << "El archivo está vacío." if content.blank?
      errors << "El cambio no está vinculado a un hallazgo aceptado." if @workspace.finding_ids(path).empty?
      original = @workspace.original(path)
      errors << "El cambio elimina más de la mitad de un archivo existente." if original && original.bytesize > 200 && content.bytesize < original.bytesize / 2
      placeholders = /(?:https?:\/\/(?:www\.)?(?:example\.(?:com|org)|your[-_]?domain\.[a-z]+)|\bYOUR_(?:API_KEY|DOMAIN|BRAND)\b)/i
      errors << "El cambio introduce dominios o credenciales de ejemplo." if content.scan(placeholders).size > original.to_s.scan(placeholders).size
      sensitive = /(?:-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bAIza[0-9A-Za-z_-]{30,}|\bgh[pousr]_[0-9A-Za-z]{20,})/
      errors << "El cambio contiene un posible secreto." if content.match?(sensitive)
      if content.scan(/\bnoindex\b/i).size > original.to_s.scan(/\bnoindex\b/i).size
        errors << "El cambio introduce una directiva noindex que puede reducir la visibilidad."
      end
      blocked_root = /^\s*Disallow:\s*\/\*?\s*(?:#.*)?$/i
      if File.basename(path).downcase == "robots.txt" && content.scan(blocked_root).size > original.to_s.scan(blocked_root).size
        errors << "El cambio introduce un bloqueo completo del rastreo en robots.txt."
      end
      introduced_domains = domains(content) - domains(original.to_s) - @known_domains - %w[schema.org www.schema.org www.w3.org ogp.me]
      errors << "El cambio introduce dominios que no aparecen en el código inspeccionado: #{introduced_domains.join(", ")}." if introduced_domains.any?
      errors
    end

    def domains(content)
      content.scan(%r{https?://([a-z0-9][a-z0-9.-]*\.[a-z]{2,})(?=[:/\s"'<>]|\z)}i).flatten.map(&:downcase).uniq
    end

    def html_semantic_checks(path, content)
      document = Nokogiri::HTML5(content)
      checks = []
      document.css('script[type="application/ld+json"]').each_with_index do |script, index|
        raw = script.text.strip
        next if raw.include?("<%") # Runtime JSON generation requires repository CI.
        begin
          data = JSON.parse(raw)
          valid = data.is_a?(Hash) || data.is_a?(Array)
          checks << check("json_ld:#{path}:#{index + 1}", valid, "El bloque JSON-LD estático debe ser un objeto o una lista JSON válidos.")
        rescue JSON::ParserError
          checks << check("json_ld:#{path}:#{index + 1}", false, "El bloque JSON-LD estático no contiene JSON válido.")
        end
      end
      checks
    end

    def finding_semantic_checks
      ids = @workspace.changed_files.flat_map { |file| file["finding_ids"] }.uniq
      @scan.findings.where(id: ids).flat_map do |finding|
        paths = @workspace.changes.keys.select { |path| @workspace.finding_ids(path).include?(finding.id) && %w[.html .htm .erb].include?(File.extname(path).downcase) }
        next [] if paths.empty?
        text = "#{finding.title} #{finding.recommendation}".downcase
        expectations = []
        expectations << [ "description", 'meta[name="description"]', "content" ] if finding.category == "metadata" && text.match?(/descripci[oó]n|description/)
        expectations << [ "title", "title", nil ] if finding.category == "metadata" && text.match?(/t[ií]tulo|\btitle\b/)
        expectations << [ "canonical", 'link[rel="canonical"]', "href" ] if text.match?(/canonical|can[oó]nic/)
        expectations << [ "language", "html[lang]", "lang" ] if %w[accessibility internationalization].include?(finding.category) && text.match?(/idioma|language|\blang\b/)
        if finding.category == "structured_data" && text.match?(/json[\s-]?ld|schema/)
          expectations << [ "json_ld", 'script[type="application/ld+json"]', nil ]
        end
        expectations.map do |label, selector, attribute|
          changed = paths.any? do |path|
            before = selected_values(@workspace.original(path).to_s, selector, attribute)
            after = selected_values(@workspace.changes[path], selector, attribute)
            after.present? && after != before && after.all?(&:present?)
          end
          check("semantic:#{finding.id}:#{label}", changed, "La corrección propuesta debe modificar #{label} con un valor no vacío en el HTML/ERB inspeccionado. La revisión y el despliegue siguen pendientes.")
        end
      end
    end

    def selected_values(content, selector, attribute)
      Nokogiri::HTML5(content).css(selector).map { |node| (attribute ? node[attribute] : node.text).to_s.strip }
    end

    def syntax_check(path, content)
      name = "syntax:#{path}"
      case File.extname(path).downcase
      when ".json", ".webmanifest"
        JSON.parse(content)
        check(name, true, "JSON válido.")
      when ".xml"
        Nokogiri::XML(content) { |config| config.strict.nonet }
        check(name, true, "XML válido; acceso a red y entidades externas desactivado.")
      when ".rb"
        check(name, !Ripper.sexp(content).nil?, "Análisis sintáctico Ruby sin ejecutar código.")
      when ".erb"
        # Rails' Erubi supports block helpers unlike plain ERB. Parsing the generated
        # Ruby validates syntax without evaluating the template or loading the repo.
        source = ActionView::Template::Handlers::ERB::Erubi.new(content).src
        check(name, !Ripper.sexp(source).nil?, "Sintaxis de plantilla Rails ERB comprobada sin ejecutarla.")
      when ".html", ".htm"
        document = Nokogiri::HTML5(content, max_errors: 30)
        original = @workspace.original(path)
        critical = []
        critical << "Se ha perdido la etiqueta head." if original.to_s.match?(/<head[\s>]/i) && !content.match?(/<head[\s>]/i)
        critical << "Se ha perdido la etiqueta body." if original.to_s.match?(/<body[\s>]/i) && !content.match?(/<body[\s>]/i)
        critical << "Hay etiquetas HTML sin terminar." if document.errors.any? { |error| error.message.match?(/eof-in-tag|eof-in-comment|eof-in-element-that-can-contain-only-text/) }
        check(name, critical.empty?, critical.empty? ? "HTML analizado; se conservan las secciones principales existentes." : critical.join(" "))
      when ".js", ".mjs", ".cjs"
        @node_sandbox.check(content).merge("name" => name)
      when ".txt", ".md"
        check(name, true, "Texto UTF-8 válido; sin ejecución de código.")
      else
        check(name, false, "No hay un validador seguro configurado para #{File.extname(path)}. Descarta este cambio y solicita intervención manual.")
      end
    rescue JSON::ParserError, Nokogiri::XML::SyntaxError, SyntaxError => error
      check(name, false, "Error sintáctico: #{error.message.to_s.truncate(600)}")
    end
  end
end
