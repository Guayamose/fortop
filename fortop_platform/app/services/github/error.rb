module Github
  class Error < StandardError
    attr_reader :status

    def initialize(message = "No se ha podido completar la operación con GitHub.", status: nil, retryable: false)
      @status = status
      @retryable = retryable
      super(message)
    end

    def retryable?
      @retryable
    end
  end
end
