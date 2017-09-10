# -*- coding: utf-8 -*-
# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class BikeshareIE < BikeShareSystem

    FEED_URL = "https://www.bikeshare.ie/"
    STATIONS_RGX = /var\ mapsfromcache\ =\ (.*?);/

    attr_accessor :stations, :meta

    def initialize(schema_instance_parameters={})
        tag     = schema_instance_parameters.fetch('tag')
        meta    = schema_instance_parameters.fetch('meta')
        @system_id = schema_instance_parameters.fetch('system_id')
        @meta   = meta.merge({'company' => 'The National Transport Authority'})
        super(tag, meta)
    end
    
    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end
        stations = []

        html = scraper.request(FEED_URL)
        stations_html = html.scan(STATIONS_RGX)
        data = JSON.parse(stations_html[0][0])

        data[@system_id].each do |item|
            name = item['name']
            latitude = item['latitude']
            longitude = item['longitude']
            bikes = item['bikesAvailable']
            free = item['docksAvailable']
            extra = {
                'uid' => item['stationId'],
                'slots' => item['docksCount']
            }
            station = BikeshareIEStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
    end
end

class BikeshareIEStation< BikeShareStation
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
#     JSON.parse(File.read('./schemas/bikeshare_ie.json'))['instances'].each do |instance|
#         bikeshare_ie = BikeshareIE.new(instance)
#         puts bikeshare_ie.meta
#         bikeshare_ie.update
#         puts bikeshare_ie.stations.length
#         bikeshare_ie.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}, #{station.extra}"
#         end
#     end
# end