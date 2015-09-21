# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the GPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class Cleanap < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url  = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'company' => 'CleaNap'})
        super(tag, @meta)
    end
    def update
        scraper = Scraper.new
        data = JSON.parse(scraper.request(@feed_url))
        stations = []
         # {"status"=>1,
         # "response_data"=>[
         #    {"station_id"=>129,
         #    "address"=>"Via Melisurgo",
         #    "latitude"=>40.840543790048,
         #    "longitude"=>14.2546322155,
         #    "postalCode"=>80133,
         #    "title"=>"CleaNap demo LumiLab",
         #    "description"=>"#11",
         #    "image_url"=>"img_129.jpg",
         #    "status"=>1,
         #    "available_locks"=>0,
         #    "available_bikes"=>2,
         #    "capacity"=>2}, ...]
        data['response_data'].each do |info|
            name = info['title']
            latitude = info['latitude']
            longitude = info['longitude']
            bikes = info['available_bikes']
            free = info['available_locks']
            extra = {
                'address' => info['address'],
                'online' => info['status'] == 1,
                'slots' => info['capacity']
            }
            station = CleanapStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
    end
end

class CleanapStation < BikeShareStation
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
#     instance = {
#     "tag" => "bike-sharing-napoli",
#     "meta" => {
#         "latitude" => 40.8517746,
#         "country" => "IT",
#         "name" => "Bike Sharing Napoli",
#         "longitude" => 14.2681244,
#         "city" => "Napoli"
#     },
#     "feed_url" => "http://www.movinap.it/_CI/api_v1/station/getAllStationsInfo"
#     }
#     cleanap = Cleanap.new(instance)
#     cleanap.update
#     puts cleanap.stations.length
#     cleanap.stations.each do |station|
#         puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}, #{station.extra}"
#     end
# end