require "rouge"

module FindingsHelper
  CATEGORIES = {
    "indexability" => "Rastreo e indexación", "metadata" => "Metadatos", "structured_data" => "Datos estructurados",
    "content" => "Contenido", "accessibility" => "Accesibilidad", "performance" => "Rendimiento", "internationalization" => "Internacionalización"
  }.freeze
  DIFF_PREVIEW_LINES = 400

  class LineFormatter < Rouge::Formatters::HTML
    def lines(tokens)
      # The formatter escapes repository text before adding its own token spans.
      token_lines(tokens).map { |line| format(line).html_safe }
    end
  end

  def finding_category(finding)
    CATEGORIES.fetch(finding.category, finding.category.to_s.humanize)
  end

  def finding_lexer(source, path)
    Rouge::Lexer.guess(filename: path.to_s.presence, source: source.to_s)
  rescue Rouge::Lexer::Guesser::Ambiguous, Rouge::Lexer::Guesser::NoLexersFound
    Rouge::Lexers::PlainText
  end

  def highlighted_evidence(finding)
    highlighted_source_lines(finding.evidence, finding.file_path)
  end

  def finding_changes(finding)
    finding.scan.changed_files.select do |file|
      file["diff"].present? && Array(file["finding_ids"]).map(&:to_i).include?(finding.id)
    end
  end

  def finding_diff_rows(patch, path:)
    old_line = new_line = nil
    rows = patch.to_s.lines.first(DIFF_PREVIEW_LINES).filter_map do |raw|
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
    rows.slice_before { |row| row[:kind] == "hunk" }.each do |hunk|
      original = hunk.select { |row| %w[context deletion].include?(row[:kind]) }
      proposed = hunk.select { |row| %w[context addition].include?(row[:kind]) }
      before = highlighted_source_lines(original.map { |row| row[:text] }.join("\n"), path)
      after = highlighted_source_lines(proposed.map { |row| row[:text] }.join("\n"), path)
      hunk.each do |row|
        case row[:kind]
        when "deletion" then row[:html] = before.shift
        when "addition" then row[:html] = after.shift
        when "context"
          before.shift
          row[:html] = after.shift
        end
      end
    end
    rows
  end

  def finding_source_url(finding)
    sha = finding.scan.base_sha
    path = finding.file_path
    return unless sha.to_s.match?(/\A[0-9a-f]{40,64}\z/) && path.present?
    encoded = path.split("/").map { |part| ERB::Util.url_encode(part) }.join("/")
    "#{finding.scan.repository.html_url}/blob/#{sha}/#{encoded}#L#{finding.line_number || 1}"
  end

  private

  def highlighted_source_lines(source, path)
    LineFormatter.new.lines(finding_lexer(source, path).new.lex(source.to_s))
  end
end
