# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

REGEX = /setConfig\('StationsData',(\[.*\])\);/


class Bikeu < BikeShareSystem
    
    attr_accessor :stations, :meta

    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('url')
        @meta     = meta.merge({'company' => 'Bike U Sp. z o.o.'})
        super(tag, @meta)
    end

    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end

        stations = []
        html = scraper.request(@feed_url)
        data = html.scan(REGEX)[0][0]

        markers = JSON.parse(data)
        markers.each do |marker|
            name       = marker['Name']
            latitude   = marker['Latitude']
            longitude  = marker['Longitude']
            bikes      = marker['TotalAvailableBikes']
            free       = marker['TotalLocks'] - bikes
            station = BikeuStation.new(name, latitude, longitude, bikes, free)
            stations << station
        end

        @stations = stations
    end 
end

class BikeuStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, free)
        super()
        @name = name
        @latitude = latitude
        @longitude = longitude
        @bikes = bikes
        @free = free
    end
end

# if __FILE__ == $0
#     schema_instance_parameters = {
#         "tag" => "bbbike",
#         "url" => "https://www.bbbike.eu/LocationsMap.aspx",
#         "meta" => {
#             "latitude" => 49.8225,
#             "city" => "Bielsko-Biała",
#             "name" =>  "BBBike",
#             "longitude" => 19.044444,
#             "country" => "PL"
#         }
#     }

#     bikeu = Bikeu.new(schema_instance_parameters)
#     bikeu.update
#     puts bikeu.stations.length
#     bikeu.stations.each do |station|
#         puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
#     end
# end