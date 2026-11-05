# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require_relative '../../lib/rubybikes/native'

class NativeExtraJsonTest < Minitest::Test
  SPECS = JSON.parse(File.read(File.expand_path('../../data/providers.json', __dir__)))
  COVERED_CLIENTS = %w[Batumvelo Bicicas CharteredBike Cykleo LastenVelo LinkBike Publibike Roovee Sejong SmartBike Tashu WeGoShare YouBikeCn YouBikeTw].freeze

  def setup
    WebMock.disable_net_connect!
  end

  def snapshot(client, parameters = {})
    specification = SPECS.find { |item| item.fetch('class') == client }
    provider = RubyBikes::Native::JsonProviders.new(specification, { 'tag' => 'fixture', 'meta' => {} }.merge(parameters))
    provider.snapshot(RubyBikes::Native::Transport.new)
  end

  def json_stub(url, payload, method: :get, query: nil, body: nil, headers: nil)
    request = stub_request(method, url)
    conditions = {}
    conditions[:query] = query if query
    conditions[:body] = body if body
    conditions[:headers] = headers if headers
    request = request.with(**conditions) unless conditions.empty?
    request.to_return(status: 200, body: JSON.generate(payload), headers: { 'Content-Type' => 'application/json' })
  end

  def test_batumvelo_updates_parking_and_roaming_bikes
    parking = json_stub('https://batumvelo.ge/api/client/public/parking', [{ 'name' => 'Batumi', 'lat' => 41.65, 'lng' => 41.64, 'type' => 'ALLOW' }],
                        headers: { 'Accept' => 'application/json' })
    roaming = json_stub('https://batumvelo.ge/api/client/public/available', [{ 'lat' => '41.651', 'lng' => '41.641' }], headers: { 'Accept' => 'application/json' })
    data = snapshot('Batumvelo')

    assert_equal [0, 0], data['stations'].first.values_at('bikes', 'free')
    assert data['stations'].first['extra']['online']
    assert_equal [41.651, 41.641, 'bike'], data['vehicles'].first.values_at('latitude', 'longitude', 'kind')
    assert_requested(parking)
    assert_requested(roaming)
  end

  def test_bicicas_counts_free_nonincident_anchors_and_electric_bikes
    payload = { 'features' => [{ 'geometry' => { 'coordinates' => [-0.05, 39.98] }, 'properties' => {
      'name' => 'Castelló', 'bikes_available' => 2,
      'anchors' => [{ 'bicycle' => nil, 'incidents' => [] }, { 'bicycle' => 'bike-1', 'incidents' => [], 'is_electric' => true }, { 'bicycle' => nil, 'incidents' => ['broken'] }],
      'last_seen' => '2026-11-01', 'number_loans' => '17', 'incidents' => [], 'online' => true
    } }] }
    stub = json_stub('https://ws2.bicicas.es/bench_status_map', payload)
    row = snapshot('Bicicas')['stations'].first

    assert_equal ['Castelló', 39.98, -0.05, 2, 1], row.values_at('name', 'latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'has_ebikes' => true, 'ebikes' => 1, 'slots' => 3, 'last_seen' => '2026-11-01', 'number_loans' => 17, 'incidents' => [], 'online' => true }, row['extra'])
    assert_requested(stub)
  end

  def test_chartered_bike_sends_app_query_and_preserves_electric_counts
    payload = { 'status' => 200, 'data' => [{ 'stationName' => 'Surat', 'latitude' => '21.19', 'longitude' => '72.83',
                                              'bikesAvailable' => nil, 'freeRacks' => '9', 'stationId' => 'station-1',
                                              'ebikesAvailable' => '2', 'stationNumber' => '17', 'active' => true }] }
    stub = json_stub('https://api.charteredbike.in/api/v1/stations/get-all-station', payload,
                     query: { 'lat' => '21.1940305', 'long' => '72.825347', 'version' => '1.9.2', 'buildNumber' => '283' }, headers: { 'User-Agent' => 'okhttp/3.12.1' })
    row = snapshot('CharteredBike')['stations'].first

    assert_equal ['Surat', 0, 9], row.values_at('name', 'bikes', 'free')
    assert_equal({ 'uid' => 'station-1', 'ebikes' => 2, 'number' => 17, 'online' => true }, row['extra'])
    assert_requested(stub)
  end

  def test_cykleo_combines_manual_and_electric_bikes
    payload = [{ 'id' => 'one', 'availableClassicBikeCount' => 3, 'availableElectricBikeCount' => 2, 'availableDockCount' => 7,
                 'station' => { 'status' => 'IN_SERVICE', 'assetStation' => { 'commercialName' => 'Dijon', 'commercialNumber' => '001',
                                                                              'coordinate' => { 'x' => 5.04, 'y' => 47.32 } } } }]
    stub = json_stub('https://portail.cykleo.fr/pu/stations/availability', payload, query: { 'organization_id' => 'fixture' },
                                                                                    headers: { 'Referer' => 'https://portail.cykleo.fr/' })
    row = snapshot('Cykleo', 'organization' => 'fixture')['stations'].first

    assert_equal ['Dijon', 47.32, 5.04, 5, 7], row.values_at('name', 'latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 'one', 'number' => '001', 'ebikes' => 2, 'normal_bikes' => 3, 'online' => true, 'status' => 'IN_SERVICE' }, row['extra'])
    assert_requested(stub)
  end

  def test_lastenvelo_csv_names_availability_and_bounding_box
    csv = "utc,human,bikeid,latitude,longitude,status,returned,name,subname,info,booking,osm\n" \
          "1,2026-11-01,bike-1,51.5,-0.1,available,0,Central,Library,Cargo,https://example.org/book,\n" \
          "1,2026-11-01,bike-2,51.51,-0.11,rented,0,Park,,Cargo,https://example.org/book,\n" \
          "1,2026-11-01,bike-3,53.0,-0.1,available,0,Outside,,Cargo,https://example.org/book,\n"
    stub = stub_request(:get, 'https://operator.example/bikes.csv').to_return(status: 200, body: csv, headers: { 'Content-Type' => 'text/csv' })
    rows = snapshot('LastenVelo', 'feed_url' => 'https://operator.example/bikes.csv', 'bbox' => [-1, 50, 1, 52])['stations']

    assert_equal(['Central - Library', 'Park'], rows.map { |row| row['name'] })
    assert_equal([1, 0], rows.map { |row| row['bikes'] })
    assert_nil rows.first['free']
    assert_equal({ 'uid' => 'bike-1', 'status' => 'available', 'rental_uris' => { 'web' => 'https://example.org/book' }, 'last_updated' => '2026-11-01', 'bike_type' => 'Cargo' },
                 rows.first['extra'])
    assert_requested(stub)
  end

  def test_linkbike_filters_stations_to_penang_polygon
    payload = [{ 'name' => 'George Town', 'lat' => '5.414', 'lng' => '100.329', 'capacity' => '12', 'availbike' => '3', 'StId' => 'one' },
               { 'name' => 'Outside', 'lat' => '3.14', 'lng' => '101.69', 'capacity' => '8', 'availbike' => '1', 'StId' => 'two' }]
    stub = json_stub('https://www.linkbike.my/linkbike_api/api_update_stationinfo.php', payload)
    rows = snapshot('LinkBike')['stations']

    assert_equal 1, rows.size
    assert_equal ['George Town', 3, 9], rows.first.values_at('name', 'bikes', 'free')
    assert_equal({ 'uid' => 'one', 'slots' => 12 }, rows.first['extra'])
    assert_requested(stub)
  end

  def publibike_payload
    { 'publibike' => { 'stations' => [{ 'name' => 'Zürich', 'latitude' => 47.3769, 'longitude' => 8.5417, 'id' => 1,
                                        'address' => 'Bahnhofstrasse', 'zip' => '8001', 'city' => 'Zürich', 'capacity' => 12,
                                        'vehicles' => [{ 'type' => { 'id' => 1 } }, { 'type' => { 'id' => 2 } }] }] },
      'velospot' => { 'responseData' => [{ 'station_name' => 'Genève', 'lat' => 46.2044, 'lng' => 6.1432, 'totalBike' => '5',
                                           'station_id' => 'two', 'station_address' => 'Gare', 'totalElectricalBike' => '2', 'totalNonElectricalBike' => '3' }] } }
  end

  def test_publibike_combines_both_operator_formats
    stub = json_stub('https://rest.publibike.ch/v1/public/all/stations', publibike_payload)
    rows = snapshot('Publibike')['stations']

    assert_equal(%w[Zürich Genève], rows.map { |row| row['name'] })
    assert_equal [2, 10], rows.first.values_at('bikes', 'free')
    assert_equal 1, rows.first['extra']['ebikes']
    assert_equal [5, 0], rows.last.values_at('bikes', 'free')
    assert_equal({ 'uid' => 'two', 'address' => 'Gare', 'ebikes' => 2, 'normal_bikes' => 3 }, rows.last['extra'])
    assert_requested(stub)
  end

  def test_publibike_canton_polygons_apply_to_both_operator_formats
    stub = json_stub('https://rest.publibike.ch/v1/public/all/stations', publibike_payload)
    rows = snapshot('Publibike', 'canton' => 'Zürich')['stations']

    assert_equal(['Zürich'], rows.map { |row| row['name'] })
    assert_requested(stub)
  end

  def test_roovee_filters_return_zones_and_classifies_roaming_bikes
    payload = { 'zones' => [{ 'name' => 'Rynek', 'type' => 'preferredBikeReturnZone', 'areaCenter' => { 'lat' => 52.4, 'lng' => 16.9 } },
                            { 'name' => 'No parking', 'type' => 'prohibited', 'areaCenter' => { 'lat' => 52.4, 'lng' => 16.9 } }],
                'bikes' => [{ 'location' => { 'lat' => 52.41, 'lng' => 16.91 }, 'bikeNumber' => 'electric-1', 'isAvailable' => true, 'type' => 'Elektryczny' },
                            { 'location' => { 'lat' => 52.42, 'lng' => 16.92 }, 'bikeNumber' => 'manual-1', 'isAvailable' => false, 'type' => 'Standard' }] }
    stub = json_stub('https://api.roovee.eu/public/bikesAndZones', payload, query: { 'tenant' => 'fixture' })
    data = snapshot('Roovee', 'tenant' => 'fixture')

    assert_equal(['Rynek'], data['stations'].map { |row| row['name'] })
    assert_equal({ 'virtual' => true }, data['stations'].first['extra'])
    assert_equal 0, data['stations'].first['bikes']
    assert_nil data['stations'].first['free']
    assert_equal(%w[ebike bike], data['vehicles'].map { |row| row['kind'] })
    assert_equal({ 'uid' => 'electric-1', 'online' => true }, data['vehicles'].first['extra'])
    refute data['vehicles'].last['extra']['online']
    assert_requested(stub)
  end

  def test_sejong_preserves_unknown_dock_counts
    stub = json_stub('https://operator.example/sejong',
                     { 'data' => { 'sbike_station' => [{ 'station_name' => '세종', 'y_pos' => '36.5', 'x_pos' => '127.3', 'bike_parking' => '3', 'station_id' => 'one',
                                                         'addr' => 'Address' }] } })
    row = snapshot('Sejong', 'feed_url' => 'https://operator.example/sejong')['stations'].first

    assert_equal ['세종', 36.5, 127.3, 3], row.values_at('name', 'latitude', 'longitude', 'bikes')
    assert_nil row['free']
    assert_equal({ 'uid' => 'one', 'address' => 'Address' }, row['extra'])
    assert_requested(stub)
  end

  def test_smartbike_matches_statuses_by_station_identifier
    information = [{ 'id' => '1', 'name' => 'One', 'location' => { 'lat' => 51.5, 'lon' => -0.1 }, 'address' => 'Address One' },
                   { 'id' => '2', 'name' => 'Two', 'location' => { 'lat' => 51.6, 'lon' => -0.2 }, 'address' => 'Address Two' }]
    statuses = [{ 'id' => '2', 'status' => 'CLOSED', 'availability' => { 'bikes' => '1', 'slots' => '11' } },
                { 'id' => '1', 'status' => 'OPEN', 'availability' => { 'bikes' => '3', 'slots' => '9' } }]
    info = json_stub('https://operator.example/station_list.json', information)
    status = json_stub('https://operator.example/station_status_list.json', statuses)
    rows = snapshot('SmartBike', 'endpoint' => 'https://operator.example')['stations']

    assert_equal [3, 9], rows.first.values_at('bikes', 'free')
    assert_equal({ 'uid' => 1, 'status' => 'OPEN', 'address' => 'Address One' }, rows.first['extra'])
    assert_equal [1, 11], rows.last.values_at('bikes', 'free')
    assert_requested(info)
    assert_requested(status)
  end

  def test_tashu_reads_embedded_station_json_with_operator_coordinate_order
    payload = [{ 'name' => '대전', 'x_pos' => '36.35', 'y_pos' => '127.38', 'parking_count' => '3', 'id' => 'one', 'address' => 'Address' }]
    stub = stub_request(:get, 'https://operator.example/tashu').to_return(status: 200, body: "<script>var station_json = JSON.parse('#{JSON.generate(payload)}');</script>")
    row = snapshot('Tashu', 'endpoint' => 'https://operator.example/tashu')['stations'].first

    assert_equal ['대전', 36.35, 127.38, 3], row.values_at('name', 'latitude', 'longitude', 'bikes')
    assert_nil row['free']
    assert_equal({ 'uid' => 'one', 'address' => 'Address' }, row['extra'])
    assert_requested(stub)
  end

  def test_wegoshare_posts_public_filter_excludes_planned_and_respects_bounds
    station = { 'name' => 'Praça', 'areaCentroid' => { 'latitude' => 38.7, 'longitude' => -9.1 }, 'totalLockedCycleCount' => '3', 'freeDocksCount' => '9',
                'id' => 'one', 'description' => 'Description', 'address' => 'Address', 'stationStatus' => 'OPEN', 'lastUpdateCycleCountAt' => '2026-11-01', 'photoId' => 'photo-1' }
    payload = { 'results' => [station, station.merge('name' => 'Planned', 'stationStatus' => 'PLANNED'),
                              station.merge('name' => 'Outside', 'areaCentroid' => { 'latitude' => 40.0, 'longitude' => -8.0 })] }
    stub = json_stub('https://operator.example/cxf/am/station/map/search', payload, method: :post, body: { 'isPublic' => true, 'limit' => -1 }.to_json,
                                                                                    headers: { 'Content-Type' => 'application/json; charset=utf-8' })
    rows = snapshot('WeGoShare', 'endpoint' => 'https://operator.example', 'bbox' => [-10, 38, -9, 39])['stations']

    assert_equal(['Praça'], rows.map { |row| row['name'] })
    assert_equal [3, 9], rows.first.values_at('bikes', 'free')
    assert_equal({ 'uid' => 'one', 'description' => 'Description', 'address' => 'Address', 'online' => true,
                   'last_update' => '2026-11-01', 'photo' => 'https://operator.example/cxf/fm/files/photo-1' }, rows.first['extra'])
    assert_requested(stub)
  end

  def youbike_station
    { 'lat' => '25.03', 'lng' => '121.56', 'name_tw' => '臺北', 'name_cn' => '泉州', 'name_en' => 'Station', 'available_spaces' => '3', 'empty_spaces' => '9',
      'station_no' => 'one', 'district_tw' => '信義', 'district_cn' => '中心', 'district_en' => 'Centre', 'address_tw' => '地址', 'address_cn' => '地址', 'address_en' => 'Address',
      'parking_spaces' => 12, 'updated_at' => '2026-11-01', 'status' => 1, 'type' => 2, 'area_code' => '00', 'available_spaces_detail' => { 'yb1' => 1, 'yb2' => 1, 'eyb' => 1 } }
  end

  def test_youbike_tw_filters_area_and_invalid_coordinates_and_preserves_translations
    item = youbike_station
    stub = json_stub('https://apis.youbike.com.tw/json/station-yb2.json', [item, item.merge('area_code' => '01'), item.merge('lat' => '')])
    rows = snapshot('YouBikeTw', 'uid' => '00')['stations']

    assert_equal(['臺北'], rows.map { |row| row['name'] })
    assert_equal [25.03, 121.56, 3, 9], rows.first.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal 2, rows.first['extra']['normal_bikes']
    assert_equal 1, rows.first['extra']['ebikes']
    assert_equal({ 'name' => 'Station', 'district' => 'Centre', 'address' => 'Address' }, rows.first['extra']['en'])
    assert rows.first['extra']['online']
    assert_requested(stub)
  end

  def test_youbike_cn_uses_chinese_fields_and_filters_invalid_coordinates
    item = youbike_station
    stub = json_stub('https://operator.example/youbike', { 'retVal' => [item, item.merge('lng' => '')] })
    rows = snapshot('YouBikeCn', 'feed_url' => 'https://operator.example/youbike')['stations']

    assert_equal(['泉州'], rows.map { |row| row['name'] })
    assert_equal [3, 9], rows.first.values_at('bikes', 'free')
    assert_equal '中心', rows.first['extra']['district']
    assert_equal 12, rows.first['extra']['slots']
    assert_equal '2026-11-01', rows.first['extra']['last_updated']
    refute rows.first['extra'].key?('normal_bikes')
    assert_requested(stub)
  end
end
