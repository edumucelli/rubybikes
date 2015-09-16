# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'rexml/document'

require_relative 'base'
require_relative 'utils'

class Nubija < BikeShareSystem

    # First, fetch a list of stations with respective IDs ('tmno').
    # Then, for each station get info about name, available bikes, and free slots  

    # addMarker('35.195964', '128.571611', '244', 'Y', '263'); 
    STATIONS_RGX = /.*?addMarker\((.*?)\);/

    # <h1 style="font-size: 11px;font-weight: bold;font-family:Dotum, sans-serif; padding-bottom: 5px; text-align: left ">
    #     <img src="../images/terminal/icon.gif" width="6" height="9"> 개나리 4차아파트
    # </h1>

    # <p>반납 가능 거치대 : <span>10</span> 대 </p>
    # <p>대여 가능 자전거 : <span>15</span> 대 </p>
    INFO_RGX = /<h1.*?>.*?<img.*?>\s*(.*?)\s*<\/h1>.*?<span>(\d+)<\/span>.*?<span>(\d+)<\/span>/m # multiline match "/regex/m"

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag             = schema_instance_parameters.fetch('tag')
        meta            = schema_instance_parameters.fetch('meta')
        @stations_url   = schema_instance_parameters.fetch('endpoint') + "terminalStateView.do"
        @info_url       = schema_instance_parameters.fetch('endpoint') + "terminalMapInfoWindow.do?tmno=%{tmno}"
        super(tag, @meta)
    end
    def update
        stations = []
        scraper = Scraper.new()
        html = scraper.request(@stations_url)
        html.scan(STATIONS_RGX).each do |marker|
            fields = marker[0].gsub("\'", '').gsub(' ', '').split(',')
            latitude = fields.first.to_f
            longitude = fields[1].to_f
            tmno = fields.last
            info_html = scraper.request(@info_url % {:tmno => tmno})
            name, free, bikes = info_html.scan(INFO_RGX)[0]
            station = NubijaStation.new(name, latitude, longitude, bikes.to_i, free.to_i)
            stations << station
        end
        @stations = stations
    end
end

class NubijaStation < BikeShareStation
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
    JSON.parse(File.read('./schemas/nubija.json'))['instances'].each do |instance|
        nubija = Nubija.new(instance)
        puts nubija.meta
        nubija.update
        puts nubija.stations.length
        nubija.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
        end
    end
end
