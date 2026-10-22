module Admin
  class AuditEventsController < BaseController
    def index
      @events = paginate(AdminAuditEvent.includes(:actor).recent)
    end
  end
end
