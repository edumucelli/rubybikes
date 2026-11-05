# frozen_string_literal: true

require_relative 'test_helper'

class NativeAuthGraphqlTest < Minitest::Test
  include NativeFixtures

  def client(name, key: nil, **parameters)
    spec = JSON.parse(File.read(File.join(RubyBikes::Native::DATA, 'providers.json'))).find { |row| row['class'] == name }
    options = { 'tag' => 'fixture', 'meta' => { 'name' => 'Fixture' } }.merge(parameters.transform_keys(&:to_s))
    RubyBikes::Native::JsonProviders.new(spec, options, key: key)
  end

  def test_bicimad_refreshes_after_unauthorized_response
    station = { 'id' => 42, 'name' => 'Madrid', 'number' => '042', 'geometry' => { 'coordinates' => [-3.7, 40.4] },
                'dock_bikes' => '3', 'free_bases' => '9', 'address' => 'Plaza', 'activate' => 1, 'no_available' => 0,
                'total_bases' => '12', 'light' => 2 }
    feed = 'https://openapi.emtmadrid.es/v2/transport/bicimad/stations/'
    auth = 'https://openapi.emtmadrid.es/v2/mobilitylabs/user/login/'
    stub_request(:get, feed).with { |req| !req.headers.key?('Accesstoken') }.to_return(status: 401, body: 'unauthorized')
    stub_request(:get, auth).with(headers: { 'passkey' => 'fixture-pass', 'x-clientid' => 'fixture-client' })
                            .to_return(response({ 'data' => [{ 'accessToken' => 'fixture-token' }] }))
    stub_request(:get, feed).with(headers: { 'accesstoken' => 'fixture-token' }).to_return(response({ 'data' => [station] }))
    row = snapshot(client('Bicimad', key: { 'passkey' => 'fixture-pass', 'clientid' => 'fixture-client' }))['stations'].first

    assert_equal ['Madrid', 40.4, -3.7, 3, 9], row.values_at('name', 'latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'number' => '042', 'uid' => 42, 'address' => 'Plaza', 'online' => true, 'slots' => 12, 'light' => 'yellow' }, row['extra'])
    assert_requested :get, feed, times: 2
    assert_requested :get, auth, times: 1
  end

  def test_bikeshare_ie_submits_scheme_and_basic_authorization
    feed = 'https://apps.bikeshare.ie/rbs/resources/appapi/station/data/list'
    data = { 'name' => 'Cork', 'latitude' => '51.9', 'longitude' => '-8.47', 'bikesAvailable' => '2', 'docksAvailable' => '10',
             'stationId' => 1, 'docksCount' => '12', 'nameIrish' => 'Corcaigh' }
    stub_request(:post, feed).with(body: { 'schemeId' => '7' }, headers: { 'Authorization' => 'Basic fixture-token' })
                             .to_return(response({ 'data' => [data] }))
    row = snapshot(client('BikeshareIE', key: 'fixture-token', system_id: 7))['stations'].first

    assert_equal ['Cork', 51.9, -8.47, 2, 10], row.values_at('name', 'latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 1, 'slots' => 12, 'name_ie' => 'Corcaigh' }, row['extra'])
  end

  def test_weelo_refreshes_token_and_aggregates_multiple_cities
    feed = 'https://api.weelo.it/resources/stations'
    station = { 'idStation' => 'w1', 'name' => 'Torino', 'latitude' => 45.07, 'longitude' => 7.69,
                'countMuscularBikesAvailable' => 3, 'countAssistedBikesAvailable' => 2, 'countFreePlacesAvailable' => 7,
                'address' => 'Piazza', 'state' => 'OPEN', 'totalPlaces' => 12 }
    stub_request(:get, feed).with(query: { 'idCity' => '1', 'serviceType' => '1' }) { |req| !req.headers.key?('Authorization') }
                            .to_return(status: 401, body: 'unauthorized')
    stub_request(:post, 'https://api.weelo.it/connect/token')
      .with(body: { 'client_id' => 'fixture-client', 'client_secret' => 'fixture-secret', 'grant_type' => 'client_credentials' })
      .to_return(response({ 'access_token' => 'fixture-token' }))
    [1, 2].each do |city|
      stub_request(:get, feed).with(query: { 'idCity' => city.to_s, 'serviceType' => '1' }, headers: { 'Authorization' => 'Bearer fixture-token' })
                              .to_return(response([station.merge('idStation' => "w#{city}")]))
    end
    rows = snapshot(client('Weelo', key: { 'client_id' => 'fixture-client', 'client_secret' => 'fixture-secret' }, city_ids: [1, 2]))['stations']

    assert_equal 2, rows.size
    assert_equal(%w[w1 w2], rows.map { |row| row['extra']['uid'] })
    assert_equal [5, 7], rows.first.values_at('bikes', 'free')
    assert_equal({ 'uid' => 'w1', 'address' => 'Piazza', 'has_ebikes' => true, 'ebikes' => 2,
                   'normal_bikes' => 3, 'status' => 'OPEN', 'slots' => 12 }, rows.first['extra'])
    assert_requested :post, 'https://api.weelo.it/connect/token', times: 1
  end

  def test_nubija_extracts_app_token_and_filters_area
    item = { 'station_cd' => '창원', 'x_pos' => '35.2', 'y_pos' => '128.7', 'parking_count' => '8',
             'id' => 'n1', 'tmno' => '42', 'address' => 'Address', 'area' => 'Changwon' }
    stub_request(:get, 'https://ar.nubija.com:55789/v1/station/list/user')
      .with(headers: { 'app-token' => 'fixture-token' })
      .to_return(response({ 'station' => [item, item.merge('area' => 'Other')] }))
    rows = snapshot(client('Nubija', key: '12345678fixture-token87654321', area: 'Changwon'))['stations']

    assert_equal 1, rows.size
    assert_equal ['창원', 35.2, 128.7, 0, 8], rows.first.values_at('name', 'latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 'n1', 'number' => 42, 'address' => 'Address' }, rows.first['extra'])
  end

  def test_bicicard_normalizes_case_and_uses_certificate_thumbprint
    endpoint = 'https://fixtures.example/bicicard'
    stub_request(:get, "#{endpoint}/api/certificado").to_return(response({ 'ThumbPrint' => 'fixture-print' }))
    payload = { 'Nombre' => 'León', 'Latitud' => 42.6, 'Longitud' => -5.57, 'NumeroBicicletasNormales' => 3,
                'NumeroBicicletasElectricas' => 2, 'NumeroCandadosLibres' => 7, 'Id' => 42, 'NumeroCandados' => 12, 'IsPuestoOnline' => true }
    stub_request(:get, "#{endpoint}/apiapp/SBancada/Estado/TodosSimple").with(headers: { 'Thumbprint' => 'fixture-print' })
                                                                        .to_return(response([payload]))
    row = snapshot(client('Bicicard', endpoint: endpoint))['stations'].first

    assert_equal ['León', 42.6, -5.57, 5, 7], row.values_at('name', 'latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 42, 'normal_bikes' => 3, 'ebikes' => 2, 'slots' => 12, 'online' => true }, row['extra'])
  end

  def test_ov_fiets_uses_subscription_key_and_handles_unknown_description_counts
    item = { 'description' => { 'full' => 'Utrecht', 'subDescription' => '12 fietsen' }, 'lat' => 52.09, 'lng' => 5.12,
             'id' => { 'value' => 'location-UTR' } }
    stub_request(:get, %r{\Ahttps://gateway.apiportal.ns.nl/places-api/v2/nearbyme\?})
      .with(headers: { 'Ocp-Apim-Subscription-Key' => 'fixture-key', 'X-MmVehicleExtra' => 'false' }) do |request|
        query = URI.decode_www_form(URI(request.uri.to_s).query)
        query.include?(%w[filterTypes OV_FIETS]) && query.include?(%w[appVersionCapabilities DLA-GreenWheels])
      end.to_return(response({ 'locations' => [item, item.merge('description' => { 'full' => 'Unknown', 'subDescription' => 'unavailable' })] }))
    rows = snapshot(client('OvFiets', key: 'fixture-key'))['stations']

    assert_equal([12, 0], rows.map { |row| row['bikes'] })
    assert_nil rows.first['free']
    assert_equal 'UTR', rows.first['extra']['uid']
  end

  def test_authenticated_clients_reject_missing_keys_before_network_access
    %w[Bicimad BikeshareIE Weelo Nubija OvFiets Digitransit].each do |name|
      assert_raises(RubyBikes::APIKeyNotAvailableError) { client(name) }
    end
  end

  def test_charichari_sends_graphql_variables_and_reports_dock_only_information
    item = { 'title' => '福岡', 'location' => { 'latitude' => 33.59, 'longitude' => 130.4 }, 'capacity' => '12',
             'id' => 'c1', 'address' => 'Address' }
    stub_request(:post, 'https://charichari.bike/api/graphql').with do |request|
      data = JSON.parse(request.body)
      data['operationName'] == 'listPorts' && data['variables'] == { 'regionId' => 'fukuoka' } && data['query'].include?('ports(regionId: $regionId)')
    end.to_return(response({ 'data' => { 'ports' => [item] } }))
    row = snapshot(client('Charichari', region_id: 'fukuoka'))['stations'].first

    assert_equal ['福岡', 33.59, 130.4, 0, 12], row.values_at('name', 'latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 'c1', 'address' => 'Address' }, row['extra'])
  end

  def test_ganxeta_sends_realtime_graphql_operation
    item = { 'station_name' => 'Reus', 'latitude' => '41.15', 'longitude' => '1.11', 'bikes_available' => '4',
             'racks_available' => '8', 'station_id' => 'g1', 'station_address' => 'Address', 'racks_total' => '12', 'station_external_id' => '001' }
    stub_request(:post, 'https://bks-api.ganxeta.cat/rms-bike-sharing-real-time/graphql').with do |request|
      payload = JSON.parse(request.body)
      payload['operationName'] == 'StationsRealtime' && payload['query'].include?('get_data_real_time')
    end.to_return(response({ 'data' => { 'get_data_real_time' => [item] } }))
    row = snapshot(client('Ganxeta'))['stations'].first

    assert_equal ['Reus', 41.15, 1.11, 4, 8], row.values_at('name', 'latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 'g1', 'address' => 'Address', 'slots' => 12, 'number' => '001' }, row['extra'])
  end

  def otp_payload
    types = [%w[BICYCLE HUMAN], %w[BICYCLE ELECTRIC_ASSIST], %w[CARGO_BICYCLE HUMAN], %w[CARGO_BICYCLE ELECTRIC_ASSIST], %w[SCOOTER ELECTRIC]]
    by_type = types.map { |form, power| { 'count' => 2, 'vehicleType' => { 'formFactor' => form, 'propulsionType' => power } } }
    station = { 'stationId' => 'otp1', 'name' => 'Helsinki', 'lat' => 60.17, 'lon' => 24.94, 'operative' => true, 'capacity' => 20,
                'rentalUris' => { 'web' => 'https://example.org/rent' }, 'availableSpaces' => { 'total' => 2_147_483_647 },
                'availableVehicles' => { 'total' => 10, 'byType' => by_type } }
    vehicles = [{ 'vehicleId' => 'bike1', 'lat' => 60.18, 'lon' => 24.95, 'operative' => true,
                  'rentalUris' => { 'web' => 'https://example.org/bike1' }, 'fuel' => { 'percent' => 0.75 },
                  'vehicleType' => { 'formFactor' => 'BICYCLE', 'propulsionType' => 'ELECTRIC_ASSIST' } },
                { 'vehicleId' => 'bike2', 'lat' => 60.19, 'lon' => 24.96, 'operative' => false, 'rentalUris' => nil,
                  'fuel' => { 'percent' => 0 }, 'vehicleType' => { 'formFactor' => 'BICYCLE', 'propulsionType' => 'HUMAN' } }]
    { 'data' => { 'vehicleRentalStations' => [station], 'rentalVehicles' => vehicles } }
  end

  def test_otp_preserves_station_vehicle_types_and_unlimited_docks
    endpoint = 'https://fixtures.example/otp'
    stub_request(:post, endpoint).with do |request|
      payload = JSON.parse(request.body)
      payload['variables'] == {} && payload['query'].include?('vehicleRentalStations') && payload['query'].include?('rentalVehicles')
    end.to_return(response(otp_payload))
    result = snapshot(client('OTP', feed_url: endpoint))
    station = result['stations'].first

    assert_equal ['Helsinki', 60.17, 24.94, 10, 32], station.values_at('name', 'latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 'otp1', 'online' => true, 'slots' => 20, 'rental_uris' => { 'web' => 'https://example.org/rent' },
                   'normal_bikes' => 2, 'ebikes' => 2, 'cargo' => 2, 'ecargo' => 2 }, station['extra'])
    assert_equal(%w[ebike bike], result['vehicles'].map { |vehicle| vehicle['kind'] })
    assert_in_delta(0.75, result['vehicles'].first['extra']['battery'])
    refute result['vehicles'].last['extra'].key?('battery')
    refute result['vehicles'].last['extra']['online']
  end

  def test_digitransit_uses_default_endpoint_subscription_and_geographic_bounds
    stub_request(:post, 'https://api.digitransit.fi/routing/v2/finland/gtfs/v1')
      .with(headers: { 'digitransit-subscription-key' => 'fixture-key' }).to_return(response(otp_payload))
    result = snapshot(client('Digitransit', key: 'fixture-key', bbox: [24.93, 60.16, 24.955, 60.185]))

    assert_equal 1, result['stations'].size
    assert_equal(['bike1'], result['vehicles'].map { |vehicle| vehicle['extra']['uid'] })
  end

  def test_urbansharing_sends_persisted_query_and_preserves_dock_group_metadata
    item = { 'title' => 'Oslo', 'coord' => { 'lat' => 59.91, 'lng' => 10.75 },
             'availabilityInfo' => { 'availableVehicles' => '3', 'availableDocks' => '9' },
             'id' => 'u1', 'subTitle' => 'Address', 'state' => 'active' }
    stub_request(:get, %r{\Ahttps://core\.urbansharing\.com/public/api/v1/graphql\?}).with do |request|
      query = URI.decode_www_form(URI(request.uri.to_s).query).to_h
      query['operationName'] == 'DockGroups' && JSON.parse(query['variables']) == { 'systemId' => 'fixture' } &&
        JSON.parse(query['extensions']).fetch('persistedQuery').fetch('sha256Hash') == '6afd0a33ab1a81d87dd31830e4e3f3da6f9e0881a9a07427b59bf1dec6fd692e'
    end.to_return(response({ 'data' => { 'dockGroups' => [item] } }))
    row = snapshot(client('UrbanSharing'))['stations'].first

    assert_equal ['Oslo', 59.91, 10.75, 3, 9], row.values_at('name', 'latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 'u1', 'address' => 'Address', 'online' => true }, row['extra'])
  end
end
