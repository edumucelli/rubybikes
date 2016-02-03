# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired by Pybike's Adbc
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class AdcbBikeshare < BikeShareSystem
	attr_accessor :stations, :meta
	def initialize(schema_instance_parameters={})
		tag       = schema_instance_parameters.fetch('tag')
		meta      = schema_instance_parameters.fetch('meta')
		@feed_url  = schema_instance_parameters.fetch('feed_url')
		@meta     = meta.merge({'company' => 'Cyacle Bicycle Rental LLC'})
		super(tag, @meta)
	end
	def update(scraper = nil)
		unless scraper
			scraper = Scraper.new
		end
		# Each station is
        # {
        #     "id":3,
        #     "s":"Yas Marina",
        #     "n":"Yas Marina",
        #     "st":1,"b":false,
        #     "su":false,
        #     "m":false,
        #     "lu":1452259533032,
        #     "lc":1452260047004,
        #     "bk":true,
        #     "bl":true,
        #     "la":24.465793,
        #     "lo":54.60961,
        #     "da":6,
        #     "dx":0,
        #     "ba":4,
        #     "bx":0
        # }
		data = JSON.parse(scraper.request(@feed_url))
		stations = []
        data['stations'].each do |item|
            name = item['n']
            latitude = item['la'].to_f
            longitude = item['lo'].to_f
            bikes = item['ba'].to_i
            free = item['da'].to_i
            extra = {
                'status' => item['st'] == 1 ? 'online' : 'offline',
                'has_bike_keys' => item['bk'] && item['bl'],
                'uid' => item['id'].to_s
            }
            station = AdcbBikeshareStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
	end
end

class AdcbBikeshareStation < BikeShareStation
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
#     JSON.parse(File.read('./schemas/adcb.json'))['instances'].each do |instance|
#         adcb = AdcbBikeshare.new(instance)
#         puts adcb.meta
#         adcb.update
#         puts adcb.stations.length
#         adcb.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.extra}"
#         end
#     end
# end