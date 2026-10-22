require "json"
require "open3"

module FortopProductionGoogleKey
  PROJECT = "fortop-ai-gkecke".freeze
  KEY_ID = "fortop-production-gemini-v2".freeze

  def self.fetch!
    prefix = [ "gcloud", "--project=#{PROJECT}", "--quiet", "services", "api-keys" ]
    _, error, status = Open3.capture3(*prefix, "describe", KEY_ID, "--location=global", "--format=none")
    unless status.success?
      raise "Cannot inspect the production Google key" unless error.match?(/NOT_FOUND|not found|does not exist/i)
      # gcloud progress output can contain keyString even with --format=none.
      # Both streams must stay captured, including when key creation fails.
      _, _, status = Open3.capture3(*prefix, "create", "--key-id=#{KEY_ID}", "--display-name=Fortop production Gemini",
        "--service-account=fortop-gemini@#{PROJECT}.iam.gserviceaccount.com", "--api-target=service=generativelanguage.googleapis.com")
      raise "Production Google key creation failed" unless status.success?
    end
    key, _, status = Open3.capture3(*prefix, "get-key-string", KEY_ID, "--location=global", "--format=value(keyString)")
    raise "Cannot retrieve the production Google key" unless status.success? && !key.strip.empty?
    key.strip
  end
end
