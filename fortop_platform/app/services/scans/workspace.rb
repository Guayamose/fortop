require "tmpdir"
require "fileutils"
require "set"

module Scans
  class Workspace
    MAX_FILE_BYTES = 100_000
    MAX_TOTAL_BYTES = 2_000_000
    MAX_READ_FILES = 100
    MAX_CHANGED_FILES = 5
    MAX_TREE_FILES = 20_000
    TEXT_EXTENSIONS = %w[.html .htm .erb .rb .js .mjs .cjs .jsx .ts .tsx .json .xml .txt .md .mdx .yaml .yml .css .scss .vue .svelte .php .astro .haml .slim .ejs .liquid .webmanifest].freeze
    IGNORED_DIRECTORIES = %w[.git .github .bundle node_modules vendor tmp log storage coverage dist build .next .nuxt .cache].freeze
    SECRET_NAME = /(?:\A\.env(?:\.|\z)|credentials|secrets?|private[_-]?key|master\.key|id_rsa|id_ed25519|\.pem\z|\.p12\z|\.pfx\z|\.key\z|service[_-]?account)/i
    READ_ONLY_NAMES = %w[Gemfile Gemfile.lock package.json package-lock.json yarn.lock pnpm-lock.yaml bun.lock bun.lockb Dockerfile docker-compose.yml compose.yml Procfile].freeze
    # Recognizable provider prefixes plus long token bodies avoid treating ordinary
    # identifiers as credentials. AQ without a separator additionally requires an
    # explicit key/token assignment. This is a conservative filter, not a complete
    # secret scanner; matching files are excluded in full and never rewritten.
    CONTENT_SECRET_PATTERNS = [
      /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/,
      /\bAIza[0-9A-Za-z_-]{30,}/,
      /\bAQ\.[0-9A-Za-z_.-]{30,}/,
      /\bgh[pousr]_[0-9A-Za-z]{20,}/,
      /\bgithub_pat_[0-9A-Za-z_]{30,}/,
      /\bsk-(?:proj-|ant-|svcacct-)?[0-9A-Za-z_-]{20,}/,
      /\bya29\.[0-9A-Za-z_.-]{30,}/,
      /\b[a-z0-9_]*(?:api[_-]?key|token|credential|secret)[a-z0-9_]*["']?\s*[:=]\s*["']AQ[0-9A-Za-z_.-]{30,}/i
    ].freeze

    attr_reader :directory, :read_paths, :changes, :total_files

    def initialize(github:, full_name:, sha:, tree:)
      @github, @full_name, @sha = github, full_name, sha
      @total_files = tree.count { |entry| entry["type"] == "blob" }
      raise Agents::ToolError, "El repositorio supera el límite de 20.000 archivos para este MVP." if @total_files > MAX_TREE_FILES

      @entries = tree.select { |entry| entry["type"] == "blob" && %w[100644 100755].include?(entry["mode"].to_s) && readable_path?(entry["path"]) }.index_by { |entry| entry["path"] }
      @unsafe_paths = tree.filter_map { |entry| entry["path"] if entry["mode"].to_s == "120000" || entry["type"] == "commit" }
      @directory = Dir.mktmpdir("fortop-scan-")
      @originals, @changes, @read_paths, @finding_ids = {}, {}, Set.new, {}
      @blocked_paths = Set.new
      @total_bytes = 0
    end

    def list_files(prefix: "", offset: 0)
      paths = (@entries.keys + @changes.keys).uniq.sort.select { |path| path.start_with?(prefix.to_s) && !@blocked_paths.include?(path) }
      { "files" => paths.drop(offset.to_i.clamp(0, MAX_TREE_FILES)).first(200), "total" => paths.length, "next_offset" => offset.to_i + 200 < paths.length ? offset.to_i + 200 : nil }
    end

    def read(path)
      check_path!(path)
      return @changes[path] if @changes.key?(path)
      return @originals[path] if @originals.key?(path)

      entry = @entries[path]
      raise Agents::ToolError, "Archivo inexistente o excluido de la lectura." unless entry
      raise Agents::ToolError, "Se ha alcanzado el límite de archivos leídos." if @originals.size >= MAX_READ_FILES
      raise Agents::ToolError, "El archivo supera los 100 KB." if entry["size"].to_i > MAX_FILE_BYTES

      content = @github.file(@full_name, path, ref: @sha).dup.force_encoding(Encoding::UTF_8)
      raise Agents::ToolError, "El archivo no es texto UTF-8 válido." unless content.valid_encoding? && !content.include?("\0")
      raise Agents::ToolError, "El archivo supera los 100 KB." if content.bytesize > MAX_FILE_BYTES
      raise Agents::ToolError, "Se ha alcanzado el límite de datos leídos." if @total_bytes + content.bytesize > MAX_TOTAL_BYTES
      if secret_content?(content)
        @blocked_paths << path
        raise Agents::ToolError, "El archivo se ha excluido porque contiene un posible secreto. No se enviará al proveedor ni se modificará."
      end

      @total_bytes += content.bytesize
      @originals[path] = content
      @read_paths << path
      materialize(path, content)
      content
    end

    def read_lines(path, start_line: 1, end_line: 200)
      content = read(path)
      first = Integer(start_line).clamp(1, 100_000)
      last = Integer(end_line).clamp(first, first + 299)
      lines = content.lines
      { "path" => path, "total_lines" => lines.length, "content" => lines[(first - 1)..(last - 1)].to_a.each_with_index.map { |line, i| "#{first + i}: #{line}" }.join.truncate(24_000), "trust" => "untrusted_repository_data" }
    rescue ArgumentError, TypeError
      raise Agents::ToolError, "El rango de líneas no es válido."
    end

    def search(query, prefix: "")
      raise Agents::ToolError, "La búsqueda debe contener entre 2 y 120 caracteres." unless query.is_a?(String) && query.length.between?(2, 120)

      matches = []
      paths = @entries.keys.select { |path| path.start_with?(prefix.to_s) }.sort_by { |path| [ seo_priority(path), path ] }
      inspected = 0
      paths.first(45).each do |path|
        begin
          content = read(path)
        rescue Agents::ToolError
          next
        end
        inspected += 1
        content.lines.each_with_index do |line, index|
          matches << { "path" => path, "line" => index + 1, "text" => line.strip.truncate(400) } if line.downcase.include?(query.downcase)
          break if matches.length >= 40
        end
        break if matches.length >= 40
      end
      { "matches" => matches, "searched_files" => inspected, "limited" => paths.length > inspected, "trust" => "untrusted_repository_data" }
    end

    def write(path, content, finding_ids: [])
      check_writable_path!(path)
      raise Agents::ToolError, "Lee el archivo existente antes de modificarlo." if @entries.key?(path) && !@read_paths.include?(path)
      raise Agents::ToolError, "La corrección supera el límite de cinco archivos." if !@changes.key?(path) && @changes.size >= MAX_CHANGED_FILES
      raise Agents::ToolError, "El contenido debe ser texto UTF-8 de menos de 100 KB." unless content.is_a?(String) && content.valid_encoding? && content.bytesize <= MAX_FILE_BYTES && !content.include?("\0")
      raise Agents::ToolError, "El contenido propuesto contiene un posible secreto y no se guardará." if secret_content?(content)

      if content == @originals[path]
        discard(path)
      else
        @changes[path] = content
        @finding_ids[path] = (@finding_ids.fetch(path, []) + finding_ids.map(&:to_i)).uniq
        materialize(path, content)
      end
      { "path" => path, "changed" => @changes.key?(path), "bytes" => content.bytesize }
    end

    def replace(path, old_text, new_text, finding_ids: [])
      content = read(path)
      raise Agents::ToolError, "El texto a sustituir debe aparecer exactamente una vez." unless old_text.is_a?(String) && old_text.present? && content.scan(Regexp.new(Regexp.escape(old_text))).length == 1
      write(path, content.sub(old_text, new_text.to_s), finding_ids: finding_ids)
    end

    def discard(path)
      check_path!(path)
      @changes.delete(path)
      @finding_ids.delete(path)
      if @originals.key?(path)
        materialize(path, @originals[path])
      else
        FileUtils.rm_f(File.join(@directory, path))
      end
      { "path" => path, "discarded" => true }
    end

    def original(path)
      @originals[path]
    end

    def finding_ids(path)
      @finding_ids.fetch(path, [])
    end

    def changed_files
      @changes.map do |path, content|
        before = @originals.fetch(path, "").lines
        after = content.lines
        # Counts are deterministic and bounded without invoking git or repository code.
        before_counts, after_counts = before.tally, after.tally
        common = before_counts.sum { |line, count| [ count, after_counts.fetch(line, 0) ].min }
        { "path" => path, "additions" => after.length - common, "deletions" => before.length - common, "finding_ids" => finding_ids(path) }
      end
    end

    def coverage
      { "total_files" => @total_files, "eligible_files" => @entries.size, "read_files" => @read_paths.size, "limits" => "Análisis estático acotado: hasta #{MAX_READ_FILES} archivos de texto, #{MAX_TOTAL_BYTES / 1_000_000} MB y cinco archivos modificados. Se excluyen secretos, dependencias, binarios y enlaces simbólicos." }
    end

    def close
      FileUtils.remove_entry_secure(@directory) if @directory && File.directory?(@directory)
    end

    def check_writable_path!(path)
      check_path!(path)
      raise Agents::ToolError, "Este archivo está protegido frente a modificaciones automáticas." if READ_ONLY_NAMES.include?(File.basename(path)) || path.start_with?("config/", "bin/", "script/", "scripts/", "test/", "spec/") || path.end_with?(".lock")
      if @entries[path] && @entries[path]["mode"].to_s != "100644"
        raise Agents::ToolError, "No se modifican archivos ejecutables."
      end
      true
    end

    private

    def check_path!(path)
      raise Agents::ToolError, "Ruta no permitida." unless readable_path?(path)
      raise Agents::ToolError, "El archivo está excluido por contener un posible secreto." if @blocked_paths.include?(path)
      raise Agents::ToolError, "No se accede a enlaces simbólicos ni submódulos." if @unsafe_paths.any? { |unsafe| path == unsafe || path.start_with?("#{unsafe}/") }
      true
    end

    def readable_path?(path)
      return false unless path.is_a?(String) && path.bytesize.between?(1, 300) && !path.match?(/[\x00-\x1f\\]/)
      return false if path.start_with?("/") || path.split("/").any? { |part| part.blank? || %w[. ..].include?(part) || IGNORED_DIRECTORIES.include?(part) || SECRET_NAME.match?(part) }
      return false if path.split("/").any? { |part| part.start_with?(".") }
      TEXT_EXTENSIONS.include?(File.extname(path).downcase) || READ_ONLY_NAMES.include?(File.basename(path))
    end

    def secret_content?(content)
      CONTENT_SECRET_PATTERNS.any? { |pattern| content.match?(pattern) }
    end

    def materialize(path, content)
      absolute = File.join(@directory, path)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, content)
    end

    def seo_priority(path)
      path.match?(/(?:layout|head|index|page|robots|sitemap|llms|metadata)/i) ? 0 : 1
    end
  end
end
