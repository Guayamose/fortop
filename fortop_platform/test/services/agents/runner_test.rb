require "test_helper"

class Agents::RunnerTest < ActiveSupport::TestCase
  class Provider
    attr_reader :history
    def initialize(responses)
      @responses = responses
    end
    def generate(**args)
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

  private

  def call(path)
    { "role" => "model", "parts" => [ { "functionCall" => { "name" => "read_file", "args" => { "path" => path } } } ] }
  end

  def final(text)
    { "role" => "model", "parts" => [ { "text" => text } ] }
  end
end
