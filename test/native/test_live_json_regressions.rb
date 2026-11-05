# frozen_string_literal: true

require_relative 'test_helper'
require 'minitest/mock'

class NativeLiveJsonRegressionsTest < Minitest::Test
  include NativeFixtures

  def test_easybike_null_station_feed_is_an_explicit_provider_error
    url = 'http://reseller.easybike.gr/didymoteicho/api.php'
    stub_request(:get, url).to_return(response({ 'tenant_id' => '19', 'stations' => nil }))
    network = provider('EasyBike', city_uid: 'didymoteicho')
    error = assert_raises(RubyBikes::ProviderError) { snapshot(network) }
    assert_equal 'Provider currently publishes no station feed', error.message
    refute_includes error.message, url
    assert_requested(:get, url)
  end

  def test_easybike_empty_but_valid_feed_remains_an_empty_snapshot
    url = 'http://reseller.easybike.gr/fixture/api.php'
    stub_request(:get, url).to_return(response({ 'tenant_id' => 'fixture', 'stations' => [] }))

    assert_empty snapshot(provider('EasyBike', city_uid: 'fixture'))['stations']
    assert_requested(:get, url)
  end

  def test_publibike_ignores_null_canton_geometry_before_filtering_both_operators
    feature = { 'type' => 'Feature', 'properties' => { 'NAME' => 'Fixture' },
                'geometry' => { 'type' => 'Polygon', 'coordinates' => [[[7, 46], [9, 46], [9, 48], [7, 48], [7, 46]]] } }
    cantons = { 'type' => 'FeatureCollection', 'features' => [feature.merge('geometry' => nil), feature] }
    payload = { 'publibike' => { 'stations' => [{ 'name' => 'Inside', 'latitude' => 47.0, 'longitude' => 8.0,
                                                  'id' => 'one', 'address' => 'Address', 'zip' => '0000', 'city' => 'Fixture', 'capacity' => 12,
                                                  'vehicles' => [{ 'type' => { 'id' => 2 } }] }] }, 'velospot' => { 'responseData' => [
                                                    { 'station_name' => 'Velospot inside', 'lat' => 47.1, 'lng' => 8.1, 'totalBike' => '3', 'station_id' => 'two',
                                                      'station_address' => 'Address', 'totalElectricalBike' => '1', 'totalNonElectricalBike' => '2' },
                                                    { 'station_name' => 'Outside', 'lat' => 45.0, 'lng' => 6.0, 'totalBike' => '3', 'station_id' => 'three',
                                                      'station_address' => 'Address', 'totalElectricalBike' => '1', 'totalNonElectricalBike' => '2' }
                                                  ] } }
    stub_request(:get, 'https://rest.publibike.ch/v1/public/all/stations').to_return(response(payload))
    # Match the real resource shape: several Swiss canton features legitimately
    # contain null geometries alongside usable polygon features.
    resource = File.join(RubyBikes::Native::DATA, 'geojson/ch_cantons.json')
    original_read = File.method(:read)
    replacement = lambda do |file, *arguments|
      file == resource ? JSON.generate(cantons) : original_read.call(file, *arguments)
    end
    data = File.stub(:read, replacement) { snapshot(provider('Publibike', canton: 'Fixture')) }

    assert_equal(['Inside', 'Velospot inside'], data['stations'].map { |row| row['name'] })
    assert_equal [1, 11], data['stations'].first.values_at('bikes', 'free')
    assert_equal [3, 0], data['stations'].last.values_at('bikes', 'free')
    assert_requested(:get, 'https://rest.publibike.ch/v1/public/all/stations')
  end
end
