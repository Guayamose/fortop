class GithubTestHttp
  attr_reader :requests

  def initialize(*responses)
    @responses = responses
    @requests = []
  end

  def request(uri, **options)
    @requests << { uri: uri, **options }
    raise "Unexpected GitHub request" if @responses.empty?
    response = @responses.shift
    raise response if response.is_a?(Exception)
    response
  end
end
