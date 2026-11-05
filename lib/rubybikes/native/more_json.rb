# frozen_string_literal: true

# Native adaptations of PyBikes clients, AGPL-3.0; see NOTICE for attribution.
class RubyBikes
  module Native
    class JsonProviders
      def update_baksi
        JSON.parse(html_capture(request(p('feed_url')), /var all = (\[.*\]);/)).each do |s|
          uid, name = s[0].split('-', 2)
          station(name, s[5], s[6], number(s[2][/\d+/]), number(s[3][/\d+/]), { 'uid' => uid, 'online' => s[1].include?('Aktif') })
        end
      end

      def update_chartered_bike
        data = json('https://api.charteredbike.in/api/v1/stations/get-all-station',
                    params: { 'lat' => 21.1940305, 'long' => 72.825347, 'version' => '1.9.2', 'buildNumber' => 283 }, headers: { 'User-Agent' => 'okhttp/3.12.1',
                                                                                                                                 'Accept' => 'application/json, text/plain, */*' })
        raise ProviderError, 'Provider returned unsuccessful status' unless data['status'] == 200

        data.fetch('data').each do |s|
          station(s['stationName'], s['latitude'], s['longitude'], number(s['bikesAvailable'] || 0), number(s['freeRacks']),
                  { 'uid' => s['stationId'], 'ebikes' => number(s['ebikesAvailable'] || 0), 'number' => number(s['stationNumber']), 'online' => s['active'] })
        end
      end

      def update_clujbike
        JSON.parse(html_capture(request(p('feed_url')), /var stations = (\[.*?\]);/)).each do |s|
          station(s['StationName'], s['Latitude'], s['Longitude'], number(s['OcuppiedSpots']), number(s['EmptyDoors']),
                  { 'address' => s['Address'], 'status' => s['Status'] == 'Offline' ? 'offline' : 'online' })
        end
      end

      def update_cykleo
        json('https://portail.cykleo.fr/pu/stations/availability', params: { 'organization_id' => p('organization') },
                                                                   headers: { 'Referer' => 'https://portail.cykleo.fr/',
                                                                              'Content-Type' => 'application/json; charset=utf-8' }).each do |s|
          info = s['station']['assetStation']
          normal, electric = s.fetch('availableClassicBikeCount'), s.fetch('availableElectricBikeCount')
          station(info['commercialName'], info['coordinate']['y'], info['coordinate']['x'], normal + electric, s['availableDockCount'],
                  { 'uid' => s['id'], 'number' => info['commercialNumber'], 'ebikes' => electric, 'normal_bikes' => normal,
                    'online' => s['station']['status'] == 'IN_SERVICE', 'status' => s['station']['status'] })
        end
      end

      def update_easybike
        if spec['class'] == 'EasyBikeNew'
          data = json("https://#{p('city_uid')}.easybike.gr:8001/imet/v2/availability", headers: { 'Authorization' => 'Basic aW1ldDIwMTkwNTAxOkomZ2UjdXBQbUBNbT81aGI0eTZZ' })
          data.fetch('stations').each { |s| station(s['label'], s['lat'], s['lng'], number(s['available']), number(s['spaces']), { 'uid' => s['station_id'] }) }
        else
          stations = json("http://reseller.easybike.gr/#{p('city_uid')}/api.php").fetch('stations')
          raise ProviderError, 'Provider currently publishes no station feed' if stations.nil?

          stations.each do |s|
            station(s['description'], s['lat'], s['lng'], number(s['free_bikes']), number(s['free_spaces']), { 'slots' => number(s['total_spaces']) })
          end
        end
      end

      def update_open_source_bike_share
        json(p('feed_url')).each do |s|
          bikes = truthy?(s['bikecount']) ? s['bikecount'] : s.fetch('bikeCount')
          station(s['standName'], s['lat'] || s['latitude'], s['lon'] || s['longitude'], number(bikes), integer(s['slotcount']),
                  { 'uid' => number(s['standId']), 'photo' => s['standPhoto'], 'description' => s['standDescription'] })
        end
      end

      def update_smoove
        json(p('feed_url')).fetch('response').each do |s|
          station(s['name'], s['coordinates'][0], s['coordinates'][1], number(s['avl_bikes']), number(s['free_slots']), { 'uid' => s['nid'], 'slots' => number(s['total_slots']) })
        end
      end

      def update_veloway
        json(p('feed_url')).fetch('stand').each do |s|
          lat, lon = Float(s['lat']), Float(s['lng'])
          next if lat.zero? && lon.zero?

          # @type var extra: RubyBikes::object
          extra = { 'uid' => number(s['id']), 'slots' => number(s['tc']), 'slots_available' => number(s['ac']), 'online' => number(s['disp']) == 1 }
          extra['address'] = URI.decode_www_form_component(s['wcom'].to_s) if truthy?(s['wcom'])
          station(URI.decode_www_form_component(s['name'].to_s), lat, lon, number(s['ab']), number(s['ap']), extra)
        end
      end

      def update_wegoshare
        json("#{p('endpoint')}/cxf/am/station/map/search", method: 'POST', data: JSON.generate('isPublic' => true, 'limit' => -1),
                                                           headers: { 'Content-Type' => 'application/json; charset=utf-8' }).fetch('results').each do |s|
          next if s['stationStatus'] == 'PLANNED'

          station(s['name'], s['areaCentroid']['latitude'], s['areaCentroid']['longitude'], number(s['totalLockedCycleCount']), number(s['freeDocksCount']),
                  { 'uid' => s['id'], 'description' => s['description'], 'address' => s['address'], 'online' => s['stationStatus'] == 'OPEN',
                    'last_update' => s['lastUpdateCycleCountAt'],
                    'photo' => s.key?('photoId') ? "#{p('endpoint')}/cxf/fm/files/#{s['photoId']}" : nil })
        end
      end

      def update_yelovelo
        json('https://opendata.agglo-larochelle.fr/d4c/api/records/2.0/downloadfile/format=json&resource_id=1f124bea-d55f-457f-9eab-b7877d803435').each do |item|
          s = item.fetch('fields')
          station(s['station_nom'], s['station_latitude'], s['station_longitude'], number(s['velos_disponibles']), number(s['accroches_libres']),
                  { 'slots' => s['nombre_emplacements'] })
        end
      end

      def update_youbike
        taiwan = spec['class'] == 'YouBikeTw'
        data = taiwan ? json('https://apis.youbike.com.tw/json/station-yb2.json') : json(p('feed_url')).fetch('retVal')
        data.each do |s|
          next if taiwan && s['area_code'] != p('uid')
          next if s['lat'] == '' || s['lng'] == ''

          language = taiwan ? 'tw' : 'cn'
          # @type var extra: RubyBikes::object
          extra = { 'uid' => s['station_no'], 'district' => s["district_#{language}"], 'address' => s["address_#{language}"], 'slots' => s['parking_spaces'],
                    'last_updated' => s['updated_at'], 'online' => s['status'] == 1, 'youbike_version' => s['type'],
                    'en' => { 'name' => s['name_en'], 'district' => s['district_en'], 'address' => s['address_en'] } }
          if taiwan
            extra['normal_bikes'] = s['available_spaces_detail']['yb1'] + s['available_spaces_detail']['yb2']
            extra['ebikes'] = s['available_spaces_detail']['eyb']
          end
          station(s["name_#{language}"], s['lat'], s['lng'], number(s['available_spaces']), number(s['empty_spaces']), extra)
        end
      end
    end
  end
end
