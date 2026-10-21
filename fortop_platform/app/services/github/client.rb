require "base64"
require "uri"

module Github
  class Client
    MAX_FILE_BYTES = 1.megabyte
    MAX_LOOKUP_PAGES = 10

    def initialize(token = nil, http: Github::Http.new, authorized_repository_id: nil, **options)
      @token = token || options[:token]
      @http = http
      @authorized_repository_id = bounded_integer(authorized_repository_id, 1..9_223_372_036_854_775_807) if authorized_repository_id.present?
      raise Error, "Inicia sesión con GitHub para continuar." if @token.blank?
    end

    # Set only by Access after checking visitor authorization and the actual
    # installation token grant. Repository metadata's push flag describes user
    # permissions and can be false even for a writable App installation token.
    def write_authorized_for?(repository_id)
      @authorized_repository_id.present? && @authorized_repository_id.to_s == repository_id.to_s
    end

    def user
      request("/user")
    end

    def installations(page: 1, per_page: 100)
      request("/user/installations", query: {
        page: bounded_integer(page, 1..10_000), per_page: bounded_integer(per_page, 1..100)
      }).fetch("installations")
    end

    def installation_repositories(installation_id, page: 1, per_page: 100)
      id = bounded_integer(installation_id, 1..9_223_372_036_854_775_807)
      request("/user/installations/#{id}/repositories", query: {
        page: bounded_integer(page, 1..10_000), per_page: bounded_integer(per_page, 1..100)
      }).fetch("repositories")
    end

    def repositories(page: 1, per_page: 100)
      request("/user/repos", query: {
        page: bounded_integer(page, 1..10_000), per_page: bounded_integer(per_page, 1..100),
        sort: "pushed", direction: "desc", affiliation: "owner,collaborator,organization_member"
      })
    end

    def repository(full_name)
      request(repo_path(full_name))
    end

    def branch_sha(full_name, branch)
      request("#{repo_path(full_name)}/git/ref/heads/#{encode_ref(branch)}").fetch("object").fetch("sha")
    end

    def tree(full_name, sha)
      result = request("#{repo_path(full_name)}/git/trees/#{encode_sha(sha)}", query: { recursive: "1" })
      if result["truncated"]
        raise Error, "El árbol del repositorio supera el tamaño permitido para una ejecución completa."
      end
      result.fetch("tree")
    end

    def file(full_name, path, ref:)
      data = request("#{repo_path(full_name)}/contents/#{encode_path(path)}", query: { ref: ref.to_s })
      unless data.is_a?(Hash) && data["type"] == "file" && data["encoding"] == "base64" && data["size"].to_i <= MAX_FILE_BYTES
        raise Error, "GitHub no ha devuelto un archivo de texto compatible."
      end
      content = Base64.strict_decode64(data.fetch("content").delete("\n\r"))
      content.force_encoding(Encoding::UTF_8)
      unless content.valid_encoding? && !content.include?("\0") && content.bytesize <= MAX_FILE_BYTES
        raise Error, "El archivo no es texto UTF-8 válido o supera el tamaño permitido."
      end
      content
    rescue ArgumentError, KeyError
      raise Error, "No se ha podido interpretar el archivo de GitHub."
    end

    def create_issue(full_name, title:, body:)
      request("#{repo_path(full_name)}/issues", method: :post, body: { title: title, body: body })
    end

    def find_issue(full_name, marker:)
      raise Error, "El identificador del hallazgo no es válido." if marker.blank? || marker.bytesize > 500
      each_page("#{repo_path(full_name)}/issues", state: "all", sort: "created", direction: "desc") do |issues|
        found = issues.find { |issue| !issue["pull_request"] && issue["body"].to_s.include?(marker) }
        return found if found
      end
      nil
    end

    def find_pull_request(full_name, head:)
      validate_managed_branch!(head)
      owner = full_name.split("/").first
      each_page("#{repo_path(full_name)}/pulls", state: "all", head: "#{owner}:#{head}") do |pulls|
        found = pulls.find { |pull| pull.dig("head", "ref") == head }
        return found if found
      end
      nil
    end

    def create_branch(full_name, name:, sha:)
      validate_managed_branch!(name)
      request("#{repo_path(full_name)}/git/refs", method: :post, body: { ref: "refs/heads/#{name}", sha: encode_sha(sha) })
    end

    # Construct a single commit from a captured base. The caller owns all files
    # and GitHub rejects a non-fast-forward update if another writer wins.
    def commit_files(full_name, branch:, base_sha:, files:, message:)
      validate_managed_branch!(branch)
      if repository(full_name).fetch("default_branch") == branch
        raise Error, "La rama principal no se puede modificar directamente."
      end
      encode_sha(base_sha)
      raise Error, "No hay cambios válidos para publicar." unless files.is_a?(Hash) && files.present? && files.size <= 30
      unless branch_sha(full_name, branch) == base_sha
        raise Error.new("La rama de remediación ha cambiado. No se han sobrescrito sus cambios.", status: 409)
      end

      prefix = repo_path(full_name)
      base_commit = request("#{prefix}/git/commits/#{encode_sha(base_sha)}")
      base_tree_sha = base_commit.fetch("tree").fetch("sha")
      modes = tree(full_name, base_sha).to_h { |entry| [ entry.fetch("path"), entry ] }
      entries = files.map do |path, content|
        encode_path(path)
        unless content.is_a?(String) && content.valid_encoding? && !content.include?("\0") && content.bytesize <= MAX_FILE_BYTES
          raise Error, "Una corrección no contiene texto válido o supera el tamaño permitido."
        end
        existing = modes[path]
        if existing && (existing["type"] != "blob" || !%w[100644 100755].include?(existing["mode"]))
          raise Error, "No se pueden modificar enlaces simbólicos, submódulos o directorios."
        end
        { path: path, mode: existing&.fetch("mode") || "100644", type: "blob", content: content }
      end

      new_tree = request("#{prefix}/git/trees", method: :post, body: { base_tree: base_tree_sha, tree: entries })
      commit = request("#{prefix}/git/commits", method: :post, body: {
        message: message, tree: new_tree.fetch("sha"), parents: [ base_sha ]
      })
      request("#{prefix}/git/refs/heads/#{encode_ref(branch)}", method: :patch, body: { sha: commit.fetch("sha"), force: false })
      commit
    end

    def create_pull_request(full_name, head:, base:, title:, body:)
      validate_managed_branch!(head)
      raise Error, "La rama de origen y destino no pueden coincidir." if head == base
      request("#{repo_path(full_name)}/pulls", method: :post, body: {
        head: head, base: base, title: title, body: body, maintainer_can_modify: true
      })
    end

    private

    def request(path, method: :get, query: nil, body: nil)
      uri = URI("https://api.github.com#{path}")
      uri.query = URI.encode_www_form(query) if query.present?
      @http.request(uri, method: method, token: @token, body: body)
    end

    def each_page(path, **query)
      1.upto(MAX_LOOKUP_PAGES) do |page|
        entries = request(path, query: query.merge(page: page, per_page: 100))
        yield entries
        return if entries.size < 100
      end
      raise Error, "Hay demasiados resultados en GitHub para verificar las publicaciones anteriores."
    end

    def repo_path(full_name)
      unless full_name.is_a?(String) && full_name.match?(%r{\A[A-Za-z0-9][A-Za-z0-9-]{0,99}/[A-Za-z0-9_.-]{1,100}\z}) &&
          !%w[. ..].include?(full_name.split("/").last)
        raise Error, "El nombre del repositorio no es válido."
      end
      "/repos/#{full_name}"
    end

    def encode_path(path)
      unless path.is_a?(String) && path.bytesize.between?(1, 1024) && !path.match?(/[\\\x00-\x1f\x7f]/) &&
          path.split("/", -1).none? { |segment| segment.empty? || %w[. .. .git].include?(segment.downcase) }
        raise Error, "La ruta del archivo no es válida."
      end
      path.split("/").map { |part| URI.encode_www_form_component(part).gsub("+", "%20") }.join("/")
    end

    def encode_ref(ref)
      unless ref.is_a?(String) && ref.present? && ref.bytesize <= 250 && !ref.match?(/[\x00-\x20\x7f\\~^:?*\[]/) &&
          !ref.include?("..") && !ref.include?("@{") && !ref.include?("//") && !ref.start_with?("/", ".") &&
          !ref.end_with?("/", ".", ".lock")
        raise Error, "La rama de GitHub no es válida."
      end
      URI.encode_www_form_component(ref).gsub("+", "%20")
    end

    def encode_sha(sha)
      raise Error, "El identificador del commit no es válido." unless sha.is_a?(String) && sha.match?(/\A[0-9a-f]{40,64}\z/)
      sha
    end

    def validate_managed_branch!(branch)
      encode_ref(branch)
      raise Error, "Solo se pueden publicar cambios en ramas de Fortop." unless branch.start_with?("fortop/")
    end

    def bounded_integer(value, range)
      integer = Integer(value)
      raise ArgumentError unless range.cover?(integer)
      integer
    rescue ArgumentError, TypeError
      raise Error, "Los parámetros de paginación no son válidos."
    end
  end
end
