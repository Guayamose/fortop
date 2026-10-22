require "test_helper"

class PlatformSettingTest < ActiveSupport::TestCase
  test "only operational keys and bounded numeric or supported model values may be saved" do
    assert PlatformSetting.new(key: "AGENT_MAX_TURNS", value: "0").valid?
    assert PlatformSetting.new(key: "VISIBILITY_DAILY_BUDGET_USD", value: "0.01").valid?
    { "GITHUB_CLIENT_SECRET" => "value", "NEW_WORK_ENABLED" => "yes", "AGENT_MAX_TURNS" => "-1",
      "AGENT_MAX_TOTAL_TOKENS" => "1.5", "VISIBILITY_DAILY_BUDGET_USD" => "NaN",
      "VISIBILITY_MAX_REQUESTS" => "0", "VISIBILITY_GEMINI_MODEL" => "unknown-model", "GEMINI_MODEL" => "https://untrusted.example/model" }.each do |key, value|
      refute PlatformSetting.new(key: key, value: value).valid?, key
    end
  end

  test "database settings override the environment and are consumed by the actual agent and visibility clients" do
    original = ENV["AGENT_MAX_TOTAL_TOKENS"]
    ENV["AGENT_MAX_TOTAL_TOKENS"] = "9000"
    assert_equal "9000", PlatformSetting.fetch("AGENT_MAX_TOTAL_TOKENS")
    PlatformSetting.create!(key: "AGENT_MAX_TOTAL_TOKENS", value: "1234")
    PlatformSetting.create!(key: "AGENT_MAX_OUTPUT_TOKENS", value: "1024")
    PlatformSetting.create!(key: "GEMINI_MODEL", value: "gemini-2.5-flash-lite")
    client = Agents::GeminiClient.new(api_key: "test-key")
    assert_equal "gemini-2.5-flash-lite", client.model
    assert_equal 1234, client.instance_variable_get(:@max_total_tokens)
    assert_equal 1024, client.instance_variable_get(:@max_output_tokens)
    PlatformSetting.create!(key: "VISIBILITY_MAX_REQUESTS", value: "75")
    PlatformSetting.create!(key: "VISIBILITY_MAX_TOKENS", value: "5000")
    settings = Visibility::Settings.build
    assert_equal 75, settings.fetch("max_requests")
    assert_equal 5000, settings.fetch("max_tokens")
  ensure
    ENV["AGENT_MAX_TOTAL_TOKENS"] = original
  end
end
