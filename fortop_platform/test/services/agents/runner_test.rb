require "test_helper"

class Agents::RunnerTest < ActiveSupport::TestCase
  class Provider
    attr_reader :history, :requests
    def initialize(responses)
      @responses = responses
      @requests = []
    end
    def generate(**args)
      @requests << args.deep_dup
      @history = args[:contents].deep_dup
      @responses.shift || raise("Unexpected model call")
    end
  end

  class Tools
    attr_reader :called
    def initialize
      @called = []
    end
    def declarations
      []
    end
    def call(name, arguments)
      @called << [ name, arguments ]
      raise Agents::ToolError, "Ruta no permitida." if arguments["path"] == "../secret"
      { "content" => "observed source" }
    end
  end

  test "preserves complete Gemini content and signatures between genuine tool turns" do
    model_turn = { "role" => "model", "parts" => [ { "text" => "private reasoning", "thought" => true, "thoughtSignature" => "signed-context" }, { "functionCall" => { "id" => "call-1", "name" => "read_file", "args" => { "path" => "index.html" } }, "thoughtSignature" => "function-signature" } ] }
    provider = Provider.new([ model_turn, final("Código inspeccionado.") ])
    tools = Tools.new

    result = Agents::Runner.new(provider: provider, tools: tools, system: "system").call(prompt: "audit")

    assert_equal model_turn, provider.history[1]
    response = provider.history[2].fetch("parts").first.fetch("functionResponse")
    assert_equal "call-1", response["id"]
    assert_equal "observed source", response.dig("response", "result", "content")
    assert_equal 1, result.tool_calls
    assert_equal "Código inspeccionado.", result.summary
  end

  test "returns tool rejection to the model so it can repair its approach" do
    provider = Provider.new([ call("../secret"), call("index.html"), final("Hecho.") ])
    tools = Tools.new
    result = Agents::Runner.new(provider: provider, tools: tools, system: "system").call(prompt: "audit")
    assert_equal 2, result.tool_calls
    assert_equal "Ruta no permitida.", provider.history[2].dig("parts", 0, "functionResponse", "response", "result", "error")
  end

  test "stops unbounded tool loops" do
    provider = Provider.new([ call("index.html"), call("index.html") ])
    assert_raises(Agents::BudgetExceeded) do
      Agents::Runner.new(provider: provider, tools: Tools.new, system: "system", max_turns: 1).call(prompt: "audit")
    end
  end

  test "rejects empty completion" do
    provider = Provider.new([ final("") ])
    assert_raises(Agents::Error) { Agents::Runner.new(provider: provider, tools: Tools.new, system: "system").call(prompt: "audit") }
  end

  test "finishes work exceeding the former turn and tool ceilings" do
    turn = { "role" => "model", "parts" => 3.times.map { |index| { "functionCall" => { "name" => "read_file", "args" => { "path" => "page-#{index}.html" } } } } }
    [ { max_turns: 0, max_tool_calls: 0 }, { max_turns: 40, max_tool_calls: 120 } ].each do |limits|
      provider = Provider.new(Array.new(35) { turn.deep_dup } + [ final("Auditoría completa.") ])
      tools = Tools.new
      result = Agents::Runner.new(provider: provider, tools: tools, system: "system", timeout: 0, context_max_bytes: 0, **limits).call(prompt: "large audit")
      assert_equal 36, result.steps
      assert_equal 105, result.tool_calls
      assert_equal 105, tools.called.size
    end
  end

  test "honors an explicit tool budget before executing an oversized batch" do
    turn = { "role" => "model", "parts" => [ call("one.html")["parts"].first, call("two.html")["parts"].first ] }
    tools = Tools.new
    assert_raises(Agents::BudgetExceeded) do
      Agents::Runner.new(provider: Provider.new([ turn ]), tools: tools, system: "system", max_tool_calls: 1).call(prompt: "audit")
    end
    assert_empty tools.called
  end

  test "summarizes old context while preserving recent signed tool pairs" do
    old, recent_one, recent_two = [ "old.html", "recent-one.html", "recent-two.html" ].map { |path| call(path) }
    recent_one["parts"].first["thoughtSignature"] = "signed-recent-one"
    recent_two["parts"].first["thoughtSignature"] = "signed-recent-two"
    provider = Provider.new([ old, recent_one, recent_two, final("Hallazgo 42 aceptado; continuar desde offset 200."), final("Hecho.") ])
    result = Agents::Runner.new(provider: provider, tools: Tools.new, system: "system", context_max_bytes: 1).call(prompt: "audit the monorepo")

    assert_equal 4, result.steps
    assert_equal 5, provider.requests.size
    assert_empty provider.requests[3][:declarations]
    assert_includes provider.history.first.dig("parts", 0, "text"), "Hallazgo 42 aceptado"
    assert_includes provider.history.first.dig("parts", 0, "text"), "audit the monorepo"
    assert_equal recent_one, provider.history[1]
    assert_equal recent_two, provider.history[3]
    assert provider.history[2].dig("parts", 0, "functionResponse")
    assert provider.history[4].dig("parts", 0, "functionResponse")
  end

  test "does not silently clamp or accept invalid runtime settings" do
    [ { max_turns: -1 }, { max_tool_calls: "invalid" }, { timeout: -5 } ].each do |limits|
      assert_raises(Agents::ConfigurationError) do
        Agents::Runner.new(provider: Provider.new([]), tools: Tools.new, system: "system", **limits)
      end
    end
  end

  private

  def call(path)
    { "role" => "model", "parts" => [ { "functionCall" => { "name" => "read_file", "args" => { "path" => path } } } ] }
  end

  def final(text)
    { "role" => "model", "parts" => [ { "text" => text } ] }
  end
end
