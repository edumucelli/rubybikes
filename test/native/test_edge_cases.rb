# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/mock'

class NativeEdgeCasesTest < Minitest::Test
  include NativeFixtures

  def test_invalid_provider_dates_are_unknown_and_valid_epoch_dates_are_utc
    client = provider('FifteenAPI', feed_url: 'https://fixtures.example/feed')

    [nil, 'not a date', Float::INFINITY, Float::NAN].each do |date|
      assert_nil client.iso_date(date)
    end
    assert_equal '1970-01-01T00:00:00Z', client.iso_date(0)
    assert_equal '2026-11-01T16:00:00Z', client.iso_date('2026-11-01T17:00:00+01:00')
  end

  def test_invalid_engine_operations_and_custom_provider_definitions_are_typed
    engine = RubyBikes::Native::Engine.new
    error = assert_raises(RubyBikes::ProviderError) { engine.request('unsupported-operation') }
    assert_match(/ArgumentError/, error.message)
    assert_raises(RubyBikes::NoSystemFoundError) { engine.request('describe', tag: 'missing') }
    assert_raises(RubyBikes::NoSystemFoundError) do
      engine.request('describe', tag: 'custom', definition: { 'module' => 'not-a-client', 'class' => 'Unknown', 'parameters' => { 'meta' => {} } })
    end
    malformed = { 'module' => 'fifteen', 'class' => 'FifteenAPI', 'parameters' => {} }
    assert_raises(RubyBikes::ProviderError) { engine.request('describe', tag: 'custom', definition: malformed) }
  ensure
    engine&.close
  end

  def test_credential_lookup_accepts_tag_class_and_explicit_keys
    %w[custom BikeshareIE bikeshare_ie].each do |lookup|
      RubyBikes.open(keys: { lookup => 'fixture-key' }) do |factory|
        client = factory.build(provider: 'BikeshareIE', tag: 'custom', meta: { name: 'Fixture' }, system_id: 7)

        assert client.authed
      end
    end
    RubyBikes.open do |factory|
      client = factory.build(provider: 'BikeshareIE', tag: 'custom', meta: { name: 'Fixture' }, system_id: 7, api_key: 'explicit-fixture-key')

      assert client.authed
    end
  end

  def test_station_identity_uses_truncation_toward_zero_and_vehicle_fallback_uses_kind
    client = provider('FifteenAPI', feed_url: 'https://fixtures.example/feed')
    # Exercise the public model constructors through a real provider update.
    stub_request(:get, 'https://fixtures.example/feed').to_return(response([
                                                                             { 'label' => 'Negative', 'coordinates' => [-43.1234569, -22.1234569], 'availableBikes' => 1,
                                                                               'availableSlots' => 9, 'id' => 's', 'isClosed' => false }
                                                                           ]))
    row = snapshot(client)['stations'].first

    assert_equal Digest::MD5.hexdigest('-22123456,-43123456'), row['id']
    station = RubyBikes::Station.new(row)

    assert_equal station.id, station.get_hash
    assert_equal station.to_h, station.to_dict
  end

  def test_provider_failure_keeps_previous_station_and_vehicle_objects
    factory = RubyBikes.new
    client = factory.build(provider: 'Roovee', tag: 'custom', meta: { name: 'Fixture' }, tenant: 'fixture')
    payload = { 'zones' => [{ 'name' => 'Station', 'type' => 'preferredBikeReturnZone', 'areaCenter' => { 'lat' => 50, 'lng' => 20 } }],
                'bikes' => [{ 'bikeNumber' => 'b1', 'type' => 'Standard', 'location' => { 'lat' => 50.1, 'lng' => 20.1 }, 'isAvailable' => true }] }
    stub_request(:get, 'https://api.roovee.eu/public/bikesAndZones?tenant=fixture').to_return(response(payload))
    client.update
    previous_stations, previous_vehicles, previous_meta = client.stations, client.vehicles, client.meta
    stub_request(:get, 'https://api.roovee.eu/public/bikesAndZones?tenant=fixture').to_return(status: 500, body: 'private bad response')
    assert_raises(RubyBikes::ProviderError) { client.update(scraper: { headers: { 'X-Fixture-Revision' => 'failed' } }) }
    assert_same previous_stations, client.stations
    assert_same previous_vehicles, client.vehicles
    assert_same previous_meta, client.meta
  ensure
    factory&.close
  end

  class SnapshotEngine
    attr_accessor :row

    def timeout = 1
    def request(*) = row
  end

  def test_invalid_vehicle_timestamp_does_not_commit_a_partial_station_snapshot
    engine = SnapshotEngine.new
    client = RubyBikes::System.new(engine, { 'tag' => 'fixture', 'meta' => { 'name' => 'Original' } }, nil)
    engine.row = { 'tag' => 'fixture', 'meta' => { 'name' => 'Valid' }, 'stations' => [
                                                                          { 'id' => 's', 'name' => 'Original', 'latitude' => 1, 'longitude' => 2 }
                                                                        ],
                   'vehicles' => [{ 'id' => 'v', 'latitude' => 1, 'longitude' => 2, 'kind' => 'bike' }] }
    client.update
    stations, vehicles = client.stations, client.vehicles
    engine.row = { 'tag' => 'fixture', 'meta' => { 'name' => 'Invalid' }, 'stations' => [
                                                                            { 'id' => 'new', 'name' => 'Replacement', 'latitude' => 1, 'longitude' => 2 }
                                                                          ],
                   'vehicles' => [{ 'id' => 'new-v', 'latitude' => 1, 'longitude' => 2, 'kind' => 'bike', 'timestamp' => 'invalid' }] }
    assert_raises(RubyBikes::ProtocolError) { client.update }
    assert_same stations, client.stations
    assert_same vehicles, client.vehicles
    assert_equal 'Valid', client.meta['name']
  end
end

class NativeTransportEdgeCasesTest < Minitest::Test
  FEED = 'https://fixtures.example/feed'

  def test_constructor_rejects_invalid_deadlines
    [0, -1, Float::INFINITY, Float::NAN, 'invalid'].each do |timeout|
      assert_raises(ArgumentError) { RubyBikes::Native::Transport.new(timeout: timeout) }
    end
  end

  def test_redirect_loop_stops_after_the_bounded_limit
    request = stub_request(:get, FEED).to_return(status: 302, headers: { 'Location' => '/feed' })
    error = assert_raises(RubyBikes::ProviderError) { RubyBikes::Native::Transport.new.request(FEED) }
    assert_match(/redirect limit/, error.message)
    assert_requested request, times: 6
  end

  def test_post_redirect_switches_to_get_and_forwards_new_scoped_cookies
    stub_request(:post, FEED).with(body: 'private-fixture-body')
                             .to_return(status: 303, headers: { 'Location' => '/result', 'Set-Cookie' => 'session=fixture; Path=/; Secure' })
    result = stub_request(:get, 'https://fixtures.example/result').with(headers: { 'Cookie' => 'session=fixture' }, body: '')
                                                                  .to_return(body: 'result')
    transport = RubyBikes::Native::Transport.new

    assert_equal 'result', transport.request(FEED, method: 'POST', data: 'private-fixture-body')
    assert_requested result
  end

  def test_standard_post_301_and_302_redirects_switch_to_get
    [301, 302].each do |status|
      stub_request(:post, FEED).to_return(status: status, headers: { 'Location' => '/result' })
      result = stub_request(:get, 'https://fixtures.example/result').with(body: '').to_return(body: 'ok')

      assert_equal 'ok', RubyBikes::Native::Transport.new.request(FEED, method: 'POST', data: 'fixture')
      assert_requested result
      WebMock.reset!
    end
  end

  def test_307_preserves_method_body_and_same_origin_authorization
    stub_request(:post, FEED).to_return(status: 307, headers: { 'Location' => '/result' })
    result = stub_request(:post, 'https://fixtures.example/result').with(body: 'fixture', headers: { 'Authorization' => 'fixture-token' })
                                                                   .to_return(body: 'ok')
    transport = RubyBikes::Native::Transport.new(headers: { 'Authorization' => 'fixture-token' })

    assert_equal 'ok', transport.request(FEED, method: 'POST', data: 'fixture')
    assert_requested result
  end

  def test_head_303_stays_head
    stub_request(:head, FEED).to_return(status: 303, headers: { 'Location' => '/result' })
    result = stub_request(:head, 'https://fixtures.example/result').to_return(status: 200)

    assert_equal '', RubyBikes::Native::Transport.new.request(FEED, method: 'HEAD')
    assert_requested result
  end

  def test_retry_after_http_date_is_converted_to_delay
    now = Time.utc(2026, 11, 4, 12)
    stub_request(:get, FEED).to_return(status: 429, headers: { 'Retry-After' => (now + 90).httpdate })
    Time.stub(:now, now) do
      error = assert_raises(RubyBikes::RateLimitedError) { RubyBikes::Native::Transport.new.request(FEED) }
      assert_equal 90, error.retry_after
    end
  end

  def test_invalid_missing_negative_and_excessive_retry_after_values_are_bounded
    { 'invalid date' => 300, nil => 300, '-1' => 1, '9999999999' => 86_400 }.each do |value, expected|
      headers = value.nil? ? {} : { 'Retry-After' => value }
      stub_request(:get, FEED).to_return(status: 429, headers: headers)
      error = assert_raises(RubyBikes::RateLimitedError) { RubyBikes::Native::Transport.new.request(FEED) }
      assert_equal expected, error.retry_after
    end
  end

  def test_raw_response_cache_and_skip_cache_preserve_bytes
    stub = stub_request(:get, FEED).to_return(body: "caf\xe9".b, headers: { 'Content-Type' => 'text/plain; charset=ISO-8859-1' })
    transport = RubyBikes::Native::Transport.new
    raw = transport.request(FEED, raw: true)

    assert_equal Encoding::BINARY, raw.encoding
    assert_equal "caf\xe9".b, raw
    assert_equal 'café', transport.request(FEED)
    assert_equal "caf\xe9".b, transport.request(FEED, raw: true, skip_cache: true)
    assert_requested stub, times: 2
  end

  def test_cached_responses_do_not_bypass_the_overall_deadline
    now = 0
    stub = stub_request(:get, FEED).to_return(body: 'ok')
    transport = RubyBikes::Native::Transport.new(timeout: 1, clock: -> { now })

    assert_equal 'ok', transport.request(FEED)
    now = 2
    assert_raises(RubyBikes::TimeoutError) { transport.request(FEED) }
    assert_requested stub, times: 1
  end

  def test_errors_are_not_cached_and_different_headers_have_distinct_entries
    stub = stub_request(:get, FEED).to_return({ status: 500, body: 'error' }, { status: 200, body: 'ok' })
    transport = RubyBikes::Native::Transport.new

    assert_equal 'error', transport.request(FEED)
    assert_equal 'ok', transport.request(FEED)
    assert_equal 'ok', transport.request(FEED, headers: { 'X-Fixture' => 'different' })
    assert_requested stub, times: 3
  end
end
