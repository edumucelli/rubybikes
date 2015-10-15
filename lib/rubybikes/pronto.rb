# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class Pronto < BikeShareSystem
    attr_accessor :stations, :meta

    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url  = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'company' => ["Pronto!", "Alta Bicycle Share, Inc"]})
        super(tag, @meta)
    end

    def update
        stations = []
        scraper = Scraper.new()
        data = JSON.parse(scraper.request(@feed_url))
        # Each station is
        # {
        #     "id":1,
        #     "s":"3rd Ave & Broad St",
        #     "n":"BT-01",
        #     "st":1,
        #     "b":false,
        #     "su":false,
        #     "m":false,
        #     "lu":1444910420300,
        #     "lc":1444910706468,
        #     "bk":true,
        #     "bl":true,
        #     "la":47.618418,
        #     "lo":-122.350964,
        #     "da":9,
        #     "dx":0,
        #     "ba":8,
        #     "bx":1
        # }
        data['stations'].each do |item|
            name = item['s']
            latitude = item['la']
            longitude = item['lo']
            bikes = item['ba']
            free = item['da']
            extra = {
                'uid' => item['n']
            }
            station = ProntoStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        self.stations = stations
    end
end

class ProntoStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, free, extra)
        super()
        @name       = name
        @latitude   = latitude
        @longitude  = longitude
        @bikes      = bikes
        @free       = free
        @extra      = extra
    end
end

# if __FILE__ == $0
#     require 'json'
#     JSON.parse(File.read('./schemas/pronto.json'))['instances'].each do |instance|
#         pronto = Pronto.new(instance)
#         puts pronto.meta
#         pronto.update
#         puts pronto.stations.length
#         pronto.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}, #{station.extra}"
#         end
#     end
# end