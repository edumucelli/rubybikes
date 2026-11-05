# frozen_string_literal: true

# Exchange only short-lived GitHub OIDC credentials; use only the temporary Actions environment file.
require 'json'
require 'net/http'
require 'uri'

module RubyGemsCredentials
  OWNER = 255_571
  EXCHANGE_URL = URI('https://rubygems.org/api/v1/oidc/trusted_publisher/exchange_token')

  def self.exchange_payload(jwt)
    { jwt: jwt, owner: OWNER }
  end

  def self.response_value(response, field)
    value = JSON.parse(response.body).fetch(field)
    raise 'Invalid credential response' unless value.is_a?(String) && !value.empty? && !value.match?(/[\r\n]/)

    value
  rescue JSON::ParserError, KeyError, TypeError
    raise 'Invalid credential response'
  end

  def self.configure
    uri = URI(ENV.fetch('ACTIONS_ID_TOKEN_REQUEST_URL'))
    uri.query = [uri.query, URI.encode_www_form(audience: 'rubygems.org')].compact.join('&')
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{ENV.fetch('ACTIONS_ID_TOKEN_REQUEST_TOKEN')}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.request(request) }
    raise 'GitHub OIDC token request failed' unless response.is_a?(Net::HTTPSuccess)

    jwt = response_value(response, 'value')
    request = Net::HTTP::Post.new(EXCHANGE_URL)
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
    request.body = JSON.generate(exchange_payload(jwt))
    response = Net::HTTP.start(EXCHANGE_URL.host, EXCHANGE_URL.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.request(request) }
    raise 'RubyGems OIDC exchange failed; check pending publisher expiry, owner, repository, workflow, and environment' unless response.is_a?(Net::HTTPSuccess)

    key = response_value(response, 'rubygems_api_key')
    puts "::add-mask::#{key}"
    File.open(ENV.fetch('GITHUB_ENV'), 'a') { |file| file.puts("GEM_HOST_API_KEY=#{key}") }
  end
end
RubyGemsCredentials.configure if $PROGRAM_NAME == __FILE__
