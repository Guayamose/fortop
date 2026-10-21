class ExpireScansJob < ApplicationJob
  queue_as :default

  def perform
    Scan.active.where(updated_at: ...30.minutes.ago).find_each(&:expire_if_stale!)
  end
end
