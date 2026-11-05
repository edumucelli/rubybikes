# frozen_string_literal: true

require 'minitest/autorun'
require 'webmock/minitest'
require 'json'
require_relative '../../lib/rubybikes/native'
require_relative '../../lib/rubybikes/native/xml_details'

class NativeXmlDetailsTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path('fixtures/xml_details', __dir__)
  FEED = 'https://example.org/feed'

  def setup
    WebMock.disable_net_connect!
    @specs = JSON.parse(File.read(File.expand_path('../../data/providers.json', __dir__)))
  end

  def fixture(name)
    File.read(File.join(FIXTURE_ROOT, name))
  end

  def provider(name, **parameters)
    spec = @specs.find { |item| item.fetch('class') == name }
    RubyBikes::Native::JsonProviders.new(spec, { 'tag' => 'fixture', 'meta' => {}, 'feed_url' => FEED }.merge(parameters.transform_keys(&:to_s)))
  end

  def snapshot(name, **parameters)
    provider(name, **parameters).snapshot(RubyBikes::Native::Transport.new)
  end

  def test_bixi_preserves_boolean_metadata_names_and_identity
    stub_request(:get, FEED).to_return(body: fixture('bixi.xml'))
    row = snapshot('BixiSystem')

    assert_equal 2, row.fetch('stations').length
    station = row['stations'].first

    assert_equal '6001 - Notre Dame / Place Jacques Cartier', station['name']
    assert_equal [45.508183, -73.554094, 14, 17], station.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal Digest::MD5.hexdigest('45508183,-73554094'), station['id']
    assert_equal({ 'uid' => 1, 'name' => 'Notre Dame / Place Jacques Cartier', 'terminalName' => '6001',
                   'locked' => false, 'installed' => true, 'temporary' => false, 'installDate' => '1276012920000',
                   'removalDate' => '', 'latestUpdateTime' => '1793550000' }, station['extra'])
    second = row['stations'].last['extra']

    assert second['locked']
    assert second['temporary']
    refute second.key?('latestUpdateTime')
    assert_predicate Time.iso8601(station['timestamp']), :utc?
  end

  def test_decobike_preserves_xml_headers_and_utf8_address
    stub_request(:get, FEED).with(headers: { 'X-Requested-With' => 'com.citibike.miami', 'Accept-Language' => 'en-US,en;q=0.9' })
                            .to_return(body: fixture('decobike.xml'))
    row = snapshot('DecoBike')['stations'].fetch(0)

    assert_equal 'miami-7 - Ocean & École', row['name']
    assert_equal [25.79065, -80.13005, 4, 6], row.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 'miami-7', 'address' => 'Ocean & École' }, row['extra'])
    assert_equal [], snapshot('DecoBike', bbox: [0, 0, 1, 1])['stations']
  end

  def test_xian_sends_soap_and_decodes_namespaced_json
    stub_request(:post, FEED).with(headers: { 'Content-Type' => 'text/xml; charset=utf-8' }) do |request|
      document = Nokogiri::XML(request.body)
      document.xpath('//q:findBikeSites', 'q' => 'http://ws.itcast.cn/').length == 1
    end.to_return(body: fixture('xian.xml'))
    row = snapshot('Xian', endpoint: FEED)['stations'].fetch(0)

    assert_equal '和平广场', row['name']
    assert_equal [34.26, 108.95, 3, 7], row.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 'x-1', 'slots' => 10, 'address' => '东大街' }, row['extra'])
  end

  def test_bicincitta_fetches_each_city_and_station_details
    station_url = 'https://example.org/frmLeStazioniComune.aspx/RefreshStations'
    detail_url = 'https://example.org/frmLeStazioni.aspx/RefreshPopup'
    stub_request(:post, station_url).with(body: JSON.generate('IDComune' => '4'), headers: { 'Content-Type' => 'application/json; charset=utf-8' })
                                    .to_return(body: fixture('bicincitta_stations.json'))
    stub_request(:post, station_url).with(body: JSON.generate('IDComune' => '5')).to_return(body: JSON.generate('d' => ['header']))
    stub_request(:post, detail_url).with(body: JSON.generate('IDStazione' => '7')).to_return(body: fixture('bicincitta_details.json'))
    network = provider('Bicincitta', endpoint: 'https://example.org/', city_ids: [4, 5])

    assert_equal 'https://example.org/frmLeStazioni.aspx?ID=4', network.meta['source']
    row = network.snapshot(RubyBikes::Native::Transport.new)['stations'].fetch(0)

    assert_equal 'Bellucci', row['name']
    assert_in_delta 43.106527599999986, row['latitude'], 0.0000001
    assert_in_delta 12.38971570000001, row['longitude'], 0.0000001
    assert_equal [2, 3], row.values_at('bikes', 'free')
    assert_equal({ 'uid' => '7', 'number' => 8, 'status' => 'under construction', 'score' => 4.5, 'reviews' => 12 }, row['extra'])
    assert_requested :post, station_url, times: 2
  end

  def test_bicincitta_uses_default_endpoint_and_falls_back_to_short_coordinate
    stub_request(:post, 'https://www.bicincitta.com/frmLeStazioniComune.aspx/RefreshStations')
      .to_return(body: JSON.generate('d' => ['header', '1§43.1§12.2§Short coordinate§1§0']))
    stub_request(:post, 'https://www.bicincitta.com/frmLeStazioni.aspx/RefreshPopup')
      .to_return(body: fixture('bicincitta_details.json'))
    row = snapshot('Bicincitta', city_ids: [1])['stations'].first

    assert_equal [43.1, 12.2], row.values_at('latitude', 'longitude')
  end

  def test_pedalada_fetches_details_and_uses_detail_status
    endpoint = 'https://example.org'
    stub_request(:get, "#{endpoint}/php/get-stations-details-map.php").to_return(body: fixture('pedalada_stations.json'))
    stub_request(:get, "#{endpoint}/php/get-station-details-and-rides.php").with(query: { 'n' => '23' }).to_return(body: fixture('pedalada_details.json'))
    row = snapshot('Pedalada', endpoint: endpoint)['stations'].first

    assert_equal [39.2, -8.7, 3, 5], row.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => 23, 'slots' => 8, 'online' => true, 'photo' => 'https://example.org/images/stations/station_23.jpg', 'status' => 'maintenance' }, row['extra'])
    meta = provider('Pedalada', endpoint: endpoint, meta: { 'company' => ['Operator'] }).meta

    assert_equal ['Operator', 'Share2Go - Mobilidade Partilhada, Sociedade Unipessoal Lda'], meta['company']
  end

  def test_pedalada_recognizes_open_and_closed_detail_status
    endpoint = 'https://example.org'
    stub_request(:get, "#{endpoint}/php/get-stations-details-map.php").to_return(body: fixture('pedalada_stations.json'))
    [true, false].each do |open|
      detail = JSON.parse(fixture('pedalada_details.json'))
      detail['details'][0] = { 'stationInMaintenance' => false, 'stationIsOpen' => open }
      stub_request(:get, "#{endpoint}/php/get-station-details-and-rides.php?n=23").to_return(body: JSON.generate(detail))

      assert_equal(open ? 'open' : 'closed', snapshot('Pedalada', endpoint: endpoint)['stations'].first['extra']['status'])
    end
  end

  def test_fsm_includes_electric_and_normal_bikes_and_docks
    endpoint = 'https://www.tel-o-fun.co.il/api/privatearea/v1'
    stub_request(:get, "#{endpoint}/map").with(headers: { 'Accept-Language' => 'en' }).to_return(body: fixture('fsm_stations.json'))
    stub_request(:get, "#{endpoint}/station/1").with(headers: { 'Accept-Language' => 'en' }).to_return(body: fixture('fsm_details.json'))
    row = snapshot('FSMSystem')['stations'].first

    assert_equal 'Tel Aviv', row['name']
    assert_equal [32.08, 34.78, 5, 9], row.values_at('latitude', 'longitude', 'bikes', 'free')
    assert_equal({ 'uid' => '1', 'number' => '01', 'shabbat' => true, 'has_ebikes' => true, 'ebikes' => 2,
                   'normal_bikes' => 3, 'normal_slots' => 5, 'e_slots' => 4, 'address' => 'Rothschild Boulevard' }, row['extra'])
  end

  def test_malformed_xml_does_not_become_an_empty_successful_update
    stub_request(:get, FEED).to_return(body: '<stations><station></stations>')
    assert_raises(Nokogiri::XML::SyntaxError) { snapshot('BixiSystem') }
  end

  def test_missing_namespaced_payload_is_rejected
    stub_request(:post, FEED).to_return(body: '<response><out>[]</out></response>')
    assert_raises(JSON::ParserError) { snapshot('Xian', endpoint: FEED) }
  end

  def test_station_detail_failure_aborts_the_update
    endpoint = 'https://www.tel-o-fun.co.il/api/privatearea/v1'
    stub_request(:get, "#{endpoint}/map").to_return(body: fixture('fsm_stations.json'))
    stub_request(:get, "#{endpoint}/station/1").to_timeout
    assert_raises(RubyBikes::TimeoutError) { snapshot('FSMSystem') }
  end

  def test_detail_requests_share_the_overall_deadline
    now = 0.0
    endpoint = 'https://www.tel-o-fun.co.il/api/privatearea/v1'
    stub_request(:get, "#{endpoint}/map").to_return do
      now = 61.0
      { body: fixture('fsm_stations.json') }
    end
    transport = RubyBikes::Native::Transport.new(timeout: 60, clock: -> { now })
    assert_raises(RubyBikes::TimeoutError) { provider('FSMSystem').snapshot(transport) }
    assert_not_requested :get, "#{endpoint}/station/1"
  end
end
