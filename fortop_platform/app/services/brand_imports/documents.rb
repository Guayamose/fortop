require "zip"
require "timeout"

module BrandImports
  class Documents
    MAX_FILES = 10
    MAX_FILE_BYTES = 20.megabytes
    MAX_TOTAL_BYTES = 50.megabytes
    MAX_TEXT = 300_000
    EXTENSIONS = %w[.pdf .docx .pptx .txt .md .csv .json].freeze
    MIME_TYPES = { ".pdf" => "application/pdf", ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      ".pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation", ".txt" => "text/plain",
      ".md" => "text/markdown", ".csv" => "text/csv", ".json" => "application/json" }.freeze

    def self.validate_uploads!(files)
      raise Visibility::Error, "Añade entre 1 y #{MAX_FILES} documentos." unless files.size.between?(1, MAX_FILES)
      files.each do |file|
        unless file.respond_to?(:original_filename) && EXTENSIONS.include?(File.extname(file.original_filename).downcase)
          raise Visibility::Error, "Usa archivos PDF, DOCX, PPTX, TXT, MD, CSV o JSON."
        end
        raise Visibility::Error, "Cada archivo debe ocupar entre 1 byte y 20 MB." unless file.size.between?(1, MAX_FILE_BYTES)
      end
      raise Visibility::Error, "Los documentos no pueden superar 50 MB en total." if files.sum(&:size) > MAX_TOTAL_BYTES
    end

    def self.extract(document)
      text = document.file.open do |file|
        case File.extname(document.file.filename.to_s).downcase
        when ".pdf" then pdf(file.path)
        when ".docx" then office(file.path, :word)
        when ".pptx" then office(file.path, :slides)
        else file.read(MAX_TEXT * 4 + 1).force_encoding(Encoding::UTF_8)
        end
      end
      text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").delete("\u0000").strip
      if text.length > MAX_TEXT
        raise Visibility::Error, "#{document.file.filename}: el documento supera los 300.000 caracteres de contexto. Divide el archivo antes de subirlo."
      end
      if text.length < 15
        raise Visibility::Error, "#{document.file.filename}: no encontramos texto legible. Si es un PDF escaneado, expórtalo con reconocimiento de texto (OCR)."
      end
      text
    rescue Zip::Error, Nokogiri::XML::SyntaxError, EncodingError
      raise Visibility::Error, "No se ha podido leer #{document.file.filename}. Comprueba que el archivo no esté dañado o protegido."
    end

    def self.pdf(path)
      output = Tempfile.new([ "fortop-pdf", ".txt" ])
      stderr = Tempfile.new("fortop-pdf-error")
      pid = Process.spawn("pdftotext", "-enc", "UTF-8", "-nopgbrk", path, output.path, out: File::NULL, err: stderr.path, pgroup: true)
      Timeout.timeout(25) { Process.wait(pid) }
      raise Visibility::Error, "No se ha podido leer el PDF. Comprueba que no esté dañado o protegido con contraseña." unless $?.success?
      raise Visibility::Error, "El PDF contiene demasiado texto. Divídelo en documentos más pequeños." if output.size > MAX_TEXT * 4
      File.binread(output.path, MAX_TEXT * 4 + 1).force_encoding(Encoding::UTF_8)
    rescue Timeout::Error
      Process.kill("KILL", -pid) rescue nil
      Process.wait(pid) rescue nil
      raise Visibility::Error, "El PDF tarda demasiado en abrirse. Prueba a exportarlo de nuevo."
    rescue Errno::ENOENT
      raise Visibility::Error, "La lectura de PDF no está disponible en el servidor."
    ensure
      output&.close!
      stderr&.close!
    end

    def self.office(path, kind)
      Zip::File.open(path) do |archive|
        names = archive.entries.select do |entry|
          kind == :word ? entry.name.match?(%r{\Aword/(?:document|header\d+|footer\d+|footnotes|endnotes)\.xml\z}) : entry.name.match?(%r{\Appt/(?:slides/slide|notesSlides/notesSlide)\d+\.xml\z})
        end.sort_by { |entry| [ entry.name[/\d+/].to_i, entry.name ] }
        raise Visibility::Error, "El archivo no contiene un documento de Office válido." if names.empty?
        raise Visibility::Error, "El documento contiene demasiado texto o demasiadas secciones." if names.size > 500 || names.sum(&:size) > 8.megabytes
        names.map do |entry|
          xml = entry.get_input_stream { |stream| stream.read(8.megabytes + 1) }
          raise Visibility::Error, "El documento contiene una sección demasiado grande." if xml.bytesize > 8.megabytes
          parsed = Nokogiri::XML(xml) { |config| config.strict.nonet }
          parsed.xpath("//*[local-name()='p']").map { |paragraph| paragraph.xpath(".//*[local-name()='t']").map(&:text).join }.join("\n")
        end.join("\n\n")
      end
    end
  end
end
