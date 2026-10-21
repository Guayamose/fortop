module Agents
  class Provider
    def self.build
      GeminiClient.new
    end
  end
end
