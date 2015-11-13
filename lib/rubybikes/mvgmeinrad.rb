# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired by the Pybikes' Mvgmeinrad.py
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class Mvgmeinrad < BikeShareSystem
	attr_accessor :stations, :meta
	def initialize(schema_instance_parameters={})
		tag       = schema_instance_parameters.fetch('tag')
		meta      = schema_instance_parameters.fetch('meta')
		@feed_url  = schema_instance_parameters.fetch('feed_url')
		@meta     = meta.merge({'company' => 'Mainzer Verkehrsgesellschaft mbH (MVG)'})
		super(tag, @meta)
	end
	def update(scraper = nil)
		unless scraper
			scraper = Scraper.new
		end
		data = JSON.parse(scraper.request(@feed_url))
		stations = []
		data.each do |station|
			name = station['name']
            latitude = station['latitude']
            longitude = station['longitude']
            bikes = station['bikes_available']
            free = station['docks_available']
            extra = {
                'slots' => station['capacity'],
                'address'  => station['address']
            }
			station = MvgmeinradStation.new(name, latitude, longitude, bikes, free, extra)
			stations << station
		end
		@stations = stations
	end
end

class MvgmeinradStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, free, extra)
        super()
        @name      = name
        @latitude  = latitude
        @longitude = longitude
        @bikes     = bikes
        @free      = free
        @extra     = extra
    end
end

# if __FILE__ == $0
#     require 'json'
#     JSON.parse(File.read('./schemas/mvgmeinrad.json'))['instances'].each do |instance|
#         mvgmeinrad = Mvgmeinrad.new(instance)
#         puts mvgmeinrad.meta
#         mvgmeinrad.update
#         puts mvgmeinrad.stations.length
#         mvgmeinrad.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}, #{station.extra}"
#         end
#     end
# end