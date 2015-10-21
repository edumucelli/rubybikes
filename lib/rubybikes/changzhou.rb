# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class Changzhou < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('feed_url')
        @meta   = meta.merge({"company" => "Changzhou Wing Public Bicycle Systems Co., Ltd."})
        super(tag, meta)
    end

    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end
        stations = []
        html = scraper.request(@feed_url)
        # There is one station in one of the cities in which the
        # address has a double quote mark in the middle of the string.
        # This makes the JSON invalid, SHIT!
        # {
        #     "id": 75,
        #     "name": "益华百货",
        #     "lat": 22.510574,
        #     "lng": 113.385837,
        #     "capacity": 20,
        #     "availBike": 0,       |-------| => These damn things here!
        #     "address": "中山市银通街"中银大厦"公交站南侧"
        # }
        data = JSON.parse(html.gsub('var ibike = ','').gsub(/("address"\s*\:\s*".*?").*?(\})/, '\1\2'))
        data['station'].each do |station|
            latitude = station['lat']
            longitude = station['lng']
            # Some stations have '0' for latitude and longitude 
            unless latitude.zero? && longitude.zero?
                name = station['name']
                bikes = station['availBike']
                capacity = station['capacity']
                # Site's code uses the same subtraction to infer 'free' bike stands
                free = capacity - bikes
                extra = {'slots' => capacity}
                station = ChangzhouStation.new(name, latitude, longitude, bikes, free, extra)
                stations << station
            end
        end
        @stations = stations
    end
end
class ChangzhouStation < BikeShareStation
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

# instance = {
#             "tag" => "changzhou-zhongshan",
#             "meta" => {
#                 "latitude" => 22.529894,
#                 "longitude" => 113.399972,
#                 "city" => "Zhongshan",
#                 "name" => "Zhongshan Public Bike",
#                 "country" => "CN"
#             },
#             "feed_url" => "http://www.zhongshantong.net/zsbicycle/zsmap/ibikestation.asp"
#         }

# changzhou = Changzhou.new(instance)
# changzhou.update

# if __FILE__ == $0
#     JSON.parse(File.read('./schemas/changzhou.json'))['instances'].each do |instance|
#         changzhou = Changzhou.new(instance)
#         puts changzhou.meta
#         changzhou.update
#         puts changzhou.stations.length
#         changzhou.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
#         end
#     end
# end