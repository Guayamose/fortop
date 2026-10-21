module Visibility
  class ProviderError < Error
    attr_reader :retryable
    def initialize(message, retryable: false)
      super(message)
      @retryable = retryable
    end
  end
end
