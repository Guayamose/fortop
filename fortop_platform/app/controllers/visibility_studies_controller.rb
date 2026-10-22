class VisibilityStudiesController < ApplicationController
  before_action :set_brand
  before_action :require_new_work_enabled, only: %i[create restart resume retry]

  def create
    study = Visibility::Studies.create!(@brand, **params.permit(:question_count, :repetitions, :budget_usd, :reuse_id).to_h.symbolize_keys)
    Visibility::Studies.enqueue!(study) if study.work_pending?
    redirect_to brand_path(@brand, study_id: study.id)
  rescue Visibility::Error, ActiveRecord::RecordInvalid => error
    redirect_to brand_path(@brand), alert: error.message
  rescue ActiveRecord::RecordNotUnique
    redirect_to brand_path(@brand), notice: "Esta marca ya tiene un estudio en curso."
  end

  %w[pause resume cancel retry restart].each do |action|
    define_method(action) do
      study = @brand.visibility_studies.find(params[:id])
      target = Visibility::Studies.control!(study, action, budget_usd: params[:budget_usd])
      redirect_to brand_path(@brand, study_id: target.id)
    rescue Visibility::Error, ActiveRecord::RecordInvalid => error
      redirect_to brand_path(@brand, study_id: study&.id), alert: error.message
    rescue ActiveRecord::RecordNotUnique
      redirect_to brand_path(@brand), alert: "Ya hay un estudio activo para esta marca."
    end
  end

  private

  def set_brand
    @brand = current_user.brands.find(params[:brand_id])
  end
end
