# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired by Pybike's Labici
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class LaBici < BikeShareSystem

	BASE_URL = "http://labici.net/api-labici.php?module=parking&method=get-locations&city=%{city_code}"

	attr_accessor :stations, :meta
	def initialize(schema_instance_parameters={})
		tag       = schema_instance_parameters.fetch('tag')
		meta      = schema_instance_parameters.fetch('meta')
		city_code = schema_instance_parameters.fetch('city_code')
		@meta     = meta.merge({'company' => 'Labici Bicicletas Públicas SL'})
		super(tag, @meta)
		@feed_url = BASE_URL % {:city_code => city_code}
	end
	def update(scraper = nil)
		unless scraper
			scraper = Scraper.new
		end
		data = JSON.parse(scraper.request(@feed_url))
		stations = []
		data['data'].each do |item|
            name = item['descripcion']
            latitude = item['latitude'].to_f
            longitude = item['longitude'].to_f
            bikes = item['xocupados'].to_i
            free = item['libres'].to_i
            extra = {
                'slots' => item['num_puestos'],
                'uid' => item['id_aparcamiento'],
            }
            station = LaBiciStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
	end
end

class LaBiciStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, free, extra)
        super()
        @name = name
        @latitude = latitude
        @longitude = longitude
        @bikes = bikes
        @free = free
        @extra = extra
    end
end

# if __FILE__ == $0
#     require 'json'
#     JSON.parse(File.read('./schemas/labici.json'))['instances'].each do |instance|
#         labici = LaBici.new(instance)
#         puts labici.meta
#         labici.update
#         puts labici.stations.length
#         labici.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.extra}"
#         end
#     end
# end