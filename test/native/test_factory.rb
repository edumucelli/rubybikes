# frozen_string_literal: true

require_relative 'test_helper'

class NativeFactoryTest < Minitest::Test
  def setup
    @factory = RubyBikes.new
  end

  def teardown
    @factory.close
    super
  end

  def test_complete_native_catalog
    assert_equal 815, @factory.tags.size
    assert_equal 85, @factory.providers.size
    assert_equal 53, @factory.catalog.map { |row| row['meta']['country'] }.uniq.size
    assert_equal 'ruby', @factory.engine_info.fetch('implementation')
    assert_equal 'b8681d2344d2ccc61d7b99b089a8cdba167a169e', @factory.engine_info.fetch('revision')
    keys = { 'bicimad' => { clientid: 'fixture', passkey: 'fixture' }, 'deutschebahn' => { client_id: 'fixture', client_secret: 'fixture' },
             'weelo' => { client_id: 'fixture', client_secret: 'fixture' } }
    @factory.catalog.each do |row|
      network = @factory.get(tag: row['tag'], api_key: keys.fetch(row['module'], 'fixture-token-1234567890'))

      assert_equal row['tag'], network.tag
      assert_equal row['class'], network.client_class
      assert_equal row['module'], network.provider
      assert_equal row['authed'], network.authed
      assert_equal row['sync'], network.sync
      assert_equal row['unifeed'], network.unifeed
    end
  end

  def test_compatible_factory_interfaces
    assert_equal @factory.get('velib').meta, @factory.get('tag' => 'velib').meta
    assert_equal 'Paris', @factory.get(tag: 'velib').meta['city']
    assert_equal 1, @factory.get(label: 'bixi').size
    assert_raises(NoGetCriteriaError) { @factory.get }
    assert_raises(NoSystemFoundError) { @factory.get('missing') }
    assert_raises(APIKeyNotAvailableError) { @factory.get('bicimad') }
    assert_equal 'velib', @factory.get('velib').tag
  end

  def test_custom_clients_and_ambiguous_modules
    network = @factory.build(provider: 'NextbikeGbfs', tag: 'custom', meta: { name: 'Custom' }, domain: 'bs')

    assert_equal 'NextbikeGbfs', network.client_class
    assert_match(/nextbike_bs/, network.meta['gbfs_href'])
    assert_raises(ArgumentError) { @factory.build(provider: 'keolis', tag: 'custom', meta: {}) }
    assert_raises(NoSystemFoundError) { @factory.build(provider: 'missing', tag: 'custom', meta: {}) }
    assert_equal 'VCub', @factory.build(provider: 'keolis', class_name: 'VCub', tag: 'custom', meta: { name: 'Custom' }, feed_url: 'https://fixture.test/feed').client_class
  end

  def test_station_and_vehicle_serialization
    row = { 'id' => 'fixture', 'name' => 'École', 'latitude' => -22.1, 'longitude' => -43.2, 'bikes' => nil, 'free' => 0, 'timestamp' => '2026-11-01T17:00:00+01:00',
            'extra' => { 'uid' => 'one' } }
    station = RubyBikes::Station.new(row)

    assert_nil station.bikes
    assert_equal '2026-11-01T16:00:00Z', station.timestamp.iso8601
    assert_equal [-43.2, -22.1], station.to_geojson['geometry']['coordinates']
    assert_equal 'École', JSON.parse(station.to_json)['name']
    vehicle = RubyBikes::Vehicle.new(row.merge('kind' => 'ebike'))

    assert_equal 'ebike', vehicle.kind
    assert_equal 'fixture', vehicle.get_hash
    assert_equal 'vehicle', vehicle.to_geojson['properties']['type']
    assert_equal vehicle.to_h, vehicle.to_dict
    assert_equal 'ebike', JSON.parse(vehicle.to_json)['kind']
  end

  def test_invalid_timeouts_and_typed_errors
    [0, -1, Float::INFINITY, Float::NAN].each do |timeout|
      assert_raises(ArgumentError) { RubyBikes.new(timeout: timeout) }
    end
    error = RubyBikes::RateLimitedError.new('Limited', details: { 'host' => 'fixture.test', 'retry_after' => 12 })

    assert_equal 12, error.retry_after
    assert_equal 'fixture.test', error.host
  end

  def test_native_system_update_serializes_and_retains_snapshot_on_failure
    factory = RubyBikes.new
    system = factory.build(provider: 'FifteenAPI', tag: 'custom', meta: { name: 'Fixture' }, feed_url: 'https://fixture.test/feed')
    stub_request(:get, 'https://fixture.test/feed').to_return(body: JSON.generate([
                                                                                    { 'label' => 'Station', 'coordinates' => [2.35, 48.85], 'availableBikes' => 3,
                                                                                      'availableSlots' => 9, 'id' => '1', 'isClosed' => false }
                                                                                  ]))

    assert_same system, system.update
    assert_equal 3, system.stations.first.bikes
    assert_equal system.to_h, system.to_dict
    assert_equal 'custom', JSON.parse(system.to_json)['tag']
    assert_equal 'FeatureCollection', system.to_geojson['type']
    previous = system.stations
    stub_request(:get, 'https://fixture.test/feed').to_return(body: 'private invalid JSON')
    error = assert_raises(RubyBikes::ProviderError) { system.update }
    refute_includes error.message, 'private'
    assert_same previous, system.stations
  ensure
    factory&.close
  end

  def test_block_form_closes_after_failure_and_unblocked_form_returns_factory
    factory = RubyBikes.open

    assert_instance_of RubyBikes, factory
    assert_raises(RuntimeError) do
      RubyBikes.open { |_instance| raise 'fixture' }
    end
  ensure
    factory&.close
  end

  class FixtureEngine
    attr_accessor :result

    def timeout = 1
    def request(*) = result
  end

  def test_invalid_snapshot_keeps_previous_objects_and_metadata
    engine = FixtureEngine.new
    system = RubyBikes::System.new(engine, { 'tag' => 'fixture', 'meta' => {} }, nil)
    engine.result = { 'tag' => 'fixture', 'meta' => { 'name' => 'Good' }, 'stations' => [
      { 'id' => 'one', 'name' => 'Good', 'latitude' => 1, 'longitude' => 2, 'timestamp' => '2026-11-01T00:00:00Z' }
    ] }
    system.update
    previous = system.stations
    engine.result = { 'tag' => 'fixture', 'meta' => {}, 'stations' => [{}] }
    assert_raises(RubyBikes::ProtocolError) { system.update }
    assert_same previous, system.stations
    assert_equal 'Good', system.meta['name']
    engine.result = { 'tag' => 'other', 'meta' => {}, 'stations' => [] }
    assert_raises(RubyBikes::ProtocolError) { system.update }
  end

  def test_metadata_returned_to_callers_does_not_mutate_provider_or_catalog_defaults
    original = @factory.get('velib')
    expected = original.meta.fetch('company').dup
    original.meta.fetch('company') << 'caller-mutation'

    assert_equal expected, @factory.get('velib').meta.fetch('company')
    original.meta['name'] = 'changed'

    refute_equal 'changed', @factory.get('velib').meta.fetch('name')
  end

  def test_empty_credentials_are_rejected_before_contacting_operators
    ['', {}].each do |key|
      assert_raises(RubyBikes::APIKeyNotAvailableError) { @factory.get(tag: 'bicimad', api_key: key) }
    end
  end

  def test_scraper_header_symbol_keys_are_normalized_at_the_factory_boundary
    client = @factory.build(provider: 'FifteenAPI', tag: 'headers', meta: { name: 'Fixture' }, feed_url: 'https://fixture.test/headers')
    stub = stub_request(:get, 'https://fixture.test/headers').with(headers: { 'X-Fixture' => 'client' }).to_return(body: '[]')
    client.update(scraper: { headers: { 'X-Fixture': 'client' } })

    assert_requested stub
  end
end
