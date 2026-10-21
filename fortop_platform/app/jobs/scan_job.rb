class ScanJob < ApplicationJob
  queue_as :default

  def perform(scan_id)
    scan = Scan.find_by(id: scan_id)
    return unless scan&.work_pending?

    # Session-level advisory lock suppresses duplicate queue delivery without
    # holding a database transaction open across model and GitHub HTTP calls.
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      key = Integer(scan.id)
      acquired = connection.select_value("SELECT pg_try_advisory_lock(804220, #{key})")
      unless acquired
        # A resume can arrive just before the paused worker releases its lock.
        # Retain the delivery instead of silently losing that continuation.
        retry_job wait: 1.second if scan.reload.work_pending?
        return
      end

      begin
        scan.reload
        Scans::Pipeline.new(scan).call if scan.work_pending?
      ensure
        connection.select_value("SELECT pg_advisory_unlock(804220, #{key})")
      end
    end
  end
end
