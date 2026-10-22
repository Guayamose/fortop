module Admin
  class ExecutionControl
    def self.actions(record)
      recovery = stale?(record) ? %w[expire] : []
      recovery + normal_actions(record)
    end

    def self.stale?(record)
      case record
      when Scan
        record.active? && !record.paused? && [ record.updated_at, record.scan_events.maximum(:created_at) ].compact.max < 30.minutes.ago
      when VisibilityStudy
        record.work_pending? && record.updated_at < 30.minutes.ago
      when BrandImport
        record.active? && record.updated_at < 10.minutes.ago
      end
    end

    def self.normal_actions(record)
      return [] if record.respond_to?(:control_action) && record.control_action.present?
      case record
      when Scan
        return %w[resume cancel restart] if record.paused?
        return %w[pause cancel restart] if record.active?
        record.publication_retryable? ? %w[retry_publication restart] : %w[restart]
      when VisibilityStudy
        return %w[resume cancel restart] if record.paused?
        return %w[pause cancel restart] if record.active?
        record.failed? ? %w[retry restart] : %w[restart]
      when BrandImport
        record.failed? && record.retryable? && record.request_count < 3 ? %w[retry] : []
      else []
      end
    end

    def initialize(record)
      @record = record
    end

    def call(action, budget_usd: nil)
      @record.reload
      raise OperationsError, "Esta acción ya no está disponible. Actualiza la página." unless self.class.actions(@record).include?(action)
      if action == "expire"
        @record.expire_if_stale!
        raise OperationsError, "El ejecutor ha vuelto a registrar actividad. La ejecución sigue en curso." unless @record.reload.failed?
        @record.update!(control_action: nil) if @record.respond_to?(:control_action) && @record.control_action.present?
        return @record
      end
      case @record
      when Scan then control_scan(action)
      when VisibilityStudy then Visibility::Studies.control!(@record, action, budget_usd: budget_usd)
      when BrandImport then retry_import
      end
    end

    private

    def control_scan(action)
      control = Scans::Control.new(@record)
      case action
      when "resume"
        raise OperationsError, "El análisis ya no está en pausa." unless control.resume!
        enqueue_scan(@record, failure_status: "paused")
      when "restart"
        if @record.active?
          raise OperationsError, "No se puede solicitar el reinicio." unless control.request!("restart")
          enqueue_scan(@record)
        else
          replacement = control.restart!
          raise OperationsError, "Ya hay un análisis activo en este repositorio." unless replacement
          enqueue_scan(replacement, failure_status: "failed") if replacement.queued?
          return replacement
        end
      when "retry_publication"
        @record.repository.with_lock do
          @record.reload
          unless @record.publication_retryable? && !@record.repository.scans.active.exists?
            raise OperationsError, "La publicación ya no está disponible para reintentar."
          end
          @record.update!(error_message: nil)
          @record.advance!("queued", progress: 88, message: "El administrador ha solicitado recuperar la publicación sin repetir la IA.")
        end
        enqueue_scan(@record, failure_status: "failed")
      else
        raise OperationsError, "No se puede solicitar esta acción." unless control.request!(action)
        enqueue_scan(@record)
      end
      @record
    end

    def enqueue_scan(scan, failure_status: nil)
      raise ActiveJob::EnqueueError unless ScanJob.perform_later(scan.id)
    rescue StandardError
      scan.with_lock do
        if failure_status && scan.queued? && scan.control_action.nil?
          scan.update!(status: failure_status, error_message: failure_status == "failed" ? "No se ha podido avisar al ejecutor." : nil, finished_at: failure_status == "failed" ? Time.current : nil)
        end
        scan.record_event!("No se ha podido avisar al ejecutor desde administración. Vuelve a intentarlo.", kind: "warning")
      end
      raise OperationsError, "No se ha podido avisar al ejecutor. La petición de control se conserva si había una operación en curso."
    end

    def retry_import
      @record.with_lock do
        unless @record.failed? && @record.retryable? && @record.request_count < 3
          raise OperationsError, "Esta lectura no está disponible para reintentar."
        end
        @record.update!(status: "queued", error_message: nil, retryable: false)
      end
      begin
        raise ActiveJob::EnqueueError unless BrandImportJob.perform_later(@record.id)
      rescue StandardError
        @record.update!(status: "failed", error_message: "No se ha podido iniciar la lectura.", retryable: true)
        raise OperationsError, "No se ha podido iniciar la lectura. Puedes reintentarlo."
      end
      @record
    end
  end
end
