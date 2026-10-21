require "test_helper"

class Scans::ControlTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    user = User.create!(github_id: 123, login: "control-user", github_token: "fake-token")
    @repository = user.repositories.create!(github_id: 456, full_name: "control/site", html_url: "https://github.com/control/site")
    @scan = @repository.scans.create!
    @control = Scans::Control.new(@scan)
  end

  test "pause preserves an encrypted checkpoint and reserves the repository without occupying a worker" do
    assert @control.request!("pause")
    assert @scan.reload.work_pending?
    assert_raises(Scans::Control::Halted) { @control.check! { { "private" => "source and signed model context" } } }
    assert @scan.reload.paused?
    assert @scan.active?
    refute @scan.work_pending?
    assert_nil @scan.control_action
    assert_equal "source and signed model context", JSON.parse(@scan.execution_state)["private"]
    refute_includes @scan.ciphertext_for(:execution_state), "source and signed model context"
    refute @repository.scans.new.valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      Scan.transaction(requires_new: true) { @repository.scans.new.save!(validate: false) }
    end
    refute @repository.destroy
    @scan.update_columns(updated_at: 2.days.ago)
    @scan.expire_if_stale!
    assert @scan.paused?
    assert @control.resume!
    refute @control.resume!
    assert @scan.reload.queued?
    assert @scan.execution_state.present?
  end

  test "cancellation can supersede a pause request and is acknowledged before releasing the slot" do
    @control.request!("pause")
    assert @control.request!("cancel")
    refute @control.request!("pause")
    assert @scan.reload.active?
    assert_raises(Scans::Control::Halted) { @control.check! }
    assert @scan.reload.cancelled?
    assert @scan.finished_at
    assert_nil @scan.execution_state
    assert_nil @scan.control_action
    assert @repository.scans.create!.queued?
  end

  test "restart stops the previous execution and queues exactly one new scan" do
    @control.request!("restart")
    assert_no_difference("Scan.count") { @control.request!("restart") }
    assert_difference("Scan.count", 1) do
      assert_enqueued_with(job: ScanJob) do
        assert_raises(Scans::Control::Halted) { @control.check! }
      end
    end
    replacement = @repository.scans.active.sole
    assert @scan.reload.cancelled?
    assert_equal @scan.id, replacement.metadata["restarted_from"]
    assert_equal replacement.id, @scan.metadata["restart_scan_id"]
    assert_no_difference("Scan.count") { assert_equal replacement, @control.restart! }
    assert_no_enqueued_jobs { assert_raises(Scans::Control::Halted) { @control.check! } }
  end

  test "restart of a terminal scan is idempotent and respects other active scans" do
    @scan.update!(status: "completed", progress: 100)
    replacement = @control.restart!
    assert replacement.queued?
    assert_equal replacement, @control.restart!
    @scan.update!(metadata: {})
    assert_nil @control.restart!
  end
end
