# Run inside the production WORKER with bin/rails runner, or pass this file
# through stdin to the deployed image. No provider generations or GitHub writes.
require "stringio"

raise "Production only" unless Rails.env.production?
expected = %w[fortop_production fortop_production_queue fortop_production_cache fortop_production_cable]
actual = [ ApplicationRecord, SolidQueue::Record, SolidCache::Record, SolidCable::Record ].map do |model|
  model.connection.select_value("SELECT current_database()")
end
raise "Unexpected production databases" unless actual == expected
raise "Database user is privileged" if ApplicationRecord.connection.select_value("SELECT rolsuper FROM pg_roles WHERE rolname = current_user")

blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("Fortop storage probe"), filename: "fortop-health.txt", content_type: "text/plain", identify: false)
begin
  raise "Document storage round trip failed" unless blob.download == "Fortop storage probe"
ensure
  blob.purge
end

valid = Scans::NodeSandbox.new.check("throw new Error('Syntax check must never execute this');")
invalid = Scans::NodeSandbox.new.check("const = ;")
raise "JavaScript sandbox failed: #{valid['details']}" unless valid["passed"] && !invalid["passed"]

probe = ScanJob.perform_later(-1) # A missing scan returns before calling any provider.
raise "Queue delivery failed" unless probe
finished = false
20.times do
  if SolidQueue::Job.uncached { SolidQueue::Job.find_by(active_job_id: probe.job_id) }&.finished_at
    finished = true
    break
  end
  sleep 1
end
raise "Worker did not complete the harmless probe" unless finished
puts({ databases: actual, application_role_superuser: false, document_round_trip: true, isolated_javascript: true, worker_probe: true, github_configured: Github::App.configured? }.to_json)
