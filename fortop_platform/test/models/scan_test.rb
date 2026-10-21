require "test_helper"

class ScanTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(github_id: 123, login: "test-user", github_token: "test-token")
    @repository = @user.repositories.create!(github_id: 456, full_name: "test-user/site",
      html_url: "https://github.com/test-user/site", installation_id: 789)
  end

  test "only one active scan is allowed even when model validation is bypassed" do
    first = @repository.scans.create!
    duplicate = @repository.scans.new
    assert_not duplicate.valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      Scan.transaction(requires_new: true) { duplicate.save!(validate: false) }
    end
    first.update!(status: "completed", progress: 100)
    assert @repository.scans.create!.queued?
  end

  test "stage transitions record timestamps and persistent progress events" do
    scan = @repository.scans.create!
    scan.advance!("analyzing", progress: 15, message: "Inspecting files")
    assert scan.started_at
    assert_nil scan.finished_at
    assert_equal "Inspecting files", scan.scan_events.last.message
    scan.advance!("completed", progress: 100, message: "Finished")
    assert scan.finished_at
    assert scan.completed?
    assert_not scan.active?
  end

  test "a running repository cannot be disconnected" do
    @repository.scans.create!
    assert_not @repository.destroy
    assert Repository.exists?(@repository.id)
  end

  test "stalled work releases the active scan slot" do
    scan = @repository.scans.create!
    scan.update_columns(created_at: 31.minutes.ago, updated_at: 31.minutes.ago)
    scan.expire_if_stale!
    assert scan.failed?
    assert scan.finished_at
    assert @repository.scans.create!.queued?
  end

  test "recent agent activity prevents a false timeout" do
    scan = @repository.scans.create!
    scan.update_columns(updated_at: 31.minutes.ago)
    scan.record_event!("Still working", kind: "tool")
    scan.expire_if_stale!
    assert scan.active?
  end
end
