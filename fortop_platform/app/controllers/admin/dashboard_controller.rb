module Admin
  class DashboardController < BaseController
    def show
      @overview = Overview.new
      @recent = ExecutionCatalog.recent(limit: 8)
      @failures = ExecutionCatalog.recent(state: "failed", limit: 6)
      @events = AdminAuditEvent.includes(:actor).recent.limit(5)
    end
  end
end
