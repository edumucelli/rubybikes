# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require_relative 'base'
require_relative 'utils'

class BCycle < BikeShareSystem

    LAT_LNG_RGX = /var point = new google.maps.LatLng\(([-+]?\d+.\d+).*?([-+]?\d+.\d+)\)\;/
    DATA_RGX = /var marker = new createMarker\(point\,.*?<h3>(.*?)<\/h3>.*?<div class='markerAddress'>(.*?)<\/div>.*?<h3>(.*?)<\/h3>.*?<h3>(.*?)<\/h3>.*?\,\ icon\,\ back/

    # DATA_RGX deals with each of the fields bellow as groups '(.*?)'
    # <div class='markerTitle'>
    #     <h3>Gunbarrel North</h3>
    # </div>
    # <div class='markerPublicText'>
    #     <h5></h5>
    # </div>
    # <div class='markerAddress'>5510 Spine Rd.
    #     <br />Boulder, CO 80301
    # </div>
    # <div class='markerAvail'>
    #     <div style='float: left; width: 50%'>
    #         <h3>9</h3>Bikes
    #     </div>
    #     <div style='float: left; width: 50%'>
    #         <h3>12</h3>Docks
    #     </div>
    # </div>

    # DATA_RGX does not match the purgatory station,
    # which contains LAT_LNG points equal to zero.
    # We just remove the points later on

    # "<div class='markerTitle'>
    #     <h3>Purgatory</h3>
    # </div>
    # <div class='markerPublicText'>
    #     <h5>For bikes that are lost, pending recovery.</h5>
    # </div>
    # <div class='markerAddress'>
    #     unknown<br />Boulder?, CO
    # </div>
    # <div class='markerEvent'>
    #     4/30/2014 - 1/1/2020
    # </div>", icon, back, false);

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('feed_url')
        @meta   = meta.merge({"company" => ['Trek Bicycle Corporation', 'Humana', 'Crispin Porter + Bogusky']})
        super(tag, meta)
    end
    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new(headers={'User-Agent' => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36
                                                            (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36"})
        end
        stations = []

        html = scraper.request(@feed_url)
        points = html.scan(LAT_LNG_RGX)
        points.delete_if { |latitude, longitude| latitude.to_f.zero? && longitude.to_f.zero? }
        data = html.scan(DATA_RGX)
        points.zip(data).each do |point, info|
            latitude, longitude = point.map(&:to_f)
            unless latitude.zero? && longitude.zero?
                name, address, bikes, free = info
                extra = {'address' => address}
                station = BCycleStation.new(name, latitude, longitude, bikes.to_i, free.to_i, extra)
                stations << station
            end
        end
        @stations = stations
    end
end

class BCycleStation < BikeShareStation
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
    JSON.parse(File.read('./schemas/bcycle.json'))['instances'].each do |instance|
        bcycle = BCycle.new(instance)
        puts bcycle.meta
        bcycle.update
        puts bcycle.stations.length
        bcycle.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}, #{station.extra}"
        end
    end
end