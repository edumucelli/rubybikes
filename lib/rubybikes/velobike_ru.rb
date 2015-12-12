# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' velobike_ru.py
# Distributed under the AGPL license, see LICENSE.txt
require 'json'

require_relative 'base'
require_relative 'utils'

class VelobikeRU < BikeShareSystem
    attr_accessor :stations, :meta

    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'company' => 'ЗАО «СитиБайк»'})
        super(tag, @meta)
    end
    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end
        data = JSON.parse(scraper.request(@feed_url))
        # Each station is
        # {
        #   "Address": "415 - \u0443\u043b. \u0421\u0443\u0449\u0451\u0432\u0441\u043a\u0438\u0439 \u0412\u0430\u043b, \u0434.2",
        #   "FreePlaces": 12,
        #   "Id": "0415",
        #   "IsLocked": true,
        #   "Position": {
        #       "Lat": 55.7914268,
        #       "Lon": 37.5905396
        #   },
        #   "TotalPlaces": 12
        # }
        stations = []
        data['Items'].each do |item|
            name = item['Address']
            latitude = item['Position']['Lat'].to_f
            longitude = item['Position']['Lon'].to_f
            free = item['FreePlaces'].to_i
            slots = item['TotalPlaces'].to_i
            bikes = slots - free
            extra = {
                'uid' => item['Id'],
                'slots' => slots,
                'address' => item['Address'],
            }
            station = VelobikeRUStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
    end
end

class VelobikeRUStation < BikeShareStation
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
#     JSON.parse(File.read('./schemas/velobike_ru.json'))['instances'].each do |instance|
#         velobike_ru = VelobikeRU.new(instance)
#         puts velobike_ru.meta
#         velobike_ru.update
#         puts velobike_ru.stations.length
#         velobike_ru.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.extra}, #{station.timestamp}"
#         end
#     end
# end