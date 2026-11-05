# frozen_string_literal: true

# Adapted from PyBikes cyclopolis.py and keolis.py.
# Copyright (C) eskerda, Eduardo Mucelli Rezende Oliveira and contributors.
# Distributed under the AGPL-3.0 license; see LICENSE.

class RubyBikes
  module Native
    class JsonProviders
      def update_cyclopolis
        return update_cyclopolis_api if spec.fetch('class') == 'CyclopolisApi'

        body = request(p('feed_url'))
        coordinate_pattern = if p('mapstyle') == 'google'
                               /latLng:\[(-?\d+\.\d+).*?(-?\d+\.\d+)\]/m
                             else
                               /"lat":\s?"(-?\d+\.\d+).*?"lon":\s?"(-?\d+\.\d+)/m
                             end
        coordinates = body.scan(coordinate_pattern)
        descriptions = body.scan(%r{data"?:.*?<span.*?>(.*?)<\\?/span>}m).flatten
        coordinates.zip(descriptions).each do |(latitude, longitude), description|
          fields = description.gsub(%r{<\\?/?b>}, '').split(%r{<br.?/?>})
          # @type var extra: RubyBikes::object
          extra = {}
          if fields.size == 4
            name, raw_bikes, raw_free, status = fields
          else
            name, raw_bikes, raw_slots, raw_free, status = fields
            extra['slots'] = number(raw_slots.split(':').last)
          end
          bikes = cyclopolis_count(raw_bikes.split(': ').last)
          free = cyclopolis_count(raw_free.split(':').last)
          extra['closed'] = true if status == 'offline'
          station(name, latitude, longitude, bikes, free, extra)
        end
      end

      def update_cyclopolis_api
        json(p('feed_url')).each do |item|
          bikes = item.fetch('vehicle_types_available').sum { |type| type.fetch('count') }
          free = item.fetch('vehicle_docks_available').sum { |type| type.fetch('count') }
          renting, returning = item.values_at('is_renting', 'is_returning')
          extra = { 'uid' => item['id'], 'is_renting' => renting, 'is_returning' => returning,
                    'online' => truthy?(renting) ? renting : returning }
          coordinates = item.fetch('location').fetch('coordinates')
          station(item['name'], coordinates[1], coordinates[0], bikes, free, extra)
        end
      end

      def update_keolis
        case spec.fetch('class')
        when 'KeolisIlevia'
          url = "https://data.lillemetropole.fr/data/ogcapi/collections/#{p('dataset')}/items"
          json(url, params: { 'f' => 'json', 'limit' => -1 }).fetch('records').each do |fields|
            extra = { 'status' => fields['etat'], 'uid' => fields['@id'].to_s,
                      'city' => fields['commune'], 'address' => fields['adresse'],
                      'last_update' => fields['date_modification'],
                      'online' => fields['etat_connexion'] == 'CONNECTÉ',
                      'payment-terminal' => fields['type'] == 'AVEC TPE' }
            station(fields['nom'], fields['y'], fields['x'], number(fields['nb_velos_dispo']),
                    number(fields['nb_places_dispo']), extra)
          end
        when 'KeolisSTAR'
          @meta['source'] = @meta['source'].gsub('{dataset}', p('dataset').to_s) if @meta['source']
          data = json('https://data.explore.star.fr/api/records/1.0/search/',
                      params: { 'dataset' => p('dataset'), 'rows' => -1 })
          data.fetch('records').each do |record|
            fields = record.fetch('fields')
            extra = { 'slots' => fields['nombreemplacementsactuels'], 'status' => fields['etat'],
                      'uid' => fields['idstation'].to_s, 'last_update' => fields['lastupdate'],
                      'online' => fields['etat'] == 'En fonctionnement', 'payment-terminal' => true }
            coordinates = fields.fetch('coordonnees')
            station(fields['nom'], coordinates[0], coordinates[1], number(fields['nombrevelosdisponibles']),
                    number(fields['nombreemplacementsdisponibles']), extra)
          end
        when 'VCub'
          json(p('feed_url')).fetch('lists').each do |fields|
            ebikes = number(fields['nbElectricBikeAvailable'])
            manual_bikes = number(fields['nbBikeAvailable'])
            bikes, free = ebikes + manual_bikes, number(fields['nbPlaceAvailable'])
            extra = { 'uid' => fields['id'].to_s, 'last_update' => fields['updatedAt'],
                      'address' => fields['address'], 'city' => fields['city'],
                      'online' => fields['connexionState'] == 'CONNECTEE', 'slots' => bikes + free,
                      'ebikes' => ebikes, 'normal_bikes' => manual_bikes,
                      'has_ebikes' => fields.key?('nbElectricBikeAvailable') }
            station(fields['name'], fields['latitude'], fields['longitude'], bikes, free, extra)
          end
        else
          raise NoSystemFoundError, 'Unknown Keolis client'
        end
      end

      private

      def cyclopolis_count(value)
        number(value)
      rescue ArgumentError
        0
      end
    end
  end
end
