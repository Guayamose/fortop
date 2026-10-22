# Run with bin/rails runner infra/gcp/production_key.rb to synchronize the
# dedicated key while preserving all database and encryption credentials.
require "json"
require "open3"
require_relative "google_key"

project = FortopProductionGoogleKey::PROJECT
key = FortopProductionGoogleKey.fetch!
prefix = [ "gcloud", "--project=#{project}", "--quiet", "secrets", "versions" ]
payload, _, status = Open3.capture3(*prefix, "access", "latest", "--secret=fortop-production-runtime")
raise "Cannot read the runtime secret" unless status.success?
runtime = JSON.parse(payload)
if runtime["GOOGLE_AI_STUDIO_API_KEY"] != key
  runtime["GOOGLE_AI_STUDIO_API_KEY"] = key
  _, _, status = Open3.capture3(*prefix, "add", "fortop-production-runtime", "--data-file=-", "--format=none", stdin_data: JSON.generate(runtime))
  raise "Cannot store production Google credentials" unless status.success?
end
puts "Production Google key synchronized; other credentials preserved."
