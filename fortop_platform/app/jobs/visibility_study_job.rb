class VisibilityStudyJob < ApplicationJob
  queue_as :default

  def perform(study_id)
    study = VisibilityStudy.find_by(id: study_id)
    return unless study&.work_pending?
    retry_wait = nil
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      key = Integer(study.id)
      acquired = connection.select_value("SELECT pg_try_advisory_lock(804221, #{key})")
      unless acquired
        retry_job wait: 2.seconds if study.reload.work_pending?
        return
      end
      begin
        Visibility::Pipeline.new(study.reload).step if study.work_pending?
      rescue Visibility::RetryLater => error
        retry_wait = error.wait
      rescue Visibility::Halted
        # A cooperative stop preserves all paid responses and stage checkpoints.
      ensure
        connection.select_value("SELECT pg_advisory_unlock(804221, #{key})")
      end
    end
    if retry_wait
      retry_job wait: retry_wait.seconds
    elsif study.reload.work_pending?
      Visibility::Studies.enqueue!(study)
    end
  end
end
