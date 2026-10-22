module Admin
  module ExecutionCatalog
    MODELS = { "scans" => Scan, "studies" => VisibilityStudy, "imports" => BrandImport }.freeze
    module_function

    def kind(record)
      MODELS.key(record.class)
    end

    def scope(kind, state: nil, user: nil)
      records = MODELS.fetch(kind).all
      records = case kind
      when "scans"
        records = records.where(repository_id: user.repositories.select(:id)) if user
        records.includes(repository: :user)
      when "studies"
        records = records.where(brand_id: user.brands.select(:id)) if user
        records.includes(brand: :user)
      when "imports"
        records = records.where(user_id: user.id) if user
        records.includes(:user)
      end
      return records unless state
      if state == "active"
        statuses = kind == "imports" ? %w[queued extracting interpreting] : MODELS.fetch(kind)::ACTIVE_STATUSES
        records.where(status: statuses)
      else
        records.where(status: state)
      end
    end

    def recent(user: nil, state: nil, limit: 8)
      MODELS.keys.flat_map { |key| scope(key, user: user, state: state).order(created_at: :desc, id: :desc).limit(limit).to_a }
        .sort_by { |entry| [ entry.created_at, entry.id ] }.reverse.first(limit)
    end
  end
end
