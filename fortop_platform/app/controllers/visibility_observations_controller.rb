class VisibilityObservationsController < ApplicationController
  def show
    @brand = current_user.brands.find(params[:brand_id])
    @study = @brand.visibility_studies.find(params[:visibility_study_id])
    @observation = @study.visibility_observations.find(params[:id])
    @call = @study.visibility_calls.where(task_key: "answer:#{@observation.question_key}:#{@observation.repetition}", status: "succeeded").order(attempt: :desc).first
    render layout: !turbo_frame_request?
  end
end
