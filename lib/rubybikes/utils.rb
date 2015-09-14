# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'open-uri'
require 'openssl'

require_relative 'warnings'
require_relative 'redirections'

suppress_warnings { OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE }

class Scraper
	attr_accessor :headers, :user_agent

    def initialize(headers=nil)
    	@headers = headers || { 'User-Agent' => 'RubyBikes' }
        @last_request = nil
    end
    def request(url, method = 'GET', params = nil, data = nil)
    	if method == 'GET'
			response = open(url, @headers.merge(:allow_unsafe_redirects => true))
            # puts response.charset
    	else
    		raise '#{method} not implemented yet.'
    	end
        data = response.read
        if response.meta.has_key?('set-cookie')
        	@headers['Cookie'] = response.meta['set-cookie']
		end
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