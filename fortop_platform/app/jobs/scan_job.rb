class ScanJob < ApplicationJob
  queue_as :default

  def perform(scan_id)
    scan = Scan.find_by(id: scan_id)
    return unless scan&.active?

    # Session-level advisory lock suppresses duplicate queue delivery without
    # holding a database transaction open across model and GitHub HTTP calls.
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      key = Integer(scan.id)
      acquired = connection.select_value("SELECT pg_try_advisory_lock(804220, #{key})")
      return unless acquired

      begin
        scan.reload
        Scans::Pipeline.new(scan).call if scan.active?
      ensure
        connection.select_value("SELECT pg_advisory_unlock(804220, #{key})")
      end
    end
  end
end
