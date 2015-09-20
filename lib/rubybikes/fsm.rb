# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require_relative 'base'
require_relative 'utils'

class FSM < BikeShareSystem

    STATIONS_RGX = /setMarker\((.*?), '<a href\=/
    # A station looks like big monsters with lots of HTML, which was discarded
    # setMarker(34.809,
    #           32.07,
    #           611,
    #           'וייצמן 57',
    #           'וייצמן 57 -  גבעתיים',
    #           '20',
    #           '20',
    #           '<a href="..." ...
    # lon, lat, id, name, address, poles, available, nearStationsDiv, isActive
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'company' => 'FSM'})
        super(tag, @meta)
    end
    def update
    	scraper = Scraper.new
        html = scraper.request(@feed_url)
        @stations = html.scan(STATIONS_RGX).map do |info|
            fields = info[0].gsub('\'','').split(',')
            longitude = fields[0].to_f
            latitude = fields[1].to_f
            name = fields[3]
            address = fields[4]
            slots = fields[5].to_i
            free = fields[6].to_i
            bikes = slots - free
            extra = {'slots' => slots,
                     'address' => address}
            FSMStation.new(name, latitude, longitude, bikes, free, extra)
        end
    end
end

class FSMStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, free, extra)
        super()
        @name       = name
        @latitude   = latitude
        @longitude  = longitude
        @bikes      = bikes
        @free       = free
        @extra      = extra
    end
end

if __FILE__ == $0
    require 'json'
    JSON.parse(File.read('./schemas/fsm.json'))['instances'].each do |instance|
        fsm = FSM.new(instance)
        puts fsm.meta
        fsm.update
        puts fsm.stations.length
        fsm.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}, #{station.extra}"
        end
    end
end