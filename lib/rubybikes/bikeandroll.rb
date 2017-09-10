# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class BikeAndRoll < BikeShareSystem

    STATIONS_RGX = /jQuery\.extend\(Drupal.settings,\s*(.*?)\);/

    attr_accessor :stations, :meta
    
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url  = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'company' => ['Bike and Roll Chicago', 'Smoove']})
        super(tag, @meta)
    end

    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end
        stations = []
        
        html = scraper.request(@feed_url)
        data = JSON.parse(html.match(STATIONS_RGX).captures.first)
        data['markers'].each do |station|
            name = station['title']
            latitude = station['latitude'].to_f
            longitude = station['longitude'].to_f
            bikes = station['avl_bikes'].to_i
            free = station['free_slots'].to_i
            slots = station['total_slots'].to_i
            uid = station['nid']
            extra = {'slots' => slots, 'uid' => uid}
            station = BikeAndRollStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
    end
end

class BikeAndRollStation < BikeShareStation
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
#     require 'json'
#     JSON.parse(File.read('./schemas/bikeandroll.json'))['instances'].each do |instance|
#         bikeandroll = BikeAndRoll.new(instance)
#         puts bikeandroll.meta
#         bikeandroll.update
#         puts bikeandroll.stations.length
#         bikeandroll.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.extra}"
#         end
#     end
# end