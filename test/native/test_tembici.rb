# frozen_string_literal: true

require_relative 'test_helper'

class TembiciTest < Minitest::Test
  URL = 'https://www.tembici.com.br/pt/belo-horizonte/'
  MAP = File.read(File.join(__dir__, 'fixtures/html/tembici.html')).freeze

  def test_public_station_map
    stub_request(:get, URL).to_return(body: MAP)

    RubyBikes.open do |bikes|
      system = bikes.get('tembici-belo-horizonte').update

      assert_equal 'Belo Horizonte', system.meta.fetch('city')
      assert_equal 'Tembici', system.client_class
      assert_equal ['Praça do Parque', 'Estação Central'], system.stations.map(&:name)
      station = system.stations.first

      assert_equal [-19.843916, -43.968333], [station.latitude, station.longitude]
      assert_equal Digest::MD5.hexdigest('-19843916,-43968333'), station.id
      assert_equal({ 'uid' => '01', 'has_ebikes' => true }, station.extra)
      assert_nil station.bikes
      assert_nil station.free
      assert_nil station.timestamp
    end
    assert_requested(:get, URL, times: 1)
  end

  def test_rejects_incomplete_station_updates
    stub_request(:get, URL).to_return(
      { body: MAP },
      { body: MAP.sub(';03|-19.863026|-43.970133', '') },
      { body: MAP.sub('-19.843916', '91') },
      { body: '<html>Station map unavailable</html>' }
    )

    RubyBikes.open do |bikes|
      system = bikes.get('tembici-belo-horizonte').update
      original = system.stations
      3.times do
        assert_raises(RubyBikes::ProviderError) { system.update }
        assert_same original, system.stations
      end
    end
  end
end
