# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' punpunbikeshare.py
# Distributed under the AGPL license, see LICENSE.txt
require 'json'

require_relative 'base'
require_relative 'utils'

class Punpunbikeshare < BikeShareSystem
    attr_accessor :stations, :meta

    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'company' => 'BTS Group Holdings'})
        super(tag, @meta)
    end
    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end
        data = JSON.parse(scraper.request(@feed_url))
        # Each station is like follows
        # If there's no bikeId in bikeDocks object, it means dock is free
        # Status seem mostly ignored by website, so let's not make assumptions
        # on that.
        # {
        #     "stationId":"01",
        #     "stationName":"foo bar",
        #     "location":"Chamchuri Square",
        #     "lat":"13.73345498316396",
        #     "lng":"100.52908658981323",
        #     "status":"1",
        #     "bikeDockCount":"8",
        #     "bikeDocks":[
        #         {"dockId":"9","bikeId":"0000A24C20C4","status":"1"},
        #         {"dockId":"10","bikeId":"0000E2CF1FC4","status":"1"},
        #         {"dockId":"11","bikeId":"000052B71FC4","status":"1"},
        #         {"dockId":"12","bikeId":"","status":"1"}
        #         ...
        #     ]
        # }
        stations = []
        data['stations'].each do |item|
            name = item['stationName']
            latitude = item['lat'].to_f
            longitude = item['lng'].to_f
            slots = item['bikeDockCount'].to_i
            bikes = item['bikeDocks'].count{ |h| !h['bikeId'].empty? }
            free = slots - bikes
            extra = {
                'slots' => slots,
                'address' => item['location'],
                'uid' => item['stationId']
            }
            station = PunpunbikeshareStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
    end
end

class PunpunbikeshareStation < BikeShareStation
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
#     JSON.parse(File.read('./schemas/punpunbikeshare.json'))['instances'].each do |instance|
#         punpunbikeshare = Punpunbikeshare.new(instance)
#         puts punpunbikeshare.meta
#         punpunbikeshare.update
#         puts punpunbikeshare.stations.length
#         punpunbikeshare.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.extra}, #{station.timestamp}"
#         end
#     end
# end