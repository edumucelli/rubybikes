# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on Pybikes' Movete.py
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class Movete < BikeShareSystem
	attr_accessor :stations, :meta

	STATIONS_RGX = /var paradas\s*=\s*(\[.*?\]);/m
	ATTRIBUTES_RGX = /\[(.*?)\]/

	def initialize(schema_instance_parameters={})
		tag       = schema_instance_parameters.fetch('tag')
		meta      = schema_instance_parameters.fetch('meta')
		@meta     = meta.merge({'company' => 'Sistema de Bicicletas Públicas del Valle de Aburrá'})
		@feed_url = 'http://movete.montevideo.gub.uy/index.php?option=com_content&view=article&id=1&Itemid=2'
		super(tag, @meta)
	end

	def update(scraper = nil)
		unless scraper
			scraper = Scraper.new
		end
		stations =[]
		data = scraper.request(@feed_url)
		# https://www.ruby-forum.com/topic/3657492
		raw_stations = data.match(STATIONS_RGX).captures
		raw_stations.first.scan(ATTRIBUTES_RGX).each do |raw_station|
			fields = raw_station.first.split(',')
			# Skip office marker
			unless fields[4].to_i == -1
				name = fields[0]
	            latitude = fields[1].to_f
	            longitude = fields[2].to_f
	            bikes = fields[6].to_i
	            slots = fields[7].to_i
	            free = slots - bikes
	            extra = {
	                'slots' => slots,
	                'uid' => fields[3]
	            }
	            station = MoveteStation.new(name, latitude, longitude, bikes, free, extra)
	            stations << station
			end
		end
		@stations = stations
	end
end

class MoveteStation < BikeShareStation
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
#     JSON.parse(File.read('./schemas/movete.json'))['instances'].each do |instance|
#         movete = Movete.new(instance)
#         puts movete.meta
#         movete.update
#         puts movete.stations.length
#         movete.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
#         end
#     end
# end