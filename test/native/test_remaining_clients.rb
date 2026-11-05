# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'rubybikes/native'
require 'rubybikes/native/remaining_clients'

class NativeRemainingClientsTest < Minitest::Test
  FIXTURES = File.expand_path('fixtures/remaining', __dir__)
  ENDPOINT = 'https://fixtures.example/stations'

  def setup
    WebMock.disable_net_connect!
  end

  def fixture(name)
    File.read(File.join(FIXTURES, name))
  end

  def provider(name, **options)
    spec = JSON.parse(File.read(File.join(RubyBikes::Native::DATA, 'providers.json'))).find { |row| row.fetch('class') == name }
    parameters = { 'tag' => 'fixture', 'meta' => { 'name' => name }, 'feed_url' => ENDPOINT }.merge(options.transform_keys(&:to_s))
    RubyBikes::Native::JsonProviders.new(spec, parameters)
  end

  def snapshot(name, **options)
    provider(name, **options).snapshot(RubyBikes::Native::Transport.new)
  end

  def test_cyclopolis_google_parses_missing_counts_capacity_and_unicode
    stub_request(:get, ENDPOINT).to_return(body: fixture('cyclopolis_google.html'))
    stations = snapshot('Cyclopolis', mapstyle: 'google').fetch('stations')

    assert_equal 2, stations.size
    first, second = stations

    assert_equal 'ETHNOSINELFSIS SQUARE', first['name']
    assert_equal [37.5639397319061, 22.8093402871746], first.values_at('latitude', 'longitude')
    assert_equal [0, 0], first.values_at('bikes', 'free')
    assert_equal({ 'slots' => 32, 'closed' => true }, first['extra'])
    assert_equal 'ΠΛΑΤΕΙΑ', second['name']
    assert_equal [3, 7], second.values_at('bikes', 'free')
    assert_equal({}, second['extra'])
    assert_requested :get, ENDPOINT, times: 1
  end

  def test_cyclopolis_mapbox_accepts_negative_coordinates_and_escaped_markup
    stub_request(:get, ENDPOINT).to_return(body: fixture('cyclopolis_mapbox.html'))
    station = snapshot('Cyclopolis', mapstyle: 'mapbox').fetch('stations').fetch(0)

    assert_equal 'Station South', station['name']
    assert_equal [-22.912345, -43.212345], station.values_at('latitude', 'longitude')
    assert_equal [2, 10], station.values_at('bikes', 'free')
    assert_equal({ 'slots' => 12 }, station['extra'])
  end

  def test_cyclopolis_api_combines_vehicle_and_dock_types
    stub_request(:get, ENDPOINT).to_return(body: fixture('cyclopolis_api.json'))
    first, closed = snapshot('CyclopolisApi').fetch('stations')

    assert_equal 'Πλατεία', first['name']
    assert_equal [37.98, 23.73, 5, 9], first.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 'station-1', 'is_renting' => true, 'is_returning' => false, 'online' => true }, first['extra'])
    assert_equal [0, 0], closed.values_at('bikes', 'free')
    refute closed['extra']['online']
    assert_empty snapshot('CyclopolisApi', bbox: [0, 0, 1, 1]).fetch('stations')
  end

  def test_cyclopolis_api_preserves_numeric_status_truthiness
    body = JSON.parse(fixture('cyclopolis_api.json'))
    body.first.merge!('is_renting' => 0, 'is_returning' => 1)
    stub_request(:get, ENDPOINT).to_return(body: JSON.generate(body))
    station = snapshot('CyclopolisApi').fetch('stations').first

    assert_equal 1, station['extra']['online']
    assert_equal 0, station['extra']['is_renting']
  end

  def test_ilevia_preserves_provider_metadata_and_terminal_flags
    url = 'https://data.lillemetropole.fr/data/ogcapi/collections/vlille/items'
    stub_request(:get, url).with(query: { 'f' => 'json', 'limit' => '-1' }).to_return(body: fixture('keolis_ilevia.json'))
    first, disconnected = snapshot('KeolisIlevia', dataset: 'vlille').fetch('stations')

    assert_equal 'République', first['name']
    assert_equal [50.63, 3.06, 4, 8], first.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal '12', first['extra']['uid']
    assert_equal 'Lille', first['extra']['city']
    assert_equal 'Place de la République', first['extra']['address']
    assert_equal '2026-11-04T12:00:00Z', first['extra']['last_update']
    assert first['extra']['online']
    assert first['extra']['payment-terminal']
    refute disconnected['extra']['online']
    refute disconnected['extra']['payment-terminal']
  end

  def test_star_uses_query_parameters_and_preserves_latitude_longitude_order
    url = 'https://data.explore.star.fr/api/records/1.0/search/'
    stub_request(:get, url).with(query: { 'dataset' => 'vls-stations', 'rows' => '-1' }).to_return(body: fixture('keolis_star.json'))
    instance = provider('KeolisSTAR', dataset: 'vls-stations', meta: { 'source' => 'https://example.org/{dataset}' })
    first, disconnected = instance.snapshot(RubyBikes::Native::Transport.new).fetch('stations')

    assert_equal [48.109, -1.679, 3, 7], first.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal '42', first['extra']['uid']
    assert_equal 10, first['extra']['slots']
    assert_equal 'En fonctionnement', first['extra']['status']
    assert first['extra']['online']
    assert first['extra']['payment-terminal']
    refute disconnected['extra']['online']
    assert_equal 'https://example.org/vls-stations', instance.meta['source']
  end

  def test_vcub_combines_electric_and_manual_bikes
    stub_request(:get, ENDPOINT).to_return(body: fixture('vcub.json'))
    first, disconnected = snapshot('VCub').fetch('stations')

    assert_equal 'Quinconces', first['name']
    assert_equal [44.846, -0.574, 5, 7], first.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => '77', 'last_update' => '2026-11-04T12:00:00Z',
                   'address' => 'Place des Quinconces', 'city' => 'Bordeaux', 'online' => true,
                   'slots' => 12, 'ebikes' => 2, 'normal_bikes' => 3, 'has_ebikes' => true }, first['extra'])
    refute disconnected['extra']['online']
    assert_equal [0, 10], disconnected.values_at('bikes', 'free')
  end

  def test_missing_provider_collections_raise_instead_of_succeeding_with_empty_data
    stub_request(:get, ENDPOINT).to_return(body: '{}')
    assert_raises(KeyError) { snapshot('VCub') }
  end
end
