# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/mock'
require 'stringio'
require 'tmpdir'
load File.expand_path('../../bin/audit-providers', __dir__)

class NativeDeadlinesTest < Minitest::Test
  include NativeFixtures

  PAYLOAD = [{ 'label' => 'Recovered', 'coordinates' => [2.35, 48.85], 'availableBikes' => 3,
               'availableSlots' => 9, 'id' => 's1', 'isClosed' => false }].freeze

  def test_real_transport_deadline_raises_only_the_public_timeout_type
    url = 'https://fixtures.example/slow-transport'
    stub_request(:get, url).to_return do
      sleep 0.1
      response(PAYLOAD)
    end
    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(RubyBikes::TimeoutError) do
      RubyBikes::Native::Transport.new(timeout: 0.02).request(url)
    end
    assert_equal 'Provider update exceeded its deadline', error.message
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - began, :<, 1
    stub_request(:get, url).to_return(response(PAYLOAD))

    assert_equal PAYLOAD, JSON.parse(RubyBikes::Native::Transport.new.request(url))
  end

  def test_deadline_context_is_reset_after_a_non_timeout_failure
    transport = RubyBikes::Native::Transport.new(timeout: 0.02)
    assert_raises(ArgumentError) { transport.within_deadline { raise ArgumentError, 'fixture failure' } }
    url = 'https://fixtures.example/context-reset'
    stub_request(:get, url).to_return do
      sleep 0.1
      response(PAYLOAD)
    end
    assert_raises(RubyBikes::TimeoutError) { transport.request(url) }
  end

  def test_two_engines_recover_after_repeated_real_deadlines
    workers = Array.new(2) do |worker_index|
      Thread.new do
        factory = RubyBikes.new(timeout: 0.02)
        begin
          8.times do |iteration|
            url = "https://fixtures.example/worker-#{worker_index}-attempt-#{iteration}"
            stub_request(:get, url).to_return do
              sleep 0.1
              response(PAYLOAD)
            end
            system = factory.build(provider: 'FifteenAPI', tag: "worker-#{worker_index}-#{iteration}", meta: { name: 'Fixture' }, feed_url: url)
            assert_raises(RubyBikes::TimeoutError) { system.update }
            assert_empty system.stations
            stub_request(:get, url).to_return(response(PAYLOAD))

            assert_same system, system.update(timeout: 1)
            assert_equal [3, 9], [system.stations.first.bikes, system.stations.first.free]
          end
        ensure
          factory.close
        end
      end
    end
    workers.each(&:value)
  end

  def test_gbfs_ignore_errors_never_swallows_an_overall_deadline
    network = provider('Gbfs', feed_url: 'https://fixtures.example/gbfs.json',
                               station_information: 'https://fixtures.example/information.json',
                               station_status: 'https://fixtures.example/status.json', ignore_errors: true)
    information = { 'station_id' => 's1', 'name' => 'Station', 'lat' => 48.85, 'lon' => 2.35 }
    status = { 'station_id' => 's1', 'is_installed' => true, 'is_renting' => true,
               'is_returning' => true, 'num_bikes_available' => 3, 'num_docks_available' => 9 }
    stub_request(:get, 'https://fixtures.example/information.json').to_return(response({ 'data' => { 'stations' => [information] } }))
    stub_request(:get, 'https://fixtures.example/status.json').to_return(response({ 'data' => { 'stations' => [status] } }))
    delayed_station = lambda do |*|
      sleep 0.1
    end

    network.stub(:station, delayed_station) do
      transport = RubyBikes::Native::Transport.new(timeout: 0.02)
      assert_raises(RubyBikes::TimeoutError) do
        transport.within_deadline { network.snapshot(transport) }
      end
    end
    assert_equal 1, snapshot(network)['stations'].length
  end
end

class NativeProviderAuditTest < Minitest::Test
  FakeSystem = Struct.new(:stations, :vehicles) do
    def update = self
  end

  class FakeFactory
    def initialize(entries, &updater)
      @entries, @updater = entries, updater
    end

    def catalog = @entries
    def get(tag) = @updater.call(tag)
  end

  def test_audit_persists_rows_and_typed_failures_as_it_progresses
    Dir.mktmpdir('rubybikes-audit-') do |directory|
      output = File.join(directory, 'status.json')
      entries = Array.new(30) { |index| { 'tag' => format('network-%02d', index), 'class' => 'Fixture', 'authed' => index == 2 } }
      observed_reports = []
      observations_lock = Mutex.new
      factory = FakeFactory.new(entries) do |tag|
        report = JSON.parse(File.read(output))
        observations_lock.synchronize { observed_reports << report }
        case tag
        when 'network-00' then raise RubyBikes::TimeoutError, 'Timed out'
        when 'network-01'
          raise RubyBikes::RateLimitedError.new('Rate limited', details: { 'host' => 'fixtures.example', 'retry_after' => 120 })
        when 'network-03' then raise RubyBikes::ProviderError, 'Fixture failure'
        when 'network-04' then FakeSystem.new([], [])
        else FakeSystem.new([Object.new], [])
        end
      end
      opener = ->(**_options, &block) { block.call(factory) }
      progress = StringIO.new
      report = RubyBikes.stub(:open, opener) { RubyBikesProviderAudit.run({ timeout: 1, output: output }, progress: progress) }

      assert report['complete']
      assert_equal 30, report['total']
      assert_equal report, JSON.parse(File.read(output))
      assert(observed_reports.any? { |row| row['networks'].length.positive? && row['complete'] == false })
      assert(observed_reports.all? { |row| row['engine'] == 'ruby' && row['networks'].map { |item| item['tag'] }.uniq.size == row['networks'].size })
      rows = report['networks'].to_h { |row| [row['tag'], row] }

      assert_equal 'timeout', rows['network-00']['status']
      assert_equal 'rate_limited', rows['network-01']['status']
      assert_equal ['fixtures.example', 120], rows['network-01'].values_at('host', 'retry_after')
      assert_equal 'requires_credentials', rows['network-02']['status']
      assert_equal 'error', rows['network-03']['status']
      assert_equal 'empty', rows['network-04']['status']
      assert_equal 'working', rows['network-05']['status']
      assert_includes progress.string, 'Audited 25/30'
      assert_includes progress.string, 'Audited 30/30'
      assert_empty Dir["#{output}.*.tmp"]
    end
  end

  def test_audit_does_not_hide_unexpected_catalog_errors
    opener = ->(**_options, &_block) { raise 'Fixture programming failure' }
    error = assert_raises(RuntimeError) do
      RubyBikes.stub(:open, opener) do
        RubyBikesProviderAudit.run({ timeout: 1, output: 'unused.json' }, progress: StringIO.new)
      end
    end
    assert_equal 'Fixture programming failure', error.message
  end
end
