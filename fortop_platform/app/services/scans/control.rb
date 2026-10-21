module Scans
  # Requests are acknowledged by the worker at an operation boundary. Until then
  # the scan keeps its exclusive repository slot, including while it is paused.
  class Control
    class Halted < StandardError; end

    def initialize(scan)
      @scan = scan
    end

    def request!(action)
      raise ArgumentError unless %w[pause cancel restart].include?(action)
      @scan.repository.with_lock do
        @scan.reload
        return false unless @scan.active?
        return false if @scan.paused? && action == "pause"
        return false if @scan.control_action.present? && @scan.control_action != "pause" && @scan.control_action != action
        unless @scan.control_action == action
          @scan.update!(control_action: action)
          label = { "pause" => "Pausa solicitada", "cancel" => "Cancelación solicitada", "restart" => "Reinicio solicitado" }.fetch(action)
          @scan.record_event!("#{label}. Terminando la operación en curso.", kind: "control")
        end
        true
      end
    end

    def resume!
      @scan.repository.with_lock do
        @scan.reload
        return false unless @scan.paused? && @scan.control_action.nil?
        @scan.advance!("queued", progress: @scan.progress, message: "Continuación solicitada. Se recuperará el trabajo guardado.")
        true
      end
    end

    def check!
      @scan.reload
      raise Halted unless @scan.active?
      return unless @scan.control_action.present? || @scan.paused?

      replacement = nil
      @scan.repository.with_lock do
        @scan.reload
        action = @scan.control_action
        if action == "pause"
          snapshot = block_given? ? yield : {}
          @scan.update!(status: "paused", control_action: nil, execution_state: JSON.generate(snapshot))
          @scan.record_event!("Análisis en pausa. El contexto y los cambios están guardados; no se harán nuevas solicitudes a la IA.", kind: "control")
        elsif %w[cancel restart].include?(action)
          @scan.update!(status: "cancelled", control_action: nil, execution_state: nil, publication_changes: nil, finished_at: Time.current)
          @scan.record_event!("Análisis cancelado. Las publicaciones ya realizadas en GitHub se conservan.", kind: "control")
          replacement = build_restart! if action == "restart"
        end
      end
      enqueue_restart(replacement) if replacement
      raise Halted
    end

    def restart!
      @scan.repository.with_lock do
        @scan.reload
        if (id = @scan.metadata["restart_scan_id"])
          return @scan.repository.scans.find(id)
        end
        return if @scan.repository.scans.active.exists?
        build_restart!
      end
    end

    private

    def build_restart!
      replacement = @scan.repository.scans.create!(status: "queued", metadata: { "restarted_from" => @scan.id })
      replacement.record_event!("Nuevo análisis desde cero, reiniciado a partir del análisis ##{@scan.id}.", kind: "control")
      @scan.update!(metadata: @scan.metadata.merge("restart_scan_id" => replacement.id))
      replacement
    end

    def enqueue_restart(scan)
      ScanJob.perform_later(scan.id)
    rescue StandardError
      scan.advance!("failed", progress: 0, message: "No se ha podido encolar el nuevo análisis. Puedes volver a iniciarlo.")
      scan.update!(error_message: "No se ha podido encolar el nuevo análisis.")
    end
  end
end
