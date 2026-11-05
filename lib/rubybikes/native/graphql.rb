# frozen_string_literal: true

# Adapted from PyBikes OTP, Charichari, Ganxeta and UrbanSharing; AGPL-3.0.
class RubyBikes
  module Native
    class JsonProviders
      def graphql(url, name, variables = {}, operation: nil)
        payload = { 'query' => File.read(File.join(Native::DATA, 'graphql', "#{name}.graphql")), 'variables' => variables }
        payload['operationName'] = operation if operation
        json(url, method: 'POST', headers: { 'Content-Type' => 'application/json; charset=utf-8' }, data: JSON.generate(payload)).fetch('data')
      end

      def update_charichari
        graphql('https://charichari.bike/api/graphql', 'charichari', { 'regionId' => p('region_id') }, operation: 'listPorts').fetch('ports').each do |s|
          station(s['title'], s['location']['latitude'], s['location']['longitude'], 0, number(s['capacity']), { 'uid' => s['id'], 'address' => s['address'] })
        end
      end

      def update_ganxeta
        graphql('https://bks-api.ganxeta.cat/rms-bike-sharing-real-time/graphql', 'ganxeta', {}, operation: 'StationsRealtime').fetch('get_data_real_time').each do |s|
          station(s['station_name'], s['latitude'], s['longitude'], number(s['bikes_available']), number(s['racks_available']),
                  { 'uid' => s['station_id'], 'address' => s['station_address'], 'slots' => number(s['racks_total']), 'number' => s['station_external_id'] })
        end
      end

      def update_otp
        data = graphql(p('feed_url'), 'otp')
        data.fetch('vehicleRentalStations').each do |s|
          # @type var extra: RubyBikes::object
          extra = { 'uid' => s['stationId'], 'online' => s['operative'] }
          extra['slots'] = s['capacity'] unless s['capacity'].nil?
          extra['rental_uris'] = s['rentalUris'] if truthy?(s['rentalUris'])
          s['availableVehicles']['byType'].each do |type|
            field = otp_type(type.fetch('vehicleType')).first
            extra[field] = extra.fetch(field, 0) + type.fetch('count') if field
          end
          free = s['availableSpaces']['total']
          station(s['name'], s['lat'], s['lon'], s['availableVehicles']['total'], free == 2_147_483_647 ? 32 : free, extra)
        end
        data.fetch('rentalVehicles').each do |s|
          # @type var extra: RubyBikes::object
          extra = { 'uid' => s['vehicleId'], 'online' => s['operative'] }
          extra['rental_uris'] = s['rentalUris'] if truthy?(s['rentalUris'])
          extra['battery'] = Float(s['fuel']['percent']) if truthy?(s['fuel']['percent'])
          vehicle(s['lat'], s['lon'], extra, otp_type(s.fetch('vehicleType')).last)
        end
      end

      def update_digitransit
        @parameters['feed_url'] ||= 'https://api.digitransit.fi/routing/v2/finland/gtfs/v1'
        @transport.headers['digitransit-subscription-key'] = @key
        update_otp
      end

      def otp_type(type)
        case [type['formFactor'], type['propulsionType']]
        when %w[BICYCLE HUMAN] then %w[normal_bikes bike]
        when %w[BICYCLE ELECTRIC_ASSIST] then %w[ebikes ebike]
        when %w[CARGO_BICYCLE HUMAN] then %w[cargo bike]
        when %w[CARGO_BICYCLE ELECTRIC_ASSIST] then %w[ecargo bike]
        else [nil, 'bike']
        end
      end

      def update_urbansharing
        params = { 'operationName' => 'DockGroups', 'variables' => JSON.generate('systemId' => tag),
                   'extensions' => JSON.generate('persistedQuery' => { 'version' => 1, 'sha256Hash' => '6afd0a33ab1a81d87dd31830e4e3f3da6f9e0881a9a07427b59bf1dec6fd692e' }) }
        json('https://core.urbansharing.com/public/api/v1/graphql', params: params).fetch('data').fetch('dockGroups').each do |s|
          station(s['title'], s['coord']['lat'], s['coord']['lng'], number(s['availabilityInfo']['availableVehicles']), number(s['availabilityInfo']['availableDocks']),
                  { 'uid' => s['id'], 'address' => s['subTitle'], 'online' => s['state'] == 'active' })
        end
      end

      def update_roovee
        data = json('https://api.roovee.eu/public/bikesAndZones', params: { 'tenant' => p('tenant') })
        data.fetch('zones').each do |s|
          next unless s['type'] == 'preferredBikeReturnZone'

          station(s['name'], s['areaCenter']['lat'], s['areaCenter']['lng'], 0, nil, { 'virtual' => true })
        end
        data.fetch('bikes').each do |s|
          vehicle(s['location']['lat'], s['location']['lng'], { 'uid' => s['bikeNumber'], 'online' => s['isAvailable'] }, s['type'] == 'Elektryczny' ? 'ebike' : 'bike')
        end
      end

      def update_bicing
        json("#{p('endpoint')}/get-stations").fetch('stations').each do |s|
          begin
            lat, lon = Float(s['latitude']), Float(s['longitude'])
          rescue ArgumentError, TypeError
            next
          end
          # @type var extra: RubyBikes::object
          extra = { 'uid' => number(s['id']), 'online' => s['status'] == 1 }
          extra['normal_bikes'] = number(s['mechanical_bikes']) if s.key?('mechanical_bikes')
          extra.merge!('has_ebikes' => true, 'ebikes' => number(s['electrical_bikes'])) if s.key?('electrical_bikes')
          station(s['streetName'], lat, lon, number(s['bikes']), number(s['slots']), extra)
        end
      end

      def update_velok
        json('https://api.tfl.lu/v1/BikePoint').fetch('features').each do |s|
          info = s.fetch('properties')
          next unless info.fetch('id').include?('velok')

          station(info['name'], s['geometry']['coordinates'][1], s['geometry']['coordinates'][0], info['available_bikes'] + info['available_ebikes'], info['available_docks'],
                  { 'uid' => info['id'].split(':').last, 'address' => info['address'], 'photo' => info['photo'], 'slots' => info['docks'], 'online' => info['open'],
                    'ebikes' => info['available_ebikes'] })
        end
      end

      def update_publibike
        cantons = Array(p('canton'))
        regions = JSON.parse(File.read(File.join(Native::DATA, 'geojson/ch_cantons.json'))).fetch('features').select { |f| f['geometry'] && cantons.include?(f['properties']['NAME']) }
        data = json('https://rest.publibike.ch/v1/public/all/stations')
        data.fetch('publibike').fetch('stations').each do |s|
          next unless regions.empty? || regions.any? { |f| Geometry.contains?(f, Float(s['latitude']), Float(s['longitude'])) }

          bikes = s.fetch('vehicles').size
          station(s['name'], s['latitude'], s['longitude'], bikes, s['capacity'] - bikes,
                  { 'uid' => s['id'], 'address' => s['address'], 'zip' => s['zip'], 'city' => s['city'], 'slots' => s['capacity'], 'ebikes' => s['vehicles'].count do |v|
                    v['type']['id'] == 2
                  end })
        end
        data.fetch('velospot').fetch('responseData').each do |s|
          next unless regions.empty? || regions.any? { |f| Geometry.contains?(f, Float(s['lat']), Float(s['lng'])) }

          station(s['station_name'], s['lat'], s['lng'], number(s['totalBike']), 0,
                  { 'uid' => s['station_id'], 'address' => s['station_address'], 'ebikes' => number(s['totalElectricalBike']),
                    'normal_bikes' => number(s['totalNonElectricalBike']) })
        end
      end
    end
  end
end
