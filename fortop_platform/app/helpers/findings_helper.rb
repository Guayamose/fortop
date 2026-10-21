module FindingsHelper
  CATEGORIES = {
    "indexability" => "Rastreo e indexación", "metadata" => "Metadatos", "structured_data" => "Datos estructurados",
    "content" => "Contenido", "accessibility" => "Accesibilidad", "performance" => "Rendimiento", "internationalization" => "Internacionalización"
  }.freeze
  DIFF_PREVIEW_LINES = 400

  LANGUAGES = JSON.parse(Rails.root.join("config/syntax_languages.json").read).index_by { |language| language.fetch("id") }.freeze
  LANGUAGE_EXTENSIONS = LANGUAGES.values.each_with_object({}) do |language, mapping|
    ([ language["id"] ] + language["aliases"] + language["extensions"]).each { |extension| mapping[extension.downcase] = language["id"] }
  end.merge({ "htm" => "html", "xhtml" => "html", "h" => "c", "hpp" => "cpp", "cc" => "cpp", "cshtml" => "razor", "svg" => "xml", "gemfile" => "ruby", "rakefile" => "ruby", "gemspec" => "ruby", "rake" => "ruby", "containerfile" => "docker", "bashrc" => "shellscript", "zshrc" => "shellscript" }).freeze

  def finding_category(finding)
    CATEGORIES.fetch(finding.category, finding.category.to_s.humanize)
  end

  def finding_language(path)
    filename = File.basename(path.to_s).downcase
    candidates = [ filename ] + filename.split(".").drop(1).each_index.map { |index| filename.split(".").drop(index + 1).join(".") }
    id = candidates.filter_map { |extension| LANGUAGE_EXTENSIONS[extension] }.first
    LANGUAGES[id] || { "id" => "text", "name" => "Texto" }
  end

  def finding_evidence_lines(finding)
    finding.evidence.to_s.split("\n", -1)
  end

  def finding_changes(finding)
    finding.scan.changed_files.select do |file|
      file["diff"].present? && Array(file["finding_ids"]).map(&:to_i).include?(finding.id)
    end
  end

  def finding_diff_rows(patch)
    old_line = new_line = nil
    patch.to_s.lines.first(DIFF_PREVIEW_LINES).filter_map do |raw|
      text = raw.chomp
      if (header = text.match(/\A@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/))
        old_line, new_line = header.captures.map(&:to_i)
        { kind: "hunk", text: text, marker: "", old: nil, new: nil }
      elsif old_line && %w[+ - \ ].include?(text[0])
        marker = text[0]
        row = { kind: marker == "+" ? "addition" : marker == "-" ? "deletion" : "context", text: text[1..], marker: marker,
          old: marker == "+" ? nil : old_line, new: marker == "-" ? nil : new_line }
        old_line += 1 unless marker == "+"
        new_line += 1 unless marker == "-"
        row
      elsif old_line && text.start_with?("\\")
        { kind: "note", text: text, marker: "", old: nil, new: nil }
      end
    end
  end

  def finding_source_url(finding)
    sha = finding.scan.base_sha
    path = finding.file_path
    return unless sha.to_s.match?(/\A[0-9a-f]{40,64}\z/) && path.present?
    encoded = path.split("/").map { |part| ERB::Util.url_encode(part) }.join("/")
    "#{finding.scan.repository.html_url}/blob/#{sha}/#{encoded}#L#{finding.line_number || 1}"
  end
end
