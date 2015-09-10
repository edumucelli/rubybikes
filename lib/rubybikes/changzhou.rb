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
        feed_url  = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'label' => 'Changzhou', 'company' => 'Changzhou Wing Public Bicycle Systems Co., Ltd.'})
        super(tag, @meta)
        @feed_url = feed_url
    end

    def update
        stations = []
        scraper = Scraper.new()
        html = scraper.request(@feed_url)
        data = JSON.parse(html.gsub('var ibike = ',''))

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

if __FILE__ == $0
    JSON.parse(File.read('./schemas/changzhou.json'))['instances'].each do |instance|
        changzhou = Changzhou.new(instance)
        changzhou.update
        puts changzhou.stations.length
        changzhou.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
        end
    end
end