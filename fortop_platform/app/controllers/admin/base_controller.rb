module Admin
  class BaseController < ApplicationController
    before_action :protect_admin_response
    before_action :require_admin

    private

    def protect_admin_response
      no_store
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end

    def require_admin
      head :not_found unless current_user&.admin?
    end

    def audit!(action, subject, details = {})
      AdminAuditEvent.create!(actor: current_user, action: action, subject: subject, details: details)
    end

    def paginate(scope)
      @page = params[:page].to_i.clamp(1, 100_000)
      @total = scope.count
      @pages = [ (@total / 25.0).ceil, 1 ].max
      @page = [ @page, @pages ].min
      scope.limit(25).offset((@page - 1) * 25)
    end

    def search(scope, *columns)
      @query = params[:q].to_s.strip.first(100)
      return scope if @query.blank?
      # Column names are supplied only by controllers, never request parameters.
      query = columns.map { |column| "#{column} ILIKE :q" }.join(" OR ")
      scope.where(query, q: "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%")
    end
  end
end
