# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'rexml/document'

require_relative 'base'
require_relative 'utils'

class CityBike < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag         = schema_instance_parameters.fetch('tag')
        meta        = schema_instance_parameters.fetch('meta')
        @feed_url   = schema_instance_parameters.fetch('feed_url')
        @meta       = meta.merge({'company' => 'Gewista Werbegesellschaft m.b.H'})
        super(tag, @meta)
    end
    def update
        scraper = Scraper.new()
        data = scraper.request(@feed_url)
        # <station>
        #     <id>102</id>
        #     <internal_id>1021</internal_id>
        #     <name>Fahnengasse</name>
        #     <boxes>18</boxes>
        #     <free_boxes>1</free_boxes>
        #     <free_bikes>17</free_bikes>
        #     <status>aktiv</status>
        #     <description>Ecke Herrengasse U3 Station Herrengasse links beim Ausgang Fahnengasse</description>
        #     <latitude>48.209481</latitude>
        #     <longitude>16.366086</longitude>
        # </station>
        xml = REXML::Document.new(data)
        xml.elements.each('stations/station') do |station|
            name = station.elements['name'].text
            latitude = station.elements['latitude'].text.to_f
            longitude = station.elements['longitude'].text.to_f
            bikes = station.elements['free_bikes'].text.to_i
            free = station.elements['free_boxes'].text.to_i
            extra = {'slots' => station.elements['boxes'].text.to_i,
                     'status' => station.elements['status'].text,
                     'description' => station.elements['description'].text}
            station = CityBikeStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
    end
end

class CityBikeStation < BikeShareStation
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

# if __FILE__ == $0
#     require 'json'
#     JSON.parse(File.read('./schemas/citybike.json'))['instances'].each do |instance|
#         citybike = CityBike.new(instance)
#         puts citybike.meta
#         citybike.update
#         puts citybike.stations.length
#         citybike.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
#         end
#     end
# end