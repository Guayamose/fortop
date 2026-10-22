class BrandsController < ApplicationController
  before_action :set_brand, only: %i[show edit update destroy]

  def index
    @brands = current_user.brands.includes(:visibility_studies).order(updated_at: :desc)
  end

  def new
    @brand = current_user.brands.new(markets: [ { "name" => "España", "language" => "es" } ])
  end

  def create
    @brand = current_user.brands.new(brand_params)
    if @brand.save
      redirect_to brand_path(@brand), notice: "Marca creada. Tu brief ya está guardado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @brand.update(brand_params)
      redirect_to brand_path(@brand), notice: "Brief actualizado. Los estudios anteriores conservan su contexto original."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def show
    @brand.visibility_studies.active.each(&:expire_if_stale!)
    @studies = @brand.visibility_studies.recent.to_a
    @active_study = @studies.find(&:active?)
    @study = if params[:study_id].present?
      @brand.visibility_studies.find(params[:study_id])
    else
      @active_study || @studies.first
    end
    if @study && request.format.json? && params[:follow_restart] == "1"
      while (next_id = @study.settings["restart_study_id"]) && next_id.to_i > @study.id
        @study = @brand.visibility_studies.find(next_id)
      end
    end
    @filters = params.permit(:market, :language, :intent, :topic, :scope, :source, :lane).to_h
    @metrics = Visibility::Metrics.new(@study, filters: @filters) if @study
    @source_domains = @study ? @study.visibility_observations.where(status: "completed").pluck(:citations).flatten.select { |source| source["cited"] && source["domain"].present? }.pluck("domain").uniq.sort : []
    @repositories = current_user.repositories.order(:full_name)
    respond_to do |format|
      format.html
      format.json { render json: { html: render_to_string(partial: "brands/workspace", formats: [ :html ]), active: @study&.work_pending? || false, study_id: @study&.id } }
    end
  end

  def destroy
    if @brand.destroy
      redirect_to brands_path, notice: "Marca eliminada."
    else
      redirect_to brand_path(@brand), alert: @brand.errors.full_messages.to_sentence
    end
  end

  private

  def set_brand
    @brand = current_user.brands.find(params[:id])
  end

  def brand_params
    attributes = params.require(:brand).permit(:name, :website, :brief, :markets_text, :aliases_text, :known_competitors, document_ids: [])
    if attributes.key?(:document_ids)
      ids = attributes[:document_ids].reject(&:blank?).map { |id| Integer(id.to_s, 10) }.uniq
      selected = current_user.brand_documents.joins(:brand_import).where(id: ids, brand_imports: { status: "completed" })
      raise ActiveRecord::RecordNotFound unless selected.count == ids.size
      attributes[:document_ids] = ids
    end
    attributes
  rescue ArgumentError, TypeError
    raise ActiveRecord::RecordNotFound
  end
end
