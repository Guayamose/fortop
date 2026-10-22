# Read-only provider checks; this never generates model output or paid searches.
# Run with bin/rails runner infra/gcp/verify_credentials.rb.
require "json"
require "net/http"
require "open3"
require "uri"

payload, _, status = Open3.capture3("gcloud", "secrets", "versions", "access", "latest", "--secret=fortop-production-runtime", "--project=fortop-ai-gkecke")
raise "Cannot read production credentials" unless status.success?
runtime = JSON.parse(payload)
app = Github::Http.new.request(URI("https://api.github.com/app"), token: Github::App.new(env: runtime).jwt)
raise "Unexpected GitHub App" unless app["slug"] == "fortop-app"
puts "GitHub App credentials verified: #{app.fetch('slug')}"

api_key = runtime["GOOGLE_AI_STUDIO_API_KEY"].presence
raise "Google key missing" unless api_key
token, _, status = Open3.capture3("gcloud", "auth", "print-access-token", "--project=fortop-ai-gkecke")
raise "Cannot verify Google key ownership" unless status.success?
lookup = URI("https://apikeys.googleapis.com/v2/keys:lookupKey")
lookup.query = URI.encode_www_form(keyString: api_key)
request = Net::HTTP::Get.new(lookup)
request["Authorization"] = "Bearer #{token.strip}"
response = Net::HTTP.start(lookup.host, lookup.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.request(request) }
raise "Google key lookup failed (HTTP #{response.code}); key was not printed" unless response.code == "200"
parent = JSON.parse(response.body).fetch("parent")
raise "Google key project mismatch: #{parent}" unless [ "projects/575118050486/locations/global", "projects/fortop-ai-gkecke/locations/global" ].include?(parent)
puts "Google key belongs to fortop-ai-gkecke"

uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite")
request = Net::HTTP::Get.new(uri)
request["x-goog-api-key"] = api_key
response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.request(request) }
raise "Gemini model metadata unavailable (HTTP #{response.code})" unless response.code == "200"
puts "Gemini model metadata verified; no generation requests made"
