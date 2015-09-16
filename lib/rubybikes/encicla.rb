# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class Encicla < BikeShareSystem
	attr_accessor :stations, :meta
	# schema_instance_parameters is the 'instance' hash from encicla.json, e.g.:
	# {
	#  "tag"=>"encicla",
	#  "meta"=>{"latitude"=>6.254942, "longitude"=>-75.567982, "city"=>"Medellin", "name"=>"EnCicla", "country"=>"CO"},
	#  "feed_url"=>"http://encicla.gov.co/status"
	# }
	def initialize(schema_instance_parameters={})
		tag       = schema_instance_parameters.fetch('tag')
		meta      = schema_instance_parameters.fetch('meta')
		@feed_url  = schema_instance_parameters.fetch('feed_url')
		@meta     = meta.merge({'company' => 'Sistema de Bicicletas Públicas del Valle de Aburrá'})
		super(tag, @meta)
	end
	def update
		scraper = Scraper.new()
		data = JSON.parse(scraper.request(@feed_url))
		stations = []
		data['stations'].each do |station|
			station['items'].each do |item|
				# discard 'Centro de Operaciones' (Operation Center) from the set of stations
				if item['cdo'].to_i != 0
					next
				end
				station = EnciclaStation.new(item)
				stations << station
		  	end
		end
		@stations = stations
	end
end

class EnciclaStation < BikeShareStation
	def initialize(item)
		super
		# {
		# "order": 0,
		# "name": "Moravia",
		# "address": "CALLE 82A # 52-29",
		# "description": "Frente a la entrada principal del Centro de Desarrollo Cultural de Moravia",
		# "lat": "6.276585",
		# "lon": "-75.564804",
		# "type": "manual",
		# "capacity": 15,
		# "bikes": 8,
		# "places": null,
		# "picture": "http:\/\/encicla.gov.co\/wp-content\/uploads\/estaciones-360-moravia.jpg",
		# "bikes_state": 0,
		# "places_state": "danger",
		# "closed": 0,
		# "cdo": 0
		# }
		@name      = item['name']
		@longitude = item['lon'].to_f
		@latitude  = item['lat'].to_f
		@bikes     = item['bikes'].to_i
		places     = item['places']
		unless places
			@free = 0
		else
			@free  = places.to_i
		end
		# 'capacity' is often incorrect, even smaller than the number of bikes
		# therefore it was not included on the 'slots' field
		@extra = {
			'address'     => item['address'],
		  	'description' => item['description'],
		  	'type'        => item['type'],
		  	'picture'     => item['picture'],
		  	'closed'      => !item['closed'].zero?
		}
  	end
end

if __FILE__ == $0
    require 'json'
    JSON.parse(File.read('./schemas/encicla.json'))['instances'].each do |instance|
        encicla = Encicla.new(instance)
        puts encicla.meta
        encicla.update
        puts encicla.stations.length
        encicla.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
        end
    end
end