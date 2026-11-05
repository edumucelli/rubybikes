# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require_relative '../../lib/rubybikes/native'
require_relative '../../lib/rubybikes/native/html_clients'

class NativeHtmlClientsTest < Minitest::Test
  FIXTURES = File.expand_path('fixtures/html', __dir__)
  SPECS = JSON.parse(File.read(File.expand_path('../../data/providers.json', __dir__)))
  COVERED_CLIENTS = %w[BiciElx BiciFerrolTerra Bikeu Emovity GyorBike Meiob Mobhis Movus Samba VelobikeKZ].freeze

  def setup
    WebMock.disable_net_connect!
  end

  def snapshot(client, fixture, parameters = {})
    specification = SPECS.find { |item| item.fetch('class') == client }
    url = case client
          when 'BiciElx' then 'https://gestion.bicielx.es/mapa_prestamo.php'
          when 'GyorBike' then 'https://www.gyorbike.hu/en/stations'
          else 'https://operator.example/stations'
          end
    stub = stub_request(:get, url).to_return(status: 200, body: File.read(File.join(FIXTURES, fixture)), headers: { 'Content-Type' => 'text/html; charset=UTF-8' })
    arguments = { 'tag' => 'fixture', 'meta' => {}, 'url' => url, 'endpoint' => url, 'feed_url' => url }.merge(parameters)
    provider = RubyBikes::Native::JsonProviders.new(specification, arguments)
    result = provider.snapshot(RubyBikes::Native::Transport.new)

    assert_requested(stub)
    assert_equal 'fixture', result.fetch('tag')
    assert_empty result.fetch('vehicles')
    result.fetch('stations')
  end

  def test_bicielx_station_name_coordinates_counts_and_identity
    stations = snapshot('BiciElx', 'bicielx.html')

    assert_equal 1, stations.size
    row = stations.first

    assert_equal "Plaça d'Espanya", row['name']
    assert_equal [38.26694, -0.69833, 3, 7], row.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 42 }, row['extra'])
  end

  def test_biciferrolterra_deduplicates_coordinates_and_preserves_signed_counts
    rows = snapshot('BiciFerrolTerra', 'biciferrolterra.html')

    assert_equal 2, rows.size
    assert_equal 'Praza de España', rows.first['name']
    assert_equal [43.4892, -8.2195, 4, 8], rows.first.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'slots' => 12, 'schedule' => '08:00-22:00' }, rows.first['extra'])
    assert_equal [-1, 0], rows.last.values_at('bikes', 'free')
  end

  def test_bikeu_parses_embedded_json
    row = snapshot('Bikeu', 'bikeu.html').first

    assert_equal 'Dworzec Główny', row['name']
    assert_equal [53.1235, 18.0084, 3, 9], row.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 'station-7' }, row['extra'])
  end

  def test_emovity_accepts_decimal_points_and_commas
    rows = snapshot('Emovity', 'emovity.html')

    assert_equal 2, rows.size
    assert_equal '17 - Plaça Major', rows.first['name']
    assert_equal [41.651, 0.611, 3, 7], rows.first.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => '17' }, rows.first['extra'])
    assert_equal [41.652, 0.612, 2, 8], rows.last.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_requested(:get, 'https://operator.example/stations', headers: { 'User-Agent' => RubyBikes::Native::JsonProviders::EMOVITY_USER_AGENT })
  end

  def test_gyorbike_combines_markers_and_table_and_handles_offline_rows
    rows = snapshot('GyorBike', 'gyorbike.html')

    assert_equal 2, rows.size
    assert_equal 'Városháza', rows.first['name']
    assert_equal [5, 7], rows.first.values_at('bikes', 'free')
    assert_equal({ 'uid' => 1, 'slots' => 12, 'normal_bikes' => 3, 'ebikes' => 2, 'online' => true }, rows.first['extra'])
    assert_equal 'Egyetem', rows.last['name']
    assert_equal [0, 0], rows.last.values_at('bikes', 'free')
    refute rows.last['extra']['online']
  end

  def test_meiob_supports_names_with_and_without_station_numbers
    rows = snapshot('Meiob', 'meiob.html')

    assert_equal(['Main Square', 'Park'], rows.map { |row| row['name'] })
    assert_equal [51.5, -0.12, 3, 9], rows.first.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'address' => 'High Street', 'city' => 'London' }, rows.first['extra'])
  end

  def test_mobhis_preserves_kids_counts_and_unnamed_offline_stations
    rows = snapshot('Mobhis', 'mobhis.html')

    assert_equal 2, rows.size
    assert_equal 'Praça Central', rows.first['name']
    assert_equal [3, 9], rows.first.values_at('bikes', 'free')
    assert_equal({ 'online' => true, 'kid_bikes' => 2, 'kid_slots' => 4 }, rows.first['extra'])
    assert_nil rows.last['name']
    assert_equal [0, 0], rows.last.values_at('bikes', 'free')
    assert_equal({ 'online' => false }, rows.last['extra'])
  end

  def test_movus_filters_invalid_stations_and_handles_missing_availability
    rows = snapshot('Movus', 'movus.html', 'ebikes' => false)

    assert_equal(%w[Central Awaiting], rows.map { |row| row['name'] })
    assert_equal [3, 0], rows.first.values_at('bikes', 'free')
    assert_equal({ 'slots' => 12 }, rows.first['extra'])
    assert_equal 0, rows.last['bikes']
    assert_nil rows.last['free']
  end

  def test_movus_combines_electric_and_manual_bikes
    row = snapshot('Movus', 'movus_electric.html', 'ebikes' => true).first

    assert_equal [5, 7], row.values_at('bikes', 'free')
    assert_equal({ 'ebikes' => 2 }, row['extra'])
  end

  def test_movus_current_station_map_uses_its_published_json_endpoint
    specification = SPECS.find { |item| item.fetch('class') == 'Movus' }
    page = 'https://www.mibisivalencia.es/mapa/mapa.php'
    page_stub = stub_request(:get, page).to_return(status: 200, body: File.read(File.join(FIXTURES, 'movus_current.html')))
    script_stub = stub_request(:get, 'https://www.mibisivalencia.es/mapa/assets/js/map.js').to_return(status: 200, body: File.read(File.join(FIXTURES, 'movus_current.js')))
    data_stub = stub_request(:get, 'https://www.mibisivalencia.es/mapa/puntos.php').to_return(status: 200, body: File.read(File.join(FIXTURES, 'movus_current.json')),
                                                                                              headers: { 'Content-Type' => 'application/json' })
    provider = RubyBikes::Native::JsonProviders.new(specification, { 'tag' => 'mibisivalencia', 'meta' => {}, 'feed_url' => page, 'ebikes' => false })
    rows = provider.snapshot(RubyBikes::Native::Transport.new).fetch('stations')

    assert_equal 2, rows.size
    assert_equal 0, rows.last['bikes']
    assert_nil rows.last['free']
    assert_equal '223 Aldaia - Plaza Constitució', rows.first['name']
    assert_equal [39.4650416, -0.46131, 0, 12], rows.first.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'slots' => 12 }, rows.first['extra'])
    [page_stub, script_stub, data_stub].each { |stub| assert_requested(stub) }
  end

  def test_samba_reads_data_literals_without_executing_code
    rows = snapshot('Samba', 'samba.html')

    assert_equal 4, rows.size
    assert_equal "1 - Praça d'Água", rows.first['name']
    assert_equal [-8.057, -34.882, 3, 9], rows.first.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'address' => 'Rua Central', 'description' => 'Near the park', 'status' => 'open' }, rows.first['extra'])
    assert_equal(['open', 'maintenance/implementation', 'maintenance/implementation', 'closed'], rows.map { |row| row['extra']['status'] })
    assert_requested(:get, 'https://operator.example/stations', headers: { 'User-Agent' => RubyBikes::Native::JsonProviders::SAMBA_USER_AGENT })
  end

  def test_literal_reader_accepts_data_and_rejects_expressions
    parser = RubyBikes::Native::DataLiteral

    assert_equal [nil, true, false, -3, 1.5, 'Á', 'x'], parser.parse('[None, True, False, -3, +1.5, "\\u00c1", \'\\x78\',]')
    assert_equal ['#{dangerous_call}', [1, 2]], parser.parse('[\'#{dangerous_call}\', (1,2)]') # rubocop:disable Lint/InterpolationCheck -- Deliberately test uninterpreted source text.
    ['[Kernel.system("touch /tmp/no")]', '[1 + 2]', '[name]', '[1]; unsafe()', '["unterminated]', '["\\xQ0"]'].each do |source|
      assert_raises(RubyBikes::ProviderError) { parser.parse(source) }
    end
    assert_raises(RubyBikes::ProviderError) { parser.parse("#{'[' * 66}0#{']' * 66}") }
    assert_raises(RubyBikes::ProviderError) { parser.parse(' ' * ((2 * 1024 * 1024) + 1)) }
  end

  def test_velobike_kz_normalizes_non_numeric_counts_and_online_status
    rows = snapshot('VelobikeKZ', 'velobike_kz.html')

    assert_equal 2, rows.size
    assert_equal 'Мәңгілік Ел', rows.first['name']
    assert_equal [51.128, 71.431, 3, 9], rows.first.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'online' => true, 'slots' => 12, 'address' => 'City Hall', 'uid' => '001' }, rows.first['extra'])
    assert_equal [0, 0], rows.last.values_at('bikes', 'free')
    refute rows.last['extra']['online']
    assert_equal 0, rows.last['extra']['slots']
  end

  def test_malformed_embedded_json_is_rejected
    specification = SPECS.find { |item| item.fetch('class') == 'Bikeu' }
    provider = RubyBikes::Native::JsonProviders.new(specification, { 'tag' => 'fixture', 'meta' => {}, 'url' => 'https://operator.example/malformed' })
    stub_request(:get, 'https://operator.example/malformed').to_return(status: 200, body: '<html>Missing map</html>')
    assert_raises(RubyBikes::ProviderError) { provider.snapshot(RubyBikes::Native::Transport.new) }
  end
end
