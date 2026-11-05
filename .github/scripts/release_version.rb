# frozen_string_literal: true

require 'json'
require 'net/http'
require_relative '../../lib/rubybikes/version'

module RubyBikesRelease
  def self.outputs(version = RubyBikes::VERSION)
    raise 'Invalid release version' unless version.match?(/\A\d+\.\d+\.\d+(?:[.-][0-9A-Za-z]+)*\z/)

    uri = URI("https://rubygems.org/api/v2/rubygems/rubybikes/versions/#{version}.json")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.get(uri.request_uri) }
    case response
    when Net::HTTPOK
      data = JSON.parse(response.body)
      raise 'Unexpected RubyGems version response' unless data.is_a?(Hash) && data['name'] == 'rubybikes' && data['version'] == version

      publish = false
    when Net::HTTPNotFound
      publish = true
    else
      raise "RubyGems version check failed (HTTP #{response.code})"
    end
    { 'version' => version, 'tag' => "v#{version}", 'publish' => publish.to_s }
  end

  def self.configure
    values = outputs
    File.open(ENV.fetch('GITHUB_OUTPUT'), 'a') do |file|
      values.each { |key, value| file.puts("#{key}=#{value}") }
    end
    puts "RubyBikes #{values.fetch('version')}: #{values.fetch('publish') == 'true' ? 'ready to publish' : 'already published; skipping'}"
  end
end

RubyBikesRelease.configure if $PROGRAM_NAME == __FILE__
