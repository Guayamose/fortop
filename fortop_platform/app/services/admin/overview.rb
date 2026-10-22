module Admin
  class Overview
    JSON_SUMS = {
      scan_requests: "CASE WHEN metadata #>> '{usage,requests}' ~ '^[0-9]{1,15}$' THEN (metadata #>> '{usage,requests}')::bigint ELSE 0 END",
      scan_tokens: "CASE WHEN metadata #>> '{usage,total_tokens}' ~ '^[0-9]{1,15}$' THEN (metadata #>> '{usage,total_tokens}')::bigint ELSE 0 END",
      import_tokens: "CASE WHEN usage #>> '{total_tokens}' ~ '^[0-9]{1,15}$' THEN (usage #>> '{total_tokens}')::bigint ELSE 0 END"
    }.freeze
    attr_reader :users, :repositories, :brands, :scans, :studies, :imports

    def initialize(user: nil)
      @users = user ? User.where(id: user.id) : User.all
      @repositories = Repository.where(user_id: @users.select(:id))
      @brands = Brand.where(user_id: @users.select(:id))
      @scans = Scan.where(repository_id: @repositories.select(:id))
      @studies = VisibilityStudy.where(brand_id: @brands.select(:id))
      @imports = BrandImport.where(user_id: @users.select(:id))
    end

    def active_count
      scans.active.count + studies.active.count + imports.where(status: %w[queued extracting interpreting]).count
    end

    def failed_count
      scans.failed.count + studies.failed.count + imports.failed.count
    end

    def usage
      @usage ||= [
        { label: "Repositorios", requests: json_sum(scans, :scan_requests), tokens: json_sum(scans, :scan_tokens), cost: nil },
        { label: "Visibilidad de marca", requests: studies.sum(:request_count), tokens: studies.sum(:token_count), cost: studies.sum(:spent_usd) },
        { label: "Lectura de documentos", requests: imports.sum(:request_count), tokens: json_sum(imports, :import_tokens), cost: imports.sum(:spent_usd) }
      ]
    end

    def estimated_spend
      usage.sum { |row| row[:cost] || 0 }
    end

    private

    def json_sum(scope, key)
      scope.sum(Arel.sql(JSON_SUMS.fetch(key))).to_i
    end
  end
end
