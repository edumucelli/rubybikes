# frozen_string_literal: true

# Native ports of PyBikes clients, Copyright eskerda, Martín González Gómez,
# Eduardo Mucelli Rezende Oliveira and contributors. Distributed under AGPL-3.0.
class RubyBikes
  module Native
    class JsonProviders < Provider
      def update
        send("update_#{spec.fetch('module')}")
      end

      def update_encicla
        json('https://webapp.metropol.gov.co/wsencicla/api/Disponibilidad/GetDisponibilidadMapas').each do |s|
          next unless number(s.fetch('cdo')).zero?

          station(s['name'], s['lat'], s['lon'], s['bikes'], s['capacity'] - s['bikes'],
                  { 'uid' => s['id'], 'slots' => s['capacity'], 'address' => s['address'].to_s.strip,
                    'description' => s['description'], 'online' => s['closed'] == '0' })
        end
      end

      def update_fifteen
        data = json(p('feed_url'))
        if data.is_a?(Hash)
          raise ProviderError, 'Provider returned unsuccessful status' unless data['statusCode'] == 200

          data = data.fetch('data').fetch('stations')
        end
        data.each do |s|
          station(s['label'], s['coordinates'][1], s['coordinates'][0], number(s['availableBikes']), number(s['availableSlots']),
                  { 'uid' => s['id'], 'online' => !s['isClosed'] })
        end
      end

      def update_gira
        json(p('feed_url')).fetch('features').each do |s|
          info = s.fetch('properties')
          bikes = number(info['num_bicicletas'])
          station(info['desig_comercial'], s['geometry']['coordinates'][0][1], s['geometry']['coordinates'][0][0], bikes, number(info['num_docas']) - bikes,
                  { 'uid' => info['id_expl'], 'slots' => info['num_docas'], 'status' => info['estado'], 'online' => info['estado'] == 'active' })
        end
      end

      def update_joco
        json(p('feed_url')).each do |s|
          bikes = number(s['slots']['withAvailableVehicle'])
          station(s['name'], s['info']['position']['coordinates'][1], s['info']['position']['coordinates'][0], bikes, number(s['slots']['free']),
                  { 'uid' => s['id'], 'has_ebikes' => true, 'ebikes' => bikes, 'address' => s['info']['address'], 'slots' => number(s['slots']['total']),
                    'online' => s['state'] == 'OPEN' })
        end
      end

      def update_kolumbus
        json('https://kolumbus-sanntidsskjerm-backend-prod.azurewebsites.net/entur/city-bikes').each do |s|
          bikes, slots = number(s['available']), number(s['capacity'])
          station(s['name'], s['latitude'], s['longitude'], bikes, [slots - bikes, 0].max,
                  { 'has_ebikes' => true, 'slots' => slots, 'uid' => s['id'], 'number' => s['id'][/Station:(\d+)$/, 1]&.to_i })
        end
      end

      def update_linkbike
        @parameters['bbox'] = JSON.parse(File.read(File.join(Native::DATA, 'geojson/penang.json')))
        json('https://www.linkbike.my/linkbike_api/api_update_stationinfo.php').each do |s|
          bikes, slots = number(s['availbike']), number(s['capacity'])
          station(s['name'], s['lat'], s['lng'], bikes, slots - bikes, { 'uid' => s['StId'], 'slots' => slots })
        end
      end

      def update_openmove
        json('https://otp.opendatahub.com/otp/routers/openmove/bike_rental').fetch('stations').each do |s|
          next if s['isFloatingBike'] || !s['networks'].include?(p('network'))

          station(s['name'], s['y'], s['x'], number(s['bikesAvailable']), number(s['spacesAvailable']),
                  { 'uid' => s['id'].delete('"'), 'last_update' => s['lastReportedEpochSeconds'], 'online' => s['realTimeData'] })
        end
      end

      def update_qrobici
        json('https://qrobici.mx/mobile/getStations').fetch('estaciones').each do |s|
          station(s['T_NOMBRE'], s['T_LATITUD'], s['T_LONGITUD'], number(s['BICICLETAS_DISPONIBLES']), number(s['ESPACIOS_DISPONIBLES']),
                  { 'uid' => s['id'], 'address' => s['T_REFERENCIA'], 'slots' => s['E_NO_SLOTS'], 'status' => s['ESTATUS'], 'online' => s['ESTATUS'] == 'En línea',
                    'last_update' => s['FH_FECHA_ULTIMA_CONEXION'] })
        end
      end

      def update_sejong
        json(p('feed_url')).fetch('data').fetch('sbike_station').each do |s|
          station(s['station_name'], s['y_pos'], s['x_pos'], number(s['bike_parking']), nil, { 'uid' => s['station_id'], 'address' => s['addr'] })
        end
      end

      def update_seoulbike
        json(p('feed_url'), method: 'POST', data: { 'stationGrpSeq' => 'ALL' }).fetch('realtimeList').each do |s|
          kids, slots = number(s['parkingELECBikeCnt']), number(s['rackTotCnt'])
          bikes = number(s['parkingQRBikeCnt']) + kids
          station(s['stationName'], s['stationLatitude'], s['stationLongitude'], bikes, [slots - bikes, 0].max,
                  { 'kid_bikes' => kids, 'slots' => slots, 'uid' => s['stationId'] })
        end
      end

      def update_slovnaft_bajk
        json('https://gate.slovnaftbajk.sk/AppGate2.php', method: 'POST', data: JSON.generate('Cmd' => 'GetAllStationInfo', 'Area' => 'BA')).fetch('Info').each do |s|
          next unless s['test_station'] == '0'

          station(s['Name'], s['GpsLat'], s['GpsLon'], number(s['BikeNum']), number(s['DockNum']),
                  { 'uid' => s['Station'], 'ebikes' => number(s['eBikeNum']), 'online' => s['active'] == '1' })
        end
      end

      def update_smartbike
        information = json("#{p('endpoint')}/station_list.json")
        statuses = json("#{p('endpoint')}/station_status_list.json").to_h { |s| [s.fetch('id'), s] }
        information.each do |s|
          status = statuses.fetch(s.fetch('id'))
          station(s['name'], s['location']['lat'], s['location']['lon'], number(status['availability']['bikes']), number(status['availability']['slots']),
                  { 'status' => status['status'], 'uid' => number(s['id']), 'address' => s['address'] })
        end
      end

      def update_soltrafego
        json("https://bikesharing.soltrafego.pt/index.php/adminapi/dashboard_data/#{p('uid')}").fetch('stations').each do |s|
          station(s['name'], s['lat'], s['lon'], number(s['online_docked']), number(s['online_free']),
                  { 'uid' => s['id'], 'address' => s['address'], 'last_update' => s['updated_on'], 'slots' => s['docks'].size, 'online' => s['active'] == '1' })
        end
      end

      def update_tashu
        raw = request(p('endpoint'))
        JSON.parse(html_capture(raw, /var station_json = JSON.parse\('(.*)'\);/)).each do |s|
          station(s['name'], s['x_pos'], s['y_pos'], number(s['parking_count']), nil, { 'uid' => s['id'], 'address' => s['address'] })
        end
      end

      def update_batumvelo
        json('https://batumvelo.ge/api/client/public/parking', headers: { 'Accept' => 'application/json' }).each do |s|
          station(s['name'], s['lat'], s['lng'], 0, 0, { 'online' => s['type'] == 'ALLOW' })
        end
        json('https://batumvelo.ge/api/client/public/available', headers: { 'Accept' => 'application/json' }).each do |s|
          vehicle(s['lat'], s['lng'])
        end
      end

      def update_aksu
        raw = request(p('endpoint'))
        JSON.parse(html_capture(raw, /var ibike = (.*)/)).fetch('station').each do |s|
          bikes, slots = number(s['availBike']), number(s['capacity'])
          station(s['name'], s['lat'], s['lng'], bikes, slots - bikes, { 'uid' => s['id'], 'address' => s['address'], 'slots' => slots })
        end
      end

      def update_bicicas
        json('https://ws2.bicicas.es/bench_status_map').fetch('features').each do |s|
          info = s.fetch('properties')
          anchors = info.fetch('anchors')
          free = anchors.count { |a| a['bicycle'].nil? && a.fetch('incidents').empty? }
          ebikes = anchors.count { |a| truthy?(a['is_electric']) }
          station(info['name'], s['geometry']['coordinates'][1], s['geometry']['coordinates'][0], info['bikes_available'], free,
                  { 'has_ebikes' => ebikes.positive?, 'ebikes' => ebikes, 'slots' => anchors.size, 'last_seen' => info['last_seen'],
                    'number_loans' => number(info['number_loans']), 'incidents' => info['incidents'], 'online' => info['online'] })
        end
      end

      def update_lastenvelo
        # @type var rows: untyped
        rows = CSV.parse(request(p('feed_url')), headers: true)
        rows.each do |row|
          _utc, human, uid, lat, lon, status, _returned, name, subname, info, booking = row.fields
          station([name, subname].reject { |v| v.nil? || v.empty? }.join(' - '), lat, lon, status == 'available' ? 1 : 0, nil,
                  { 'uid' => uid, 'status' => status, 'rental_uris' => { 'web' => booking }, 'last_updated' => human, 'bike_type' => info })
        end
      end
    end
  end
end
