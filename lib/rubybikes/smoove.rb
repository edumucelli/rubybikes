# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require_relative 'base'
require_relative 'utils'

# Each station is formatted as:
# newmark_01(28, 45.770958,3.073871, "<div class=\"mapbal\" align=\"left\">022 Jaurès<br>Vélos disponibles: 4<br>Emplacements libres: 10<br>CB: Non<br></div>");
# I.e., (station_id, latitude, longitude, name, available_bikes, free_bike_stands, credit_card_enabled (discarded afterwards))
DATA_RGX = /\(\d+\,\ (\d+.\d+).*?(\d+.\d+)\,\ "<div.*?>(.*?)<br>.*?:(.*?)<br>.*?:(.*?)<br>.*?:(.*?)<br><\/div>"\)/

class Smoove < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag         = schema_instance_parameters.fetch('tag')
        meta        = schema_instance_parameters.fetch('meta')
        @feed_url   = schema_instance_parameters.fetch('feed_url')
        @meta       = meta.merge(meta = {'label' => 'Smoove', 'company' => 'Smoove'})
        super(tag, @meta)
    end
    def update
        scraper = Scraper.new()
        html = scraper.request(@feed_url)
        stations_data = html.scan(DATA_RGX)

        @stations = stations_data.map do |station_data|
            # discards the last element of stations_data
            # which indicates if the station is credit card-enabled
            latitude, longitude, name, bikes, free = station_data[0...-1]
            SmooveStation.new(name, latitude.to_f, longitude.to_f, bikes.to_i, free.to_i)
        end
    end
end

class SmooveStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, free)
        super()
        @name      = name
        @latitude  = latitude
        @longitude = longitude
        @bikes     = bikes
        @free      = free
    end
end

if __FILE__ == $0
    require 'json'
    JSON.parse(File.read('./schemas/smoove.json'))['instances'].each do |instance|
        smoove = Smoove.new(instance)
        smoove.update
        puts smoove.stations.length
        smoove.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
        end
    end
end