module Github
  class Error < StandardError
    attr_reader :status

    def initialize(message = "No se ha podido completar la operación con GitHub.", status: nil)
      @status = status
      super(message)
    end
  end
end
