# frozen_string_literal: true

# Adapted from PyBikes nextbike.py, Copyright eskerda and contributors, AGPL-3.0.
class RubyBikes
  module Native
    class Nextbike < Provider
      def initialize(spec, parameters, key: nil)
        super
        @parameters.fetch('domain')
      end

      def update
        url = "https://#{p('hostname', 'maps.nextbike.net')}/maps/nextbike-live.xml"
        document = Nokogiri::XML(request(url, params: { 'domains' => p('domain') })) { |config| config.strict.nonet }
        places = document.xpath('/markers/country//city//place')
        places = places.select { |place| place.ancestors('city').first['uid'] == p('city_uid').to_s } if p('city_uid')
        raise ProviderError, 'Provider returned no places for this network' if places.empty?

        places.each do |place|
          latitude, longitude = Float(place['lat']), Float(place['lng'])
          next if p('bbox') && !Geometry.contains?(p('bbox'), latitude, longitude)

          if place['spot'] == '1'
            extra = { 'uid' => place['uid'], 'virtual' => place['place_type'] == '17' }
            extra['number'] = place['number'] if place['number']
            bike_types = place['bike_types']
            counts = if bike_types && !bike_types.strip.empty?
                       JSON.parse(bike_types).values
                     else
                       [place['bikes']]
                     end
            extra['bikes_approximate'] = true if counts.any? { |count| count.to_s.end_with?('+') }
            bikes = counts.sum { |count| number(count.to_s.delete_suffix('+')) }
            free = nil
            if place['bike_racks']
              extra['slots'] = number(place['bike_racks'])
              free = place['free_racks'] ? number(place['free_racks']) : extra['slots'] - bikes
            end
            extra['bike_uids'] = place['bike_numbers'].split(',').reject(&:empty?) if place['bike_numbers']
            station(place['name'], latitude, longitude, bikes, free, extra)
          end
          if place['bike'] == '1'
            bike = place.at_xpath('./bike')
            vehicle(latitude, longitude, { 'uid' => bike['number'], 'online' => bike['active'] == '1' })
          end
        end
      end
    end
  end
end
