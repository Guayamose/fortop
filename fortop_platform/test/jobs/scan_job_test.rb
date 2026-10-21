require "test_helper"

class ScanJobTest < ActiveJob::TestCase
  test "ignores deleted scans" do
    assert_nothing_raised { ScanJob.perform_now(-1) }
  end

  test "does not run a completed scan again" do
    user = User.create!(github_id: SecureRandom.random_number(1_000_000_000), login: "job-user", github_token: "fake-token")
    repo = user.repositories.create!(github_id: SecureRandom.random_number(1_000_000_000), full_name: "test/job", html_url: "https://github.com/test/job")
    scan = repo.scans.create!(status: "completed", progress: 100)
    assert_no_difference("ScanEvent.count") { ScanJob.perform_now(scan.id) }
    assert scan.reload.completed?
  end

  test "does not deliver a duplicate job when another PostgreSQL session owns its lock" do
    user = User.create!(github_id: SecureRandom.random_number(1_000_000_000), login: "lock-user", github_token: "fake-token")
    repo = user.repositories.create!(github_id: SecureRandom.random_number(1_000_000_000), full_name: "test/locked", html_url: "https://github.com/test/locked")
    scan = repo.scans.create!
    # A separate session simulates an already running worker. Session locks are
    # visible across transactions even while fixtures remain uncommitted.
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    connection = PG.connect(dbname: config[:database], host: config[:host], port: config[:port], user: config[:username], password: config[:password])
    connection.exec_params("SELECT pg_advisory_lock(804220, $1)", [ scan.id ])
    assert_enqueued_with(job: ScanJob, args: [ scan.id ]) do
      assert_no_difference("ScanEvent.count") { ScanJob.perform_now(scan.id) }
    end
    assert scan.reload.queued?
  ensure
    connection&.close
  end

  test "queued pause and paused cancellation are serviced without constructing GitHub or a model" do
    user = User.create!(github_id: 123, login: "pause-user", github_token: "fake-token")
    repo = user.repositories.create!(github_id: 456, full_name: "test/paused", html_url: "https://github.com/test/paused")
    scan = repo.scans.create!
    Github::Access.stub(:client_for, ->(*) { flunk "No GitHub client should be constructed" }) do
      Agents::Provider.stub(:build, ->(*) { flunk "No model should be built" }) do
        Scans::Control.new(scan).request!("pause")
        ScanJob.perform_now(scan.id)
        assert scan.reload.paused?
        assert_no_difference("ScanEvent.count") { ScanJob.perform_now(scan.id) }
        Scans::Control.new(scan).request!("cancel")
        ScanJob.perform_now(scan.id)
        assert scan.reload.cancelled?
      end
    end
  end
end
