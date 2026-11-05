# frozen_string_literal: true

require_relative 'test_helper'

class NativeGbfsNextbikeTest < Minitest::Test
  GBFS_CLIENTS = %w[Ambici BCycle Beryl Careem Cyclocity Derp Callabike DB Docomo Ecovelo Gbfs HelloCycling NextbikeGbfs OpenSourceBikeShareV2 SharedMobility Velib].freeze
  ROOT = 'https://fixtures.example/gbfs/'

  def setup
    @specs = JSON.parse(File.read(File.join(RubyBikes::Native::DATA, 'providers.json')))
    @information = { 'station_id' => 's1', 'stationCode' => 'traditional-code', 'name' => [{ 'text' => 'École' }],
                     'lat' => 35.681236, 'lon' => 139.767125, 'capacity' => 12, 'address' => 'Station Road',
                     'post_code' => '100-0005', 'altitude' => 10, 'rental_methods' => %w[CREDITCARD KEY],
                     'rental_uris' => { 'android' => 'app://station', 'web' => 'https://example.org/station', 'private' => 'ignored' } }
    @status = { 'station_id' => 's1', 'is_installed' => 1, 'is_renting' => 1, 'is_returning' => 0,
                'num_bikes_available' => 3, 'num_docks_available' => 9, 'last_reported' => 1_793_550_000 }
    @vehicles = [{ 'bike_id' => 'bike-1', 'lat' => 35.68124, 'lon' => 139.76713, 'is_disabled' => false,
                   'is_reserved' => false, 'type' => 'electric_bike', 'current_fuel_percent' => 0.5 }]
  end

  def client(name = 'Gbfs', key: :default, **parameters)
    spec = @specs.find { |item| item['class'] == name }
    options = { 'tag' => 'fixture', 'meta' => { 'name' => 'Fixture' }, 'feed_url' => "#{ROOT}gbfs.json", 'uid' => 13,
                'contract' => 'TEST', 'dataset' => 'fixture', 'domain' => 'fixture', 'provider' => 'Fixture' }.merge(parameters.transform_keys(&:to_s))
    if key == :default
      key = if spec['authed']
              name == 'SharedMobility' ? 'fixture@example.org' : { 'client_id' => 'fixture-id', 'client_secret' => 'fixture-secret' }
            end
    end
    RubyBikes::Native::Gbfs.new(spec, options, key: key)
  end

  def json_response(payload, status: 200)
    { status: status, body: JSON.generate(payload), headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_feed(network, language: true, vehicle_feed: 'free_bike_status', types: nil)
    names = ['station_information', 'station_status', vehicle_feed]
    names << 'vehicle_types' if types
    discovery = { 'feeds' => names.map { |name| { 'name' => name, 'url' => "#{ROOT}#{name}.json" } } }
    discovery = { 'en' => discovery } if language
    stub_request(:get, network.meta.fetch('gbfs_href')).to_return(json_response({ 'data' => discovery }))
    stub_request(:get, "#{ROOT}station_information.json").to_return(json_response({ 'data' => { 'stations' => [@information] } }))
    stub_request(:get, "#{ROOT}station_status.json").to_return(json_response({ 'data' => { 'stations' => [@status] } }))
    key = vehicle_feed == 'vehicle_status' ? 'vehicles' : 'bikes'
    stub_request(:get, "#{ROOT}#{vehicle_feed}.json").to_return(json_response({ 'data' => { key => @vehicles } }))
    stub_request(:get, "#{ROOT}vehicle_types.json").to_return(json_response({ 'data' => { 'vehicle_types' => types } })) if types
  end

  GBFS_CLIENTS.each do |name|
    define_method("test_#{name.downcase}_updates_stations_and_vehicles") do
      @status['num_bikes_available_types'] = if name == 'Velib'
                                               [{ 'mechanical' => 2 }, { 'ebike' => 1 }]
                                             else
                                               (name == 'BCycle' ? { 'classic' => 2, 'electric' => 1 } : { 'mechanical' => 2, 'ebike' => 1 })
                                             end
      network = client(name)
      stub_feed(network)
      row = network.snapshot(RubyBikes::Native::Transport.new)

      assert_equal 1, row['stations'].size, name
      assert_equal 1, row['vehicles'].size, name
      station = row['stations'].first

      assert_equal ['École', 35.681236, 139.767125, 3, 9], station.values_at('name', 'latitude', 'longitude', 'bikes', 'free')
      assert_equal ['bike-1', 'ebike', 0.5], [row['vehicles'][0]['extra']['uid'], row['vehicles'][0]['kind'], row['vehicles'][0]['extra']['battery']]
      assert_equal 'Station Road', station['extra']['address']
      assert_equal %w[creditcard key], station['extra']['payment']
      assert_equal({ 'android' => 'app://station', 'web' => 'https://example.org/station' }, station['extra']['rental_uris'])
      assert_equal [2, 1], station['extra'].values_at('normal_bikes', 'ebikes')
      if name == 'Velib'
        assert_equal ['traditional-code', 's1', true, true], station['extra'].values_at('uid', 'station_id', 'banking', 'payment-terminal')
      else
        assert_equal 's1', station['extra']['uid']
      end
      case name
      when 'DB', 'Callabike'

        assert_requested(:get, network.meta['gbfs_href'], headers: { 'DB-Client-Id' => 'fixture-id', 'DB-Api-Key' => 'fixture-secret', 'Accept' => 'application/json' })
      when 'SharedMobility'

        assert_requested(:get, network.meta['gbfs_href'], headers: { 'Authorization' => 'fixture@example.org' })
      end
    end
  end

  def test_factory_inventory_contains_exactly_the_tested_gbfs_classes
    assert_equal GBFS_CLIENTS.sort, @specs.select { |item| item['gbfs'] }.map { |item| item['class'] }.sort
  end

  def test_gbfs_three_uses_direct_feeds_vehicle_counts_and_vehicle_ids
    @status.delete('num_bikes_available')
    @status['num_vehicles_available'] = '4'
    @status['last_reported'] = '2026-11-01T17:00:00+01:00'
    @vehicles = [{ 'vehicle_id' => 'v3', 'lat' => 35.68124, 'lon' => 139.76713, 'is_disabled' => true }]
    network = client
    stub_feed(network, language: false, vehicle_feed: 'vehicle_status')
    row = network.snapshot(RubyBikes::Native::Transport.new)

    assert_equal 4, row['stations'][0]['bikes']
    assert_equal '2026-11-01T16:00:00Z', row['stations'][0]['extra']['last_updated']
    assert_equal 'v3', row['vehicles'][0]['extra']['uid']
    refute row['vehicles'][0]['extra']['online']
  end

  def test_operator_counts_with_leading_zeroes_are_decimal
    @status['num_bikes_available'] = '08'
    @status['num_docks_available'] = '09'
    network = client
    stub_feed(network)
    row = network.snapshot(RubyBikes::Native::Transport.new)['stations'].first

    assert_equal [8, 9], row.values_at('bikes', 'free')
  end

  def test_missing_counts_remain_nil_and_zero_counts_remain_zero
    @status.delete('num_bikes_available')
    @status.delete('num_docks_available')
    network = client
    stub_feed(network)
    station = network.snapshot(RubyBikes::Native::Transport.new)['stations'].first

    assert_nil station['bikes']
    assert_nil station['free']
    @status.merge!('num_bikes_available' => 0, 'num_docks_available' => 0)
    stub_feed(network)
    station = network.snapshot(RubyBikes::Native::Transport.new)['stations'].first

    assert_equal [0, 0], station.values_at('bikes', 'free')
  end

  def test_type_counts_include_cargo_scooters_and_unsupported_types_are_ignored
    types = [
      { 'vehicle_type_id' => 'human', 'form_factor' => 'bicycle', 'propulsion_type' => 'human' },
      { 'vehicle_type_id' => 'assist', 'form_factor' => 'bicycle', 'propulsion_type' => 'electric_assist' },
      { 'vehicle_type_id' => 'electric', 'form_factor' => 'bicycle', 'propulsion_type' => 'electric' },
      { 'vehicle_type_id' => 'cargo', 'form_factor' => 'cargo_bicycle', 'propulsion_type' => 'human' },
      { 'vehicle_type_id' => 'ecargo', 'form_factor' => 'cargo_bicycle', 'propulsion_type' => 'electric_assist' },
      { 'vehicle_type_id' => 'scooter', 'form_factor' => 'scooter_standing', 'propulsion_type' => 'electric' },
      { 'vehicle_type_id' => 'unsupported', 'form_factor' => 'car', 'propulsion_type' => 'combustion' }
    ]
    @status['num_bikes_available'] = 0
    @status['vehicle_types_available'] = types.map { |type| { 'vehicle_type_id' => type['vehicle_type_id'], 'count' => 2 } } + [{ 'vehicle_type_id' => 'missing', 'count' => 9 }]
    @vehicles = types.map do |type|
      { 'vehicle_type_id' => type['vehicle_type_id'], 'bike_id' => type['vehicle_type_id'], 'lat' => 35.68124, 'lon' => 139.76713, 'is_disabled' => false }
    end
    @vehicles << { 'station_id' => 's1' }
    @vehicles << { 'vehicle_type_id' => 'missing' }
    network = client
    stub_feed(network, types: types)
    row = network.snapshot(RubyBikes::Native::Transport.new)

    assert_equal 6, row['stations'][0]['bikes']
    assert_equal [2, 4, 2, 2, 2], row['stations'][0]['extra'].values_at('normal_bikes', 'ebikes', 'cargo', 'ecargo', 'scooters')
    assert_equal(%w[bike ebike ebike bike ebike scooter], row['vehicles'].map { |item| item['kind'] })
    assert row['stations'][0]['extra']['has_ecargo']
    assert row['stations'][0]['extra']['has_scooters']
  end

  def test_legacy_vehicle_type_can_override_a_resolved_type
    types = [{ 'vehicle_type_id' => 'normal', 'form_factor' => 'bicycle', 'propulsion_type' => 'human' }]
    @vehicles[0]['vehicle_type_id'] = 'normal'
    @vehicles[0]['type'] = 'electric_scooter'
    network = client
    stub_feed(network, types: types)

    assert_equal 'scooter', network.snapshot(RubyBikes::Native::Transport.new)['vehicles'].first['kind']
  end

  def test_information_status_intersection_planned_stations_and_region_filter
    network = client(region_id: 'region-1')
    stub_feed(network)
    information = [@information.merge('region_id' => 'region-1'), @information.merge('station_id' => 'no-status', 'region_id' => 'region-1'),
                   @information.merge('station_id' => 'other', 'region_id' => 'region-2')]
    statuses = [@status, @status.merge('station_id' => 'other'), @status.merge('station_id' => 'no-information')]
    stub_request(:get, "#{ROOT}station_information.json").to_return(json_response({ 'data' => { 'stations' => information } }))
    stub_request(:get, "#{ROOT}station_status.json").to_return(json_response({ 'data' => { 'stations' => statuses } }))

    assert_equal 1, network.snapshot(RubyBikes::Native::Transport.new)['stations'].size
    statuses[0]['is_installed'] = false
    stub_request(:get, "#{ROOT}station_status.json").to_return(json_response({ 'data' => { 'stations' => statuses } }))

    assert_empty network.snapshot(RubyBikes::Native::Transport.new)['stations']
  end

  def test_ignore_errors_only_skips_invalid_station_payloads_when_requested
    @information['lat'] = 'invalid'
    network = client(ignore_errors: true)
    stub_feed(network)

    assert_empty network.snapshot(RubyBikes::Native::Transport.new)['stations']
    strict = client
    assert_raises(ArgumentError) { strict.snapshot(RubyBikes::Native::Transport.new) }
  end

  def test_discovery_fallback_authentication_failure_and_rate_limit
    network = client
    stub_request(:get, network.meta['gbfs_href']).to_return(status: 404)
    stub_request(:get, "#{ROOT}station_information.json").to_return(json_response({ 'data' => { 'stations' => [@information] } }))
    stub_request(:get, "#{ROOT}station_status.json").to_return(json_response({ 'data' => { 'stations' => [@status] } }))

    assert_equal 1, network.snapshot(RubyBikes::Native::Transport.new)['stations'].size
    stub_request(:get, network.meta['gbfs_href']).to_return(status: 401, body: 'private response')
    error = assert_raises(RubyBikes::ProviderError) { network.snapshot(RubyBikes::Native::Transport.new) }
    refute_includes error.message, 'private response'
    stub_request(:get, network.meta['gbfs_href']).to_return(status: 429, headers: { 'Retry-After' => '120' })

    assert_equal 120, assert_raises(RubyBikes::RateLimitedError) { network.snapshot(RubyBikes::Native::Transport.new) }.retry_after
  end

  def test_hardcoded_feeds_skip_discovery_and_force_https
    network = client(station_information: 'http://fixtures.example/gbfs/station_information.json', station_status: 'http://fixtures.example/gbfs/station_status.json',
                     force_https: true)
    stub_request(:get, "#{ROOT}station_information.json").to_return(json_response({ 'data' => { 'stations' => [@information] } }))
    stub_request(:get, "#{ROOT}station_status.json").to_return(json_response({ 'data' => { 'stations' => [@status] } }))

    assert_equal 1, network.snapshot(RubyBikes::Native::Transport.new)['stations'].size
    assert_not_requested :get, network.meta['gbfs_href']
  end

  def test_query_arguments_are_forwarded_and_non_english_discovery_is_supported
    network = client(feed_url: "#{ROOT}gbfs.json?key=fixture", append_feed_args_to_req: true)
    feeds = { 'fr' => { 'feeds' => %w[station_information station_status].map { |name| { 'name' => name, 'url' => "#{ROOT}#{name}.json" } } } }
    stub_request(:get, "#{ROOT}gbfs.json").with(query: 'key=fixture&key=fixture').to_return(json_response({ 'data' => feeds }))
    stub_request(:get, "#{ROOT}station_information.json?key=fixture").to_return(json_response({ 'data' => { 'stations' => [@information] } }))
    stub_request(:get, "#{ROOT}station_status.json?key=fixture").to_return(json_response({ 'data' => { 'stations' => [@status] } }))

    assert_equal 1, network.snapshot(RubyBikes::Native::Transport.new)['stations'].size
  end

  def test_constructor_urls_company_metadata_and_required_parameters
    assert_equal 'https://api.cyclocity.fr/contracts/test/gbfs/gbfs.json', client('Cyclocity').meta['gbfs_href']
    assert_equal 'https://gbfs.nextbike.net/maps/gbfs/v2/nextbike_fixture/gbfs.json', client('NextbikeGbfs').meta['gbfs_href']
    assert_equal ['Operator', 'BCycle, LLC'], client('BCycle', meta: { 'company' => ['Operator'] }).meta['company']
    assert_raises(RubyBikes::APIKeyNotAvailableError) { client('SharedMobility', key: nil) }
    assert_raises(ArgumentError) { client('Docomo', uid: 'nonexistent') }
    spec = @specs.find { |item| item['class'] == 'NextbikeGbfs' }
    assert_raises(KeyError) { RubyBikes::Native::Gbfs.new(spec, { 'tag' => 'custom', 'meta' => {} }) }
  end

  def test_bounding_box_filters_both_stations_and_vehicles
    network = client(bbox: [0, 0, 1, 1])
    stub_feed(network)
    row = network.snapshot(RubyBikes::Native::Transport.new)

    assert_empty row['stations']
    assert_empty row['vehicles']
  end

  def test_invalid_last_reported_is_preserved_as_unknown
    @status['last_reported'] = 'invalid timestamp'
    @status['num_ebikes_available'] = 0
    network = client
    stub_feed(network)
    extra = network.snapshot(RubyBikes::Native::Transport.new)['stations'].first['extra']

    assert_nil extra['last_updated']
    assert_equal 0, extra['ebikes']
    assert extra['has_ebikes']
  end

  %w[Nextbike Bizkaibizi].each do |name|
    define_method("test_#{name.downcase}_xml_stations_and_vehicles") do
      spec = @specs.find { |item| item['class'] == name }
      network = RubyBikes::Native::Nextbike.new(spec, { 'tag' => 'fixture', 'meta' => { 'name' => 'Fixture' }, 'domain' => 'fixture', 'city_uid' => 'city-1' })
      xml = <<~XML
        <markers><country><city uid="city-1">
          <place uid="s1" name="Station" lat="48.85" lng="2.35" spot="1" bikes="5+" bike_racks="12" free_racks="6" number="001" bike_numbers="one,two," place_type="17" />
          <place uid="s2" name="Unknown racks" lat="48.86" lng="2.36" spot="1" bike_types='{"bike":2,"ebike":"3+"}' />
          <place uid="s3" name="Computed spaces" lat="48.87" lng="2.37" spot="1" bikes="2" bike_racks="12" />
          <place lat="48.88" lng="2.38" bike="1"><bike number="vehicle-1" active="1" /></place>
        </city><city uid="city-2"><place uid="ignore" name="Other city" lat="1" lng="1" spot="1" bikes="1" /></city></country></markers>
      XML
      stub_request(:get, 'https://maps.nextbike.net/maps/nextbike-live.xml?domains=fixture').to_return(body: xml)
      row = network.snapshot(RubyBikes::Native::Transport.new)

      assert_equal 3, row['stations'].size
      assert_equal [5, 6], row['stations'][0].values_at('bikes', 'free')
      assert_equal({ 'uid' => 's1', 'virtual' => true, 'number' => '001', 'bikes_approximate' => true, 'slots' => 12, 'bike_uids' => %w[one two] }, row['stations'][0]['extra'])
      assert_equal 5, row['stations'][1]['bikes']
      assert_nil row['stations'][1]['free']
      assert_equal 10, row['stations'][2]['free']
      assert_equal 1, row['vehicles'].size
      assert_equal({ 'uid' => 'vehicle-1', 'online' => true }, row['vehicles'][0]['extra'])
    end
  end

  def test_nextbike_constructor_requires_domain_and_rejects_malformed_xml
    spec = @specs.find { |item| item['class'] == 'Nextbike' }
    assert_raises(KeyError) { RubyBikes::Native::Nextbike.new(spec, { 'tag' => 'fixture', 'meta' => {} }) }
    network = RubyBikes::Native::Nextbike.new(spec, { 'tag' => 'fixture', 'meta' => {}, 'domain' => 'test' })
    stub_request(:get, 'https://maps.nextbike.net/maps/nextbike-live.xml?domains=test').to_return(body: '<markers><country></markers>')
    assert_raises(Nokogiri::XML::SyntaxError) { network.snapshot(RubyBikes::Native::Transport.new) }
  end

  def test_nextbike_filters_bounds_before_parsing_places_and_decimal_counts
    spec = @specs.find { |item| item['class'] == 'Nextbike' }
    network = RubyBikes::Native::Nextbike.new(spec, { 'tag' => 'fixture', 'meta' => {}, 'domain' => 'test', 'bbox' => [2, 48, 3, 49] })
    xml = <<~XML
      <markers>
      <country>
      <city>
      <place uid="good" name="Station" lat="48.5" lng="2.5" spot="1" bikes="08" bike_racks="12" free_racks="09"/>
      <place lat="0" lng="0" spot="1"/>
      </city>
      </country>
      </markers>
    XML
    stub_request(:get, 'https://maps.nextbike.net/maps/nextbike-live.xml?domains=test').to_return(body: xml)
    rows = network.snapshot(RubyBikes::Native::Transport.new)['stations']

    assert_equal 1, rows.size
    assert_equal [8, 9], rows.first.values_at('bikes', 'free')
  end

  def test_nextbike_blank_bike_types_use_the_reported_total_without_changing_vehicle_ids
    spec = @specs.find { |item| item['class'] == 'Nextbike' }
    network = RubyBikes::Native::Nextbike.new(spec, { 'tag' => 'fixture', 'meta' => {}, 'domain' => 'test' })
    xml = <<~XML
      <markers><country><city>
        <place uid="empty" name="Empty station" lat="48.85" lng="2.35" spot="1" bikes="0" bike_types="" bike_racks="10"/>
        <place uid="available" name="Available station" lat="48.86" lng="2.36" spot="1" bikes="08" bike_types="" free_racks="02" bike_racks="10"/>
        <place uid="approximate" name="Approximate station" lat="48.87" lng="2.37" spot="1" bikes="5+" bike_types=" " bike_racks="10"/>
        <place uid="typed" name="Typed station" lat="48.88" lng="2.38" spot="1" bikes="5+" bike_types='{&quot;196&quot;:4,&quot;431&quot;:&quot;2+&quot;}'/>
        <place lat="48.89" lng="2.39" bike="1"><bike number="vehicle-1" active="1"/></place>
      </city></country></markers>
    XML
    stub_request(:get, 'https://maps.nextbike.net/maps/nextbike-live.xml?domains=test').to_return(body: xml)
    snapshot = network.snapshot(RubyBikes::Native::Transport.new)

    assert_equal([0, 8, 5, 6], snapshot['stations'].map { |station| station['bikes'] })
    assert_equal([10, 2, 5, nil], snapshot['stations'].map { |station| station['free'] })
    assert snapshot['stations'][2]['extra']['bikes_approximate']
    assert snapshot['stations'][3]['extra']['bikes_approximate']
    assert_equal Digest::MD5.hexdigest('fixture,vehicle-1'), snapshot['vehicles'].first['id']
  end

  def test_nextbike_nonempty_invalid_bike_types_do_not_become_false_zero_counts
    spec = @specs.find { |item| item['class'] == 'Nextbike' }
    network = RubyBikes::Native::Nextbike.new(spec, { 'tag' => 'fixture', 'meta' => {}, 'domain' => 'test' })
    xml = '<markers><country><city><place uid="bad" name="Invalid types" lat="48.85" lng="2.35" spot="1" bikes="5" bike_types="invalid"/></city></country></markers>'
    stub_request(:get, 'https://maps.nextbike.net/maps/nextbike-live.xml?domains=test').to_return(body: xml)
    assert_raises(JSON::ParserError) { network.snapshot(RubyBikes::Native::Transport.new) }
  end

  def test_nextbike_rejects_an_unknown_city
    spec = @specs.find { |item| item['class'] == 'Nextbike' }
    network = RubyBikes::Native::Nextbike.new(spec, { 'tag' => 'fixture', 'meta' => {}, 'domain' => 'test', 'city_uid' => 'missing' })
    stub_request(:get, 'https://maps.nextbike.net/maps/nextbike-live.xml?domains=test').to_return(body: '<markers><country><city uid="exists"/></country></markers>')
    assert_raises(RubyBikes::ProviderError) { network.snapshot(RubyBikes::Native::Transport.new) }
  end
end
