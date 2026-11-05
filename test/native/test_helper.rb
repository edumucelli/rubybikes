# frozen_string_literal: true

if ENV['COVERAGE'] == '1'
  gem 'simplecov', '~> 0.22.0'
  require 'simplecov'
  SimpleCov.start do
    enable_coverage :branch
    track_files '{lib/rubybikes.rb,lib/rubybikes/version.rb,lib/rubybikes/engine.rb,lib/rubybikes/native.rb,lib/rubybikes/native/**/*.rb}'
    add_filter '/test/'
    minimum_coverage line: 95
  end
end
require 'minitest/autorun'
require 'webmock/minitest'
require 'rubybikes/native'
WebMock.disable_net_connect!

module NativeFixtures
  def provider(name, **parameters)
    spec = JSON.parse(File.read(File.join(RubyBikes::Native::DATA, 'providers.json'))).find { |row| row['class'] == name }
    raise "Unknown fixture client #{name}" unless spec

    options = { 'tag' => 'fixture', 'meta' => { 'name' => 'Fixture' } }.merge(parameters.transform_keys(&:to_s))
    klass = if spec['gbfs']
              RubyBikes::Native::Gbfs
            else
              (%w[Nextbike Bizkaibizi].include?(name) ? RubyBikes::Native::Nextbike : RubyBikes::Native::JsonProviders)
            end
    klass.new(spec, options)
  end

  def response(payload, status: 200)
    { status: status, body: payload.is_a?(String) ? payload : JSON.generate(payload), headers: { 'Content-Type' => 'application/json; charset=utf-8' } }
  end

  def snapshot(client)
    client.snapshot(RubyBikes::Native::Transport.new)
  end
end

if ENV['VERIFY_PROVIDER_COVERAGE'] == '1'
  require 'set'
  module NativeProviderCoverage
    COMPLETED = Set.new
    def snapshot(transport)
      result = super
      COMPLETED.add(spec.fetch('class')) unless result.fetch('stations').empty? && result.fetch('vehicles').empty?
      result
    end
  end
  RubyBikes::Native::Provider.prepend(NativeProviderCoverage)
  Minitest.after_run do
    expected = JSON.parse(File.read(File.join(RubyBikes::Native::DATA, 'providers.json'))).to_set { |row| row.fetch('class') }
    missing = expected - NativeProviderCoverage::COMPLETED
    raise "Clients without successful nonempty fixture updates: #{missing.to_a.sort.join(', ')}" unless missing.empty?
  end
end
