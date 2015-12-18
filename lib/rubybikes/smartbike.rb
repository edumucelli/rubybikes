# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' smartbike.py, mainly on how to deal with the messy double encoded JSON, damn it!)
# Distributed under the AGPL license, see LICENSE.txt

require 'json'
require 'cgi'

require_relative 'base'
require_relative 'utils'

class SmartBike < BikeShareSystem

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('feed_url')
        @format = schema_instance_parameters.fetch('format')
        @meta     = meta.merge({'company' => 'ClearChannel'})
        super(tag, @meta)
    end

    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end
        stations = []
        data = JSON.parse(scraper.request(@feed_url))
        if @format == "json_v1"
            # {"StationID":"1",
            # "DisctrictCode":"1",
            # "AddressGmapsLongitude":"-0.90466700000000000",
            # "AddressGmapsLatitude":"41.67046400000000000",
            # "StationAvailableBikes":"11",
            # "StationFreeSlot":"13",
            # "AddressZipCode":"11111",
            # "AddressStreet1":"Avda. Pablo Ruiz Picasso - Torre del Agua",
            # "AddressNumber":"0",
            # "NearbyStationList":"2,3,69",
            # "StationStatusCode":"OPN",
            # "StationName":"1 - Avda. Pablo Ruiz Picasso - Torre del Agua"}
            # Double-encoded JSON, that is nasty and messed up!
            JSON.parse(data[1]['data']).each do |info|
                name = info['StationName']
                latitude = info['AddressGmapsLatitude'].to_f
                longitude = info['AddressGmapsLongitude'].to_f
                bikes = info['StationAvailableBikes'].to_i
                free = info['StationFreeSlot']
                extra = {'address' => "#{info['AddressStreet1']}, #{info['AddressNumber']}"}
                station = SmartBikeStation.new(name, latitude, longitude, bikes, free, extra)
                stations << station
            end
        else
            # {"id"=>"488",
            # "district"=>"10",
            # "lon"=>"2.184391",
            # "lat"=>"41.423976",
            # "bikes"=>"7",
            # "slots"=>"5",
            # "zip"=>"08027",
            # "address"=>"(PK) C/ DE CIENFUEGOS",
            # "addressNumber"=>"13",
            # "nearbyStations"=>"464,468",
            # "status"=>"OPN",
            # "name"=>"488 - (PK) C/ DE CIENFUEGOS, 13",
            # "stationType"=>"ELECTRIC_BIKE"}
            data.each do |info|
                name = info['name']
                latitude = info['lat'].to_f
                longitude = info['lon'].to_f
                bikes = info['bikes'].to_i
                free = info['slots']
                extra = {'address' => "#{info['address']}, #{info['addressNumber']}"}
                station = SmartBikeStation.new(name, latitude, longitude, bikes, free, extra)
                stations << station
            end
        end
        @stations = stations
    end
end

class SmartBikeNew < BikeShareSystem

    # Stations looks like this, however HTML is not clean as shown bellow,
    # but a mess of unescaped-unicode-formatted string
    # GoogleMap.addMarker(
    # '/media/assets/images/station_map/more_than_five_bikes_flag.png',
    # 45.464683238626,
    # 9.18879747390747,
    # 'Duomo',
    # '<div style="width: 240px; height: 120px;">
    #     <span style="font-weight: bold;">178 - V Alpini</span>
    #     <br>
    #     <ul>
    #         <li>Available bicycles: 9</li>
    #         <li>Available electrical bicycles: 0</li>
    #         <li>Available slots: 20</li>
    #         </ul>
    # </div>');
    
    STATIONS_RGX = /GoogleMap\.addMarker\(.*?,\s*(\d+.\d+)\s*,\s*(\d+.\d+),\s*\'(.*?)\',(.*?)\)\;/
    STATUS_RGX = /.*?Available bicycles:\s*(\d+).*?Available electrical bicycles:\s*(\d+).*?Available slots:\s*(\d+)/

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'company' => 'ClearChannel'})
        super(tag, @meta)
    end

    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end
        stations = []
        html = scraper.request(@feed_url)
        data = html.scan(STATIONS_RGX)
        data.each do |item|
            latitude, longitude, name, mess = item
            standard_bikes, electric_bikes, free = mess.scan(STATUS_RGX)[0]
            bikes = standard_bikes.to_i + electric_bikes.to_i
            station = SmartBikeStation.new(name, latitude.to_f, longitude.to_f, bikes, free.to_i)
            stations << station
        end
        @stations = stations
    end
end

class SmartBikeStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, free, extra={})
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
#     JSON.parse(File.read('./schemas/smartbike.json'))['class']['SmartBikeNew']['instances'].each do |instance|
#     # JSON.parse(File.read('./schemas/samba.json'))['class']['SambaNew']['instances'].each do |instance|
#         smartbike = SmartBikeNew.new(instance)
#         puts smartbike.meta
#         smartbike.update
#         puts smartbike.stations.length
#         smartbike.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}, #{station.extra}"
#         end
#     end
# end