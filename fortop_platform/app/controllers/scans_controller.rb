class ScansController < ApplicationController
  before_action :set_repository

  def create
    @repository.scans.active.first&.expire_if_stale!
    @scan = @repository.scans.active.first
    if @scan
      redirect_to repository_scan_path(@repository, @scan), notice: "Este repositorio ya tiene un análisis en curso."
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
    redirect_to repository_scan_path(@repository, @scan)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    if (active_scan = @repository.scans.active.first)
      redirect_to repository_scan_path(@repository, active_scan), notice: "Este repositorio ya tiene un análisis en curso."
    else
      redirect_to repository_path(@repository), alert: "No se ha podido crear el análisis. Vuelve a intentarlo."
    end
  end

  def show
    @scan = @repository.scans.find(params[:id])
    @scan.expire_if_stale!
    respond_to do |format|
      format.html
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
      redirect_to repository_scan_path(@repository, @scan), alert: "No se puede reintentar esta publicación o ya hay una ejecución en curso."
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
    redirect_to repository_scan_path(@repository, @scan)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to repository_scan_path(@repository, @scan), alert: "Ya hay una ejecución en curso para este repositorio."
  end

  private

  def set_repository
    @repository = current_user.repositories.find(params[:repository_id])
  end
end
