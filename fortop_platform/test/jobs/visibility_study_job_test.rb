require "test_helper"
require_relative "../support/visibility_fixtures"

class VisibilityStudyJobTest < ActiveJob::TestCase
  include VisibilityFixtures

  test "one step schedules a continuation and duplicate sessions cannot acquire its lease" do
    study=visibility_study
    client=FakeVisibilityClient.new
    Visibility::GoogleClient.stub(:new, client) do
      assert_enqueued_with(job: VisibilityStudyJob, args: [ study.id ]) { VisibilityStudyJob.perform_now(study.id) }
    end
    assert_equal "researching", study.reload.stage
    assert_equal 1, study.request_count
    config=ActiveRecord::Base.connection_db_config.configuration_hash
    connection=PG.connect(dbname: config[:database], host: config[:host], port: config[:port], user: config[:username], password: config[:password])
    connection.exec_params("SELECT pg_advisory_lock(804221, $1)", [ study.id ])
    assert_enqueued_with(job: VisibilityStudyJob, args: [ study.id ]) do
      assert_no_difference("VisibilityCall.count") { VisibilityStudyJob.perform_now(study.id) }
    end
  ensure
    connection&.close
  end

  test "queued pause and restart require no API key and live report follows its replacement" do
    study=visibility_study
    study.update!(control_action: "pause")
    Visibility::GoogleClient.stub(:new, ->(*) { flunk "Provider is unnecessary for a stop" }) { VisibilityStudyJob.perform_now(study.id) }
    assert study.reload.paused?
    Visibility::Studies.control!(study, "restart")
    assert_difference("VisibilityStudy.count", 1) { VisibilityStudyJob.perform_now(study.id) }
    assert study.reload.cancelled?
    replacement=study.brand.visibility_studies.find(study.settings["restart_study_id"])
    assert replacement.queued?
    assert_equal 0, replacement.request_count
    assert_equal replacement, Visibility::Studies.control!(study, "restart")
  end
end
