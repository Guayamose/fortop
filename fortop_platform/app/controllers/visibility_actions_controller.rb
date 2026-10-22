class VisibilityActionsController < ApplicationController
  before_action :set_action
  before_action :require_new_work_enabled, only: :handoff

  def update
    @action.update!(status: params.require(:visibility_action).fetch(:status))
    redirect_to brand_path(@brand, study_id: @study.id, anchor: "actions"), notice: "Acción actualizada."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to brand_path(@brand, study_id: @study.id), alert: error.record.errors.full_messages.to_sentence
  end

  def handoff
    raise Visibility::Error, "Solo las comprobaciones técnicas pueden enviarse al repositorio." unless @action.kind == "technical"
    repository = current_user.repositories.find(params[:repository_id])
    scan = nil
    repository.with_lock do
      @action.with_lock do
        scan = @action.scan
        unless scan
          raise Visibility::Error, "Este repositorio ya tiene un análisis activo." if repository.scans.active.exists?
          scan = repository.scans.create!(metadata: { "visibility_context" => { "study_id" => @study.id, "action_id" => @action.id,
            "title" => @action.title, "description" => @action.description, "observation_ids" => @action.observation_ids,
            "evidence" => @study.visibility_observations.where(id: @action.observation_ids).limit(8).map { |observation| { "question" => observation.question["text"], "analysis" => observation.analysis, "sources" => observation.citations.map { |source| source.slice("canonical_url", "url", "title") } } } } })
          scan.record_event!("Análisis solicitado desde el estudio de visibilidad. Los agentes contrastarán la recomendación con el código.")
          @action.update!(repository: repository, scan: scan, status: "in_progress")
        end
      end
    end
    if scan.queued?
      begin
        raise ActiveJob::EnqueueError unless ScanJob.perform_later(scan.id)
      rescue StandardError
        scan.update!(status: "failed", error_message: "No se ha podido encolar el análisis. Inicia uno nuevo desde el repositorio.", finished_at: Time.current)
      end
    end
    redirect_to repository_path(scan.repository, scan_id: scan.id)
  rescue Visibility::Error => error
    redirect_to brand_path(@brand, study_id: @study.id), alert: error.message
  end

  private

  def set_action
    @brand = current_user.brands.find(params[:brand_id])
    @study = @brand.visibility_studies.find(params[:visibility_study_id])
    @action = @study.visibility_actions.find(params[:id])
  end
end
