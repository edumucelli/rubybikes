# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'rexml/document'

require_relative 'base'
require_relative 'utils'

class Nextbike < BikeShareSystem

    BASE_URL = "https://nextbike.net/maps/nextbike-live.xml?domains=%{domain}"

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = BASE_URL % {:domain => schema_instance_parameters.fetch('domain')}
        @city_uid = schema_instance_parameters.fetch('city_uid')
        @meta     = meta.merge({'company' => 'Nextbike GmbH'})
        super(tag, @meta)
    end

    def update
        scraper = Scraper.new()
        data = scraper.request(@feed_url)
        xml = REXML::Document.new(data)
        xml.elements.each("//city[@uid=#{@city_uid}]/place") do |station|
            # A bike station looks like this
            # <place
                # bike_numbers='83264,83023,83294,83202,83016'
                # bike_racks='20'
                # bikes='5+'
                # lat='54.597175'
                # lng='-5.93097'
                # name='City Hall'
                # number='3902'
                # spot='1'
                # terminal_type='7inch'
                # uid='263966'/>
            name = station.attributes['name']
            latitude = station.attributes['lat'].to_f
            longitude = station.attributes['lng'].to_f
            raw_bikes = station.attributes['bikes']
            # Some stations count up to 5, then it addes a '+' sign, WHY.CANNOT.COUNT.NORMALLY?
            if raw_bikes.end_with?('+')
                bikes = raw_bikes.gsub('+', '').to_i
            else
                bikes = raw_bikes.to_i
            end
            free = station.attributes['slots'].to_i
            station = NextbikeStation.new(name, latitude, longitude, bikes, free)
            stations << station
        end
        @stations = stations
    end
end

class NextbikeStation < BikeShareStation
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
    JSON.parse(File.read('./schemas/nextbike.json'))['instances'].each do |instance|
        nextbike = Nextbike.new(instance)
        puts nextbike.meta
        nextbike.update
        puts nextbike.stations.length
        nextbike.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
        end
    end
end