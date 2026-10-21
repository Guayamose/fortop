require "uri"
require "net/http"

module Visibility
  module Urls
    REDIRECT_HOST = "vertexaisearch.cloud.google.com".freeze
    module_function

    def public_url(value)
      uri = URI.parse(value.to_s)
      return unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && [ 80, 443 ].include?(uri.port)
      host = uri.host.downcase.delete_suffix(".")
      return unless host.match?(/\A(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}\z/) && host.length <= 253
      return if host.match?(/\.(?:local|localhost|internal|test|invalid|example)\z/)
      uri.host = host
      uri.fragment = nil
      uri.to_s
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    def domain(value)
      url = public_url(value)
      URI(url).host.delete_prefix("www.") if url
    end

    def same_domain?(url, website)
      host, target = domain(url), domain(website)
      host && target && (host == target || host.end_with?(".#{target}"))
    end

    # Only contact the fixed Google redirect service. Never fetch the destination
    # or arbitrary user-supplied URLs, including private network addresses.
    def resolve(value, transport: nil)
      url = public_url(value)
      return unless url
      uri = URI(url)
      return url unless uri.host == REDIRECT_HOST
      return unless uri.scheme == "https" && uri.path.start_with?("/grounding-api-redirect/")
      response = if transport
        transport.call(uri)
      else
        Net::HTTP.start(uri.host, 443, use_ssl: true, open_timeout: 3, read_timeout: 4) { |http| http.head(uri.request_uri) }
      end
      destination = public_url(response["location"])
      destination if destination && URI(destination).host != REDIRECT_HOST
    rescue IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError
      nil
    end

    def normalize_sources(sources, resolver: method(:resolve))
      Array(sources).filter_map do |source|
        next unless source.is_a?(Hash) && (url = public_url(source["url"]))
        canonical = resolver.call(url)
        source.slice("title", "excerpts", "cited").merge("url" => url, "canonical_url" => canonical, "domain" => domain(canonical), "resolved" => canonical.present?)
      end
    end
  end
end
