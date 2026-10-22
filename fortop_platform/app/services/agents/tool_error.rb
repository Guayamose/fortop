module Agents
  class ToolError < Error
    attr_reader :details

    def initialize(message, details: {})
      @details = details
      super(message)
    end
  end
end
