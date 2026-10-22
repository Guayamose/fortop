require "test_helper"

class VisibilityGoogleClientTest < ActiveSupport::TestCase
  test "grounded requests isolate instructions and keep supported citations usage and provider search widget" do
    request_body=nil
    response=Struct.new(:code, :body).new("200", JSON.generate({ "modelVersion"=>"gemini-version", "candidates"=>[ { "finishReason"=>"STOP", "content"=>{ "parts"=>[ { "text"=>"private thought", "thought"=>true }, { "text"=>"La marca ofrece facturación." } ] }, "groundingMetadata"=>{ "webSearchQueries"=>[ "facturación" ], "groundingChunks"=>[ { "web"=>{ "uri"=>"https://public.com/source", "title"=>"Fuente" } }, { "web"=>{ "uri"=>"https://other.com", "title"=>"No citada" } } ], "groundingSupports"=>[ { "segment"=>{ "text"=>"La marca ofrece facturación." }, "groundingChunkIndices"=>[ 0 ] } ], "searchEntryPoint"=>{ "renderedContent"=>"<div>Google Search</div>" } } } ], "usageMetadata"=>{ "promptTokenCount"=>100, "candidatesTokenCount"=>50, "thoughtsTokenCount"=>20, "totalTokenCount"=>170 } }))
    client=Visibility::GoogleClient.new(api_key: "fake-only", transport: ->(uri, request) { assert_equal "generativelanguage.googleapis.com", uri.host; assert_equal "fake-only", request["x-goog-api-key"]; request_body=JSON.parse(request.body); response })
    result=client.generate(model: "gemini-3.5-flash-lite", system: "Instructions", prompt: "Question", grounded: true, max_output_tokens: 512, temperature: 0.7)
    assert_equal [ { "googleSearch"=>{} } ], request_body["tools"]
    assert_equal [ { "text"=>"Question" } ], request_body.dig("contents", 0, "parts")
    assert_equal "La marca ofrece facturación.", result.text
    assert_equal [ true, false ], result.citations.pluck("cited")
    assert_equal 70, result.usage["output_tokens"]
    assert_equal 170, result.usage["total_tokens"]
    assert_equal 1, result.usage["search_queries"]
    assert_includes result.search_entry_point, "Google Search"
  end

  test "provider errors never expose the API key or raw upstream body" do
    response=Struct.new(:code, :body).new("429", '{"error":"fake-secret-key"}')
    client=Visibility::GoogleClient.new(api_key: "fake-secret-key", transport: ->(*) { response })
    error=assert_raises(Visibility::ProviderError) { client.generate(model: "gemini-3.5-flash-lite", system: "s", prompt: "p", grounded: false, max_output_tokens: 512, temperature: 0.2) }
    assert error.retryable
    assert_no_match(/fake-secret-key/, error.message)
  end

  test "structured calls use schema without enabling search and incomplete outputs cannot enter metrics" do
    response=Struct.new(:code, :body).new("200", JSON.generate({ "candidates"=>[ { "finishReason"=>"MAX_TOKENS", "content"=>{ "parts"=>[ { "text"=>"partial" } ] } } ] }))
    client=Visibility::GoogleClient.new(api_key: "fake", transport: ->(_, request) { body=JSON.parse(request.body); assert_nil body["tools"]; assert_equal "application/json", body.dig("generationConfig", "responseMimeType"); response })
    assert_raises(Visibility::ProviderError) { client.generate(model: "gemini-3.5-flash-lite", system: "s", prompt: "p", grounded: false, schema: { type: "object" }, max_output_tokens: 512, temperature: 0.2) }
  end
end
