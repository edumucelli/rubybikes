# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'rexml/document'

require_relative 'base'
require_relative 'utils'

class DecoBike < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url  = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge(meta = {'company' => 'DecoBike LLC'})
        super(tag, @meta)
    end

    def update
        stations = []
        scraper = Scraper.new()
        data = scraper.request(@feed_url)
        # <locations>
        #     <location>
        #     <Id>601</Id>
        #     <Address>Grand Ave & Main Hwy</Address>
        #     <Distance>0</Distance>
        #     <Latitude>25.7280500</Latitude>
        #     <Longitude>-80.2417300</Longitude>
        #     <Bikes>1</Bikes>
        #     <Dockings>15</Dockings>
        #     <StationAdList/>
        #     </location>
        # ...
        xml = REXML::Document.new(data)
        xml.elements.each('locations/location') do |station|
            address = station.elements['Address'].text
            name = "#{station.elements['Id'].text} - #{address}"
            latitude = station.elements['Latitude'].text.to_f
            longitude = station.elements['Longitude'].text.to_f
            bikes = station.elements['Bikes'].text.to_i
            free = station.elements['Dockings'].text.to_i
            extra = {'address' => address}
            station = DecoBikeStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
    end
end

class DecoBikeStation < BikeShareStation
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
    require 'json'
    JSON.parse(File.read('./schemas/decobike.json'))['instances'].each do |instance|
        decobike = DecoBike.new(instance)
        puts decobike.meta
        decobike.update
        puts decobike.stations.length
        decobike.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
        end
    end
end