require "test_helper"

class Agents::GeminiClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  test "retries transient provider errors and tracks real usage" do
    responses = [ Response.new("429", "quota"), Response.new("503", "unavailable"), response ]
    sleeps, requests = [], []
    client = Agents::GeminiClient.new(api_key: "test-key", transport: ->(_uri, req) { requests << req; responses.shift }, sleeper: ->(delay) { sleeps << delay })

    result = client.generate(system: "audit", contents: [], declarations: [])

    assert_equal "OK", result.dig("parts", 0, "text")
    assert_equal [ 2, 4 ], sleeps
    assert_equal 3, requests.size
    assert_equal 15, client.usage["total_tokens"]
    assert_equal 10, client.usage["input_tokens"]
    assert_equal 5, client.usage["output_tokens"]
    assert_equal "test-key", requests.first["x-goog-api-key"]
    assert_not_includes requests.first.uri.to_s, "test-key"
  end

  test "does not expose provider bodies containing secrets" do
    client = Agents::GeminiClient.new(api_key: "test-key", transport: ->(*) { Response.new("403", '{"message":"test-key SUPERSECRET"}') })
    error = assert_raises(Agents::Error) { client.generate(system: "audit", contents: [], declarations: []) }
    assert_not_includes error.message, "SUPERSECRET"
    assert_not_includes error.message, "test-key"
    assert_equal 1, client.usage["requests"]
  end

  test "refuses requests that would exceed configured total token budget" do
    client = Agents::GeminiClient.new(api_key: "test-key", transport: ->(*) { flunk "Should not make a paid request" })
    assert_raises(Agents::BudgetExceeded) { client.generate(system: "x" * 2_000_000, contents: [], declarations: []) }
  end

  test "counts hidden thinking and shares the cumulative budget across agent runs" do
    requests = 0
    paid_result = Response.new("200", JSON.generate({ candidates: [ { content: { role: "model", parts: [ { text: "Auditoría estática terminada." } ] } } ], usageMetadata: { promptTokenCount: 59_000, candidatesTokenCount: 100, thoughtsTokenCount: 900, totalTokenCount: 60_000 } }))
    client = Agents::GeminiClient.new(api_key: "test-key", transport: ->(*) { requests += 1; paid_result }, max_total_tokens: 120_000)
    tools = Object.new
    tools.define_singleton_method(:declarations) { [] }
    2.times { Agents::Runner.new(provider: client, tools: tools, system: "system").call(prompt: "audit") }
    assert_equal 2, requests
    assert_equal 120_000, client.usage["total_tokens"]
    assert_equal 2_000, client.usage["output_tokens"]

    assert_raises(Agents::BudgetExceeded) { Agents::Runner.new(provider: client, tools: tools, system: "system").call(prompt: "audit again") }
    assert_equal 2, requests, "Budget must stop before a third paid request"
  end

  test "resuming the same scan preserves its earlier token ceiling" do
    client = Agents::GeminiClient.new(api_key: "test-key", transport: ->(*) { flunk "No budget remains for another request" }, max_total_tokens: 60_000)
    client.account_for_previous_usage("total_tokens" => 59_500)
    assert_raises(Agents::BudgetExceeded) { client.generate(system: "audit", contents: [], declarations: []) }
    assert_equal 0, client.usage["requests"]
  end

  private

  def response
    Response.new("200", JSON.generate({ candidates: [ { content: { role: "model", parts: [ { text: "OK", thoughtSignature: "sig" } ] } } ], usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 4, thoughtsTokenCount: 1, totalTokenCount: 15 } }))
  end
end
