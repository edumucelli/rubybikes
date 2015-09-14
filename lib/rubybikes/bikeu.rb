# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

REGEX = /var stationsData = (\[.*\]);/

class Bikeu < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url  = schema_instance_parameters.fetch('url')
        @meta     = meta.merge({'company' => 'Bike U Sp. z o.o.'})
        super(tag, @meta)
    end
    def update
        stations = []
        scraper = Scraper.new()
        html = scraper.request(@feed_url)
        data = JSON.parse(html.scan(REGEX)[0][0])
        data.each do |marker|
            station = BikeuStation.new(marker)
            stations << station
        end
        @stations = stations
    end 
end
class BikeuStation < BikeShareStation
    def initialize(info)
        super
        @latitude   = info['Latitude']
        @longitude  = info['Longitude']
        @name       = info['Name']
        @bikes      = info['TotalAvailableBikes']
        @free       = info['TotalLocks'] - @bikes
    end
end

if __FILE__ == $0
    schema_instance_parameters = {
        "tag" => "bbbike",
        "url" => "https://www.bbbike.eu/LocationsMap.aspx",
        "meta" => {
            "latitude" => 49.8225,
            "city" => "Bielsko-Biała",
            "name" =>  "BBBike",
            "longitude" => 19.044444,
            "country" => "PL"
        }
    }

    bikeu = Bikeu.new(schema_instance_parameters)
    bikeu.update
    puts bikeu.stations.length
    bikeu.stations.each do |station|
        puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
    end
end