# Run with: bin/rails runner infra/gcp/prepare_secrets.rb
require "base64"
require "json"
require "open3"
require "securerandom"
require_relative "google_key"

config = JSON.parse(File.read(File.join(__dir__, "config.json")))
project, secret = config.values_at("project", "secret")
raise "Unexpected project" unless project == "fortop-ai-gkecke"
command = [ "gcloud", "--project=#{project}", "--quiet", "secrets", "versions" ]
versions, error, status = Open3.capture3(*command, "list", secret, "--filter=state:ENABLED", "--format=value(name)")
raise "Cannot inspect production secret: #{error}" unless status.success?
if versions.present?
  puts "Production secrets already exist; encryption and database keys were preserved."
else
  local = Github::Configuration.environment
  missing = Github::Configuration::KEYS.reject { |key| key == "GITHUB_WEBHOOK_SECRET" || local[key].present? }
  api_key = FortopProductionGoogleKey.fetch!
  raise "Missing local GitHub configuration: #{missing.join(', ')}" if missing.any?
  raise "Missing Rails master key" unless Rails.root.join("config/master.key").file?
  password = SecureRandom.hex(32)
  values = {
    "RAILS_MASTER_KEY" => Rails.root.join("config/master.key").read.strip,
    "SECRET_KEY_BASE" => SecureRandom.hex(64),
    "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => SecureRandom.hex(32),
    "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => SecureRandom.hex(32),
    "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => SecureRandom.hex(32),
    "FORTOP_DATABASE_PASSWORD" => password,
    "POSTGRES_ADMIN_PASSWORD" => SecureRandom.hex(32),
    "GOOGLE_AI_STUDIO_API_KEY" => api_key
  }.merge(local.slice(*Github::Configuration::KEYS))
  if values.fetch("GITHUB_APP_PRIVATE_KEY").include?("-----BEGIN")
    values["GITHUB_APP_PRIVATE_KEY"] = Base64.strict_encode64(values.fetch("GITHUB_APP_PRIVATE_KEY").gsub('\\n', "\n"))
  end
  %w[DATABASE_URL QUEUE_DATABASE_URL CACHE_DATABASE_URL CABLE_DATABASE_URL].zip(%w[fortop_production fortop_production_queue fortop_production_cache fortop_production_cable]).each do |key, database|
    values[key] = "postgresql://fortop:#{password}@fortop-db:5432/#{database}"
  end
  values["GITHUB_WEBHOOK_SECRET"] ||= ""
  _, error, status = Open3.capture3(*command, "add", secret, "--data-file=-", "--format=none", stdin_data: JSON.generate(values))
  raise "Cannot save production secret: #{error}" unless status.success?
  puts "Production secrets stored in Secret Manager. No credentials were written to the repository."
end
