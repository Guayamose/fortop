require "test_helper"
require_relative "../support/github_sign_in"

class AdminExecutionControlTest < ActiveSupport::TestCase
  include GithubSignIn

  setup do
    @user = User.create!(github_id: 9123, login: "builder", github_token: "test-only")
    @repository = connected_repository(@user)
  end

  test "failed queue delivery restores a resumable scan and retryable document import" do
    scan = @repository.scans.create!(status: "paused")
    ScanJob.stub(:perform_later, false) do
      assert_raises(Admin::OperationsError) { Admin::ExecutionControl.new(scan).call("resume") }
    end
    assert scan.reload.paused?
    assert_nil scan.error_message
    assert_includes Admin::ExecutionControl.actions(scan), "resume"

    import = @user.brand_imports.create!(status: "failed", retryable: true)
    BrandImportJob.stub(:perform_later, false) do
      assert_raises(Admin::OperationsError) { Admin::ExecutionControl.new(import).call("retry") }
    end
    assert import.reload.failed?
    assert import.retryable?
  end

  test "pausing and cancelling preserve the existing cooperative operation boundaries" do
    scan = @repository.scans.create!(status: "analyzing")
    ScanJob.stub(:perform_later, true) do
      Admin::ExecutionControl.new(scan).call("pause")
      assert scan.reload.analyzing?
      assert_equal "pause", scan.control_action
      assert_empty Admin::ExecutionControl.actions(scan)
      assert_raises(Scans::Control::Halted) { Scans::Control.new(scan).check! { { "checkpoint" => "saved" } } }
      assert scan.reload.paused?
      assert_includes scan.execution_state, "saved"
      Admin::ExecutionControl.new(scan).call("cancel")
      assert_raises(Scans::Control::Halted) { Scans::Control.new(scan).check! }
      assert scan.reload.cancelled?
      assert_nil scan.execution_state
    end
  end

  test "stalled work can be marked interrupted without starting paid work and fresh activity prevents it" do
    import = @user.brand_imports.create!(status: "interpreting")
    refute_includes Admin::ExecutionControl.actions(import), "expire"
    import.update_columns(updated_at: 11.minutes.ago)
    assert_includes Admin::ExecutionControl.actions(import), "expire"
    Admin::ExecutionControl.new(import).call("expire")
    assert import.reload.failed?
    assert import.retryable?

    scan = @repository.scans.create!(status: "analyzing")
    scan.update_columns(updated_at: 31.minutes.ago)
    assert_includes Admin::ExecutionControl.actions(scan), "expire"
    scan.record_event!("El agente sigue trabajando.")
    refute_includes Admin::ExecutionControl.actions(scan), "expire"
    assert_raises(Admin::OperationsError) { Admin::ExecutionControl.new(scan).call("expire") }
    assert scan.reload.analyzing?
  end
end
