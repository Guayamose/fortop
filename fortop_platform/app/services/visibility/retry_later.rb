module Visibility
  class RetryLater < Halted
    attr_reader :wait
    def initialize(wait)
      @wait = wait
      super("Reintento programado")
    end
  end
end
