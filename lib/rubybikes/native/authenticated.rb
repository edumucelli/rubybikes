# frozen_string_literal: true

# Adapted from PyBikes authenticated clients; AGPL-3.0, original attribution in NOTICE.
class RubyBikes
  module Native
    class JsonProviders
      def update_bicimad
        url = 'https://openapi.emtmadrid.es/v2/transport/bicimad/stations/'
        raw = request(url)
        if @transport.last_response.status == 401
          auth = json('https://openapi.emtmadrid.es/v2/mobilitylabs/user/login/', headers: { 'passkey' => @key.fetch('passkey'), 'x-clientid' => @key.fetch('clientid') })
          @transport.headers['accesstoken'] = auth.fetch('data').first.fetch('accessToken')
          raw = request(url, skip_cache: true)
        end
        JSON.parse(raw).fetch('data').each do |s|
          online = s['activate'] == 1 && s['no_available'] == 0 # rubocop:disable Style/NumericPredicate -- JSON fields may contain non-numeric values.
          station(s['name'], s['geometry']['coordinates'][1], s['geometry']['coordinates'][0], number(s['dock_bikes']), number(s['free_bases']),
                  { 'number' => s['number'], 'uid' => s['id'], 'address' => s['address'], 'online' => online,
                    'slots' => number(s['total_bases']), 'light' => %w[green red yellow gray].fetch(number(s['light'])) })
        end
      end

      def update_bikeshare_ie
        headers = {
          'Authorization' => "Basic #{@key}",
          'User-Agent' => 'Dalvik/2.1.0 (Linux; U; Android 11; ROCINANTE FIRE Build/9001'
        }
        json('https://apps.bikeshare.ie/rbs/resources/appapi/station/data/list',
             method: 'POST', data: { 'schemeId' => p('system_id').to_s }, headers: headers).fetch('data').each do |s|
          station(s['name'], s['latitude'], s['longitude'], number(s['bikesAvailable']), number(s['docksAvailable']),
                  { 'uid' => s['stationId'], 'slots' => number(s['docksCount']), 'name_ie' => s['nameIrish'] })
        end
      end

      def update_weelo
        @transport.headers['User-Agent'] = 'okhttp/4.9.1'
        Array(p('city_ids')).each do |city|
          url = 'https://api.weelo.it/resources/stations'
          params = { 'idCity' => city, 'serviceType' => 1 }
          raw = request(url, params: params)
          if @transport.last_response.status == 401
            token = json('https://api.weelo.it/connect/token', method: 'POST', data: @key.merge('grant_type' => 'client_credentials')).fetch('access_token')
            @transport.headers['Authorization'] = "Bearer #{token}"
            raw = request(url, params: params, skip_cache: true)
          end
          JSON.parse(raw).each do |s|
            normal, electric = s.fetch('countMuscularBikesAvailable'), s.fetch('countAssistedBikesAvailable')
            station(s['name'], s['latitude'], s['longitude'], normal + electric, s['countFreePlacesAvailable'],
                    { 'uid' => s['idStation'], 'address' => s['address'], 'has_ebikes' => true, 'ebikes' => electric,
                      'normal_bikes' => normal, 'status' => s['state'], 'slots' => s['totalPlaces'] })
          end
        end
      end

      def update_nubija
        json('https://ar.nubija.com:55789/v1/station/list/user', headers: { 'app-token' => @key[8...-8], 'User-Agent' => 'okhttp/3.14.9' }).fetch('station').each do |s|
          next unless s['area'] == p('area')

          station(s['station_cd'], s['x_pos'], s['y_pos'], 0, number(s['parking_count']),
                  { 'uid' => s['id'], 'number' => number(s['tmno']), 'address' => s['address'] })
        end
      end

      def update_bicicard
        headers = { 'User-Agent' => 'Dalvik/2.1.0 (Linux; U; Android 11; ROCINANTE FIRE Build/9001', 'DeviceModel' => 'ROCINANTE FIRE' }
        cert = lower_keys(json("#{p('endpoint')}/api/certificado", headers: headers))
        headers['Thumbprint'] = cert.fetch('thumbprint')
        lower_keys(json("#{p('endpoint')}/apiapp/SBancada/Estado/TodosSimple", headers: headers, skip_cache: true)).each do |s|
          normal, electric = s.fetch('numerobicicletasnormales'), s.fetch('numerobicicletaselectricas')
          station(s['nombre'], s['latitud'], s['longitud'], normal + electric, s['numerocandadoslibres'],
                  { 'uid' => s['id'], 'normal_bikes' => normal, 'ebikes' => electric, 'slots' => s['numerocandados'], 'online' => s['ispuestoonline'] })
        end
      end

      def update_ov_fiets
        params = { 'minLat' => 50.2876, 'minLng' => 2.7109, 'maxLat' => 53.8857, 'maxLng' => 7.9541, 'zoomLevel' => 9, 'limit' => 500,
                   'filterTypes' => ['OV_FIETS'], 'appVersionCapabilities' => %w[DLF-Tier DLS-Check DLA-GreenWheels], 'enableSubfilters' => true }
        json('https://gateway.apiportal.ns.nl/places-api/v2/nearbyme', params: params,
                                                                       headers: { 'X-MmVehicleExtra' => 'false',
                                                                                  'Ocp-Apim-Subscription-Key' => @key }).fetch('locations').each do |s|
          bikes = s['description']['subDescription'][/\d+/].to_i
          station(s['description']['full'], s['lat'], s['lng'], bikes, nil, { 'uid' => s['id']['value'][/.*-(\w+)\s*$/, 1] })
        end
      end

      def lower_keys(value)
        case value
        when Hash then value.to_h { |key, item| [key.downcase, lower_keys(item)] }
        when Array then value.map { |item| lower_keys(item) }
        else value
        end
      end
    end
  end
end
