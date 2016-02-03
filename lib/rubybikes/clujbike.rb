# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired by Pybike's Clujbike
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class Clujbike < BikeShareSystem
	attr_accessor :stations, :meta
	def initialize(schema_instance_parameters={})
		tag       = schema_instance_parameters.fetch('tag')
		meta      = schema_instance_parameters.fetch('meta')
		@feed_url  = schema_instance_parameters.fetch('feed_url')
		@meta     = meta.merge({'company' => 'Municipiul Cluj-Napoca'})
		super(tag, @meta)
	end
	def update(scraper = nil)
		unless scraper
			scraper = Scraper.new
		end
		post_data = {
            'sort' => '',
            'group' => '',
            'filter' => '',
            'StationName' => '',
            'Address' => '',
            'OcuppiedSpots' => '0',
            'EmptySpots' => '0',
            'MaximumNumberOfBikes' => '0',
            'LastSyncDate' => '',
            'IdStatus' => '0',
            'Status' => '',
            'StatusType' => '',
            'Latitude' => '0',
            'Longitude' => '0',
            'IsValid' => 'true',
            'CustomIsValid' => 'false',
            'Id' => '0',
        }
        data = JSON.parse(scraper.request(@feed_url, 'POST', post_data))
        stations = []
        data['Data'].each do |item|
            name = item['StationName']
            latitude = item['Latitude'].to_f
            longitude = item['Longitude'].to_f

            if latitude == 0.0 || longitude == 0.0
                next
            end

            bikes = item['OcuppiedSpots'].to_i
            free = item['EmptySpots'].to_i
            extra = {
                'slots' => item['MaximumNumberOfBikes'],
                'address' => item['Address'],
                'status' => item['StatusType'] == 'Offline' ? 'offline' : 'online'
            }
            station = ClujbikeStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
	end
end

class ClujbikeStation < BikeShareStation
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
#     JSON.parse(File.read('./schemas/clujbike.json'))['instances'].each do |instance|
#         clujbike = Clujbike.new(instance)
#         puts clujbike.meta
#         clujbike.update
#         puts clujbike.stations.length
#         clujbike.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.extra}"
#         end
#     end
# end