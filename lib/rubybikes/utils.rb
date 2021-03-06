# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'open-uri'
require 'net/http'
require 'openssl'

require_relative 'warnings'
require_relative 'redirections'

suppress_warnings { OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE }

class Scraper
	attr_accessor :headers, :proxy

    def initialize(headers = nil, proxy = nil)
        #{ 'User-Agent' => 'RubyBikes' }
    	@headers = headers || {'User-Agent' => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36"}
        @proxy = URI.parse(proxy) if proxy
        @last_request = nil
    end
    def request(url, method = 'GET', params = nil)
    	if method == 'GET'
			response = open(url, @headers.merge(:allow_unsafe_redirects => true, :read_timeout => 17, :proxy => @proxy))
            # puts response.charset
            data = response.read
            if response.meta.has_key?('set-cookie')
                @headers['Cookie'] = response.meta['set-cookie']
            end
        elsif method == 'POST'
            # As open-uri does not provide GET, fall-back to net/http
            uri = URI.parse(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == 'https'
            request = Net::HTTP::Post.new(uri.path)
            request.set_form_data(params)
            response = http.request(request)
            if response['set-cookie']
                @headers['Cookie'] = response['set-cookie']
            end
            data = response.body
    	else
    		raise '#{method} not implemented.'
    	end
        # FIXME: the method should be stored with last_response
        # to indicate how to read it, since they differ with
        # the HTTP method
        @last_request = response
        return data
    end
    def clear_cookie
        if @headers.has_key?('Cookie')
            @headers.delete('Cookie')
        end
    end
end

class String
  def to_bool
    return true if self =~ (/^(true|t|yes|y|1)$/i)
    return false if self.empty? || self =~ (/^(false|f|no|n|0)$/i)
    raise ArgumentError.new "invalid value: #{self}"
  end
end