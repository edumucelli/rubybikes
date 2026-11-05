# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'time'
require 'timeout'
require 'http/cookie_jar'

class RubyBikes
  module Native
    class Transport
      Response = Struct.new(:status, :headers, :body, keyword_init: true)
      attr_reader :headers, :last_response

      def initialize(timeout: 60, headers: {}, proxy: nil, cooldowns: {}, cache: nil, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @clock = clock
        seconds = Float(timeout, exception: true)
        raise ArgumentError, 'timeout must be positive' unless seconds&.positive? && seconds.finite?

        @deadline = @clock.call + seconds
        @headers = { 'User-Agent' => "RubyBikes/#{RubyBikes::VERSION}" }.merge(headers)
        @proxy = proxy && URI(proxy)
        @cooldowns = cooldowns
        @cookies = HTTP::CookieJar.new
        @cache = cache || ResponseCache.new
        @deadline_active = false
      end

      def remaining
        seconds = @deadline - @clock.call
        raise TimeoutError, 'Provider update exceeded its deadline' unless seconds.positive?

        seconds
      end

      def within_deadline
        return yield if @deadline_active

        @deadline_active = true
        begin
          Timeout.timeout(remaining) { yield } # rubocop:disable Style/ExplicitBlockArgument -- The timer passes an argument; provider blocks take none.
        rescue Timeout::Error
          raise TimeoutError, 'Provider update exceeded its deadline'
        ensure
          @deadline_active = false
        end
      end

      def request(url, method: 'GET', params: nil, data: nil, headers: {}, raw: false, skip_cache: false, default_encoding: 'UTF-8')
        within_deadline do
          perform_request(url, method: method, params: params, data: data, headers: headers, raw: raw, skip_cache: skip_cache, default_encoding: default_encoding)
        end
      end

      private

      def perform_request(url, method:, params:, data:, headers:, raw:, skip_cache:, default_encoding:)
        remaining
        uri = transport_uri(url)
        uri.query = [uri.query, params && URI.encode_www_form(params)].compact.reject(&:empty?).join('&')
        uri.query = nil if uri.query == ''
        host = uri.host
        raise ArgumentError, 'Provider URL must include a host' unless host

        until_time = @cooldowns.fetch(host, 0.0)
        raise RateLimitedError.new('Provider rate limit reached', details: { 'host' => uri.host, 'retry_after' => until_time - Time.now.to_f }) if until_time > Time.now.to_f

        combined = @headers.merge(headers)
        cookies = @cookies.cookies(uri)
        combined['Cookie'] = cookies.map { |cookie| "#{cookie.name}=#{cookie.value}" }.join('; ') unless cookies.empty?
        cache_key = [method, uri.to_s, data, combined]
        cached = @cache.get(cache_key, @clock.call) if method == 'GET' && !skip_cache
        if cached
          @last_response = cached
          return decode(@last_response, raw, default_encoding)
        end
        response = fetch(uri, method, data, combined, 5)
        @last_response = response
        if response.status == 429
          value = response.headers.fetch('retry-after', '300')
          delay = begin
            Float(value)
          rescue ArgumentError
            begin
              Time.httpdate(value).to_f - Time.now.to_f
            rescue ArgumentError
              300
            end
          end
          delay = [[delay, 1].max, 86_400].min # rubocop:disable Style/ComparableClamp -- Preserve rejection of non-comparable Retry-After values.
          @cooldowns[host] = Time.now.to_f + delay
          raise RateLimitedError.new('Provider rate limit reached', details: { 'host' => uri.host, 'retry_after' => delay })
        end
        @cache.put(cache_key, response, @clock.call) if method == 'GET' && response.status.between?(200, 299) && !skip_cache
        decode(response, raw, default_encoding)
      end

      def decode(response, raw, default_encoding)
        body = response.body
        if raw
          body.b
        else
          body.dup.force_encoding(response.headers.fetch('content-type', '')[/charset\s*=\s*"?([^;"\s]+)/i, 1] || default_encoding).encode('UTF-8', invalid: :replace,
                                                                                                                                                    undef: :replace)
        end
      end

      def transport_uri(url)
        uri = URI(url)
        raise ArgumentError, 'Provider URL must use HTTP or HTTPS' unless uri.is_a?(URI::HTTP)

        uri
      end

      def fetch(uri, method, data, headers, redirects)
        proxy = @proxy
        http_class = if proxy
                       proxy_host = proxy.host
                       raise ArgumentError, 'Proxy URL must include a host' unless proxy_host

                       Net::HTTP::Proxy(proxy_host, proxy.port, proxy.user, proxy.password)
                     else
                       Net::HTTP
                     end
        host = uri.host
        raise ArgumentError, 'Provider URL must include a host' unless host

        http = http_class.new(host, uri.port)
        http.max_retries = 0
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = [5, remaining].min
        http.read_timeout = [20, remaining].min
        http.write_timeout = [20, remaining].min
        # Net::HTTP accepts its generic request base class at this boundary.
        # @type var request: untyped
        request = Net::HTTPGenericRequest.new(method, !data.nil?, method != 'HEAD', uri.request_uri, headers)
        if data.is_a?(Hash)
          request.set_form_data(data)
        elsif data
          request.body = data
        end
        response = http.start { |connection| connection.request(request) }
        response.get_fields('set-cookie')&.each { |cookie| @cookies.parse(cookie, uri) }
        if response.is_a?(Net::HTTPRedirection)
          raise ProviderError, 'Provider exceeded the redirect limit' if redirects.zero?

          target = transport_uri(URI.join(uri.to_s, response.fetch('location')).to_s)
          forwarded = headers.dup
          forwarded.reject! { |key, _| %w[authorization cookie].include?(key.downcase) } if [target.scheme, target.host, target.port] != [uri.scheme, uri.host, uri.port]
          cookies = @cookies.cookies(target)
          forwarded['Cookie'] = cookies.map { |cookie| "#{cookie.name}=#{cookie.value}" }.join('; ') unless cookies.empty?
          redirect_method = if (%w[302 303].include?(response.code) && method != 'HEAD') || (response.code == '301' && method == 'POST')
                              'GET'
                            else
                              method
                            end
          return fetch(target, redirect_method, redirect_method == method ? data : nil, forwarded, redirects - 1)
        end
        Response.new(status: response.code.to_i, headers: response.each_header.to_h, body: response.body || '')
      end
    end
  end
end
