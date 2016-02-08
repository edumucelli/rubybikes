# Copyright (C) 2016, Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require_relative 'base'
require_relative 'utils'

class Cyclehire < BikeShareSystem

    DATA_RGX = /var sites = \[(.*?)\]\;/
    STATIONS_RGX = /\[(.*?)\]/

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url  = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'company' => 'Groundwork, ITS'})
        super(tag, @meta)
    end
    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end
        stations = []
        
        # var sites = [['<p><strong>001-Slough Train Station</strong></p>',
        #                51.511350,-0.591562, ,
        #                '<p><strong>001-Slough Train Station</strong></p>
        #                    <p>Number of bikes available: 11</p>
        #                    <p>Number of free docking points: 21</p>'], ...

        html = scraper.request(@feed_url)
        data = html.match(DATA_RGX).captures.first
        raw_stations = data.scan(STATIONS_RGX)
        raw_stations.each do |raw_station|
            fields = raw_station[0].split(',')
            latitude = fields[1].to_f
            longitude = fields[2].to_f
            raw_status = fields[4]
            name, bikes, free = raw_status.scan(/<strong>(.*?)<\/strong>.*?(\d+).*?(\d+)/)[0]
            station = CycleHireStation.new(name, latitude, longitude, bikes, free, {})
            stations << station
        end
        @stations = stations
    end
end

class CycleHireStation < BikeShareStation
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
#     JSON.parse(File.read('./schemas/cyclehire.json'))['instances'].each do |instance|
#         cyclehire = Cyclehire.new(instance)
#         puts cyclehire.meta
#         cyclehire.update
#         puts cyclehire.stations.length
#         cyclehire.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.extra}"
#         end
#     end
# end