module Admin
  class ActivityController < BaseController
    before_action :set_execution, only: %i[show control]

    def index
      @kind = ExecutionCatalog::MODELS.key?(params[:kind]) ? params[:kind] : "scans"
      @state = %w[active failed completed cancelled paused].include?(params[:state]) ? params[:state] : nil
      scope = ExecutionCatalog.scope(@kind, state: @state)
      @executions = paginate(scope.order(created_at: :desc, id: :desc))
    end

    def show
      @events = case @execution
      when Scan then @execution.scan_events.order(created_at: :desc, id: :desc).limit(100)
      when VisibilityStudy then @execution.visibility_events.order(created_at: :desc, id: :desc).limit(100)
      else []
      end
    end

    def control
      action = params[:operation].to_s
      unless %w[pause resume cancel restart retry retry_publication expire].include?(action)
        return head :unprocessable_entity
      end
      if %w[resume restart retry retry_publication].include?(action) && !PlatformSetting.new_work_enabled?
        raise OperationsError, "Las nuevas ejecuciones están pausadas. Actívalas en Configuración antes de continuar."
      end
      target = ExecutionControl.new(@execution).call(action, budget_usd: params[:budget_usd])
      audit!("execution.#{action}", "#{@execution.class.name}:#{@execution.id}", { "target_id" => target.id })
      redirect_to admin_activity_entry_path(kind: ExecutionCatalog.kind(target), id: target.id), notice: "Acción solicitada. El ejecutor la aplicará al terminar la operación en curso."
    rescue OperationsError, Visibility::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      redirect_to admin_activity_entry_path(kind: @kind, id: @execution.id), alert: error.is_a?(ActiveRecord::RecordNotUnique) ? "Ya hay una ejecución activa para este recurso." : error.message
    end

    private

    def set_execution
      @kind = params[:kind]
      raise ActiveRecord::RecordNotFound unless ExecutionCatalog::MODELS.key?(@kind)
      @execution = ExecutionCatalog.scope(@kind).find(params[:id])
    end
  end
end
