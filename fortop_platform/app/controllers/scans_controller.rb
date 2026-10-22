class ScansController < ApplicationController
  before_action :set_repository
  before_action :require_new_work_enabled, only: %i[create restart resume retry_publication]

  def create
    @repository.scans.active.first&.expire_if_stale!
    @scan = @repository.scans.active.first
    if @scan
      redirect_to scan_location(@scan), notice: "Este repositorio ya tiene un análisis en curso."
      return
    end

    @scan = @repository.scans.create!(status: "queued", progress: 0)
    @scan.record_event!("Análisis solicitado. Preparando los agentes.")
    begin
      ScanJob.perform_later(@scan.id)
    rescue StandardError
      @scan.update!(status: "failed", error_message: "No se ha podido iniciar el análisis. Vuelve a intentarlo.", finished_at: Time.current)
      @scan.record_event!(@scan.error_message, kind: "warning")
      Rails.logger.error("No se ha podido encolar el análisis #{@scan.id}.")
    end
    redirect_to scan_location(@scan)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    if (active_scan = @repository.scans.active.first)
      redirect_to scan_location(active_scan), notice: "Este repositorio ya tiene un análisis en curso."
    else
      redirect_to repository_path(@repository), alert: "No se ha podido crear el análisis. Vuelve a intentarlo."
    end
  end

  def show
    @scan = @repository.scans.find(params[:id])
    @scan.expire_if_stale!
    respond_to do |format|
      format.html { redirect_to repository_path(@repository, scan_id: @scan.id) }
      format.json do
        render json: { html: render_to_string(partial: "scans/progress", formats: [ :html ], locals: { scan: @scan }), active: @scan.active? }
      end
    end
  end

  def retry_publication
    @scan = @repository.scans.find(params[:id])
    requested = false
    @repository.with_lock do
      @scan.reload
      if @scan.publication_retryable? && !@repository.scans.active.exists?
        @scan.update!(error_message: nil)
        @scan.advance!("queued", progress: 88, message: "Reintento de publicación solicitado. Se recuperarán las correcciones sin repetir la IA.")
        requested = true
      end
    end
    unless requested
      redirect_to scan_location(@scan), alert: "No se puede reintentar esta publicación o ya hay una ejecución en curso."
      return
    end

    begin
      ScanJob.perform_later(@scan.id)
    rescue StandardError
      message = "No se ha podido encolar la publicación. Puedes volver a intentarlo."
      @scan.update!(error_message: message)
      @scan.advance!("failed", progress: 88, message: message)
      Rails.logger.error("No se ha podido encolar la publicación #{@scan.id}.")
    end
    redirect_to scan_location(@scan)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to scan_location(@scan), alert: "Ya hay una ejecución en curso para este repositorio."
  end

  def pause
    request_control("pause")
  end

  def cancel
    request_control("cancel")
  end

  def resume
    @scan = @repository.scans.find(params[:id])
    if Scans::Control.new(@scan).resume!
      begin
        raise ActiveJob::EnqueueError unless ScanJob.perform_later(@scan.id)
      rescue StandardError
        @repository.with_lock do
          @scan.reload
          if @scan.queued? && @scan.control_action.nil?
            @scan.update!(status: "paused")
            @scan.record_event!("No se ha podido encolar la continuación. Vuelve a pulsar Continuar.", kind: "warning")
          end
        end
      end
      redirect_to repository_path(@repository)
    else
      redirect_to repository_path(@repository), alert: "Este análisis no está disponible para continuar."
    end
  end

  def restart
    @scan = @repository.scans.find(params[:id])
    if @scan.active?
      request_control("restart")
    elsif (replacement = Scans::Control.new(@scan).restart!)
      ScanJob.perform_later(replacement.id) if replacement.queued?
      redirect_to repository_path(@repository)
    else
      redirect_to repository_path(@repository), alert: "Ya hay un análisis en curso para este repositorio."
    end
  rescue ActiveJob::EnqueueError
    replacement&.advance!("failed", progress: 0, message: "No se ha podido iniciar el nuevo análisis. Vuelve a intentarlo.")
    redirect_to repository_path(@repository), alert: "No se ha podido iniciar el nuevo análisis."
  end

  private

  def request_control(action)
    @scan = @repository.scans.find(params[:id])
    if Scans::Control.new(@scan).request!(action)
      begin
        # Also services queued or paused scans that have no running worker.
        ScanJob.perform_later(@scan.id)
      rescue StandardError
        @scan.record_event!("No se ha podido avisar al ejecutor. Si el estado no cambia, vuelve a solicitar la acción.", kind: "warning")
      end
      redirect_to repository_path(@repository)
    else
      redirect_to repository_path(@repository), alert: "Esta acción ya no está disponible para el análisis."
    end
  end

  def scan_location(scan)
    params[:return_to] == "repository" ? repository_path(@repository) : repository_scan_path(@repository, scan)
  end

  def set_repository
    @repository = current_user.repositories.find(params[:repository_id])
  end
end
