# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require_relative 'base'
require_relative 'utils'

class Emovity < BikeShareSystem

    LAT_LNG_RGX = /addMarker\(\d+,([-+]?\d+.\d+),([-+]?\d+.\d+)/
    DATA_RGX    = /html\[\d+\]='.*?<div style=\\"font-weight\:bold;font-size:14px;\\">.*?(.*?)<\/div><div>(.*?)<\/div><div>Bicis lliures:.*?(\d+)<\/div><div>Aparcaments lliures:.*?(\d+).*?';/

    # DATA_RGX parses stations' info as:
    # <div style=\"width:210px; padding-right:10px;\">
    #     <div style=\"font-weight:bold;font-size:14px;\">01- Biblioteca Antònia Adroher</div>
    #     <div>Biblioteca Antònia Adroher</div>
    #     <div>Bicis lliures: 14</div>
    #     <div>Aparcaments lliures: 4</div>
    # </div>
    
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag         = schema_instance_parameters.fetch('tag')
        meta        = schema_instance_parameters.fetch('meta')
        @feed_url   = schema_instance_parameters.fetch('feed_url')
        @meta       = meta.merge({'company' => 'ICNITA S.L.'})
        super(tag, @meta)
    end

    def update
        scraper = Scraper.new
        html = scraper.request(@feed_url)
        points = html.scan(LAT_LNG_RGX)
        data = html.scan(DATA_RGX)
        @stations = points.zip(data).map do |point, info|
            latitude, longitude = point
            name, address, bikes, free = info
            extra = {'address' => address}
            EmovityStation.new(name, latitude.to_f, longitude.to_f, bikes.to_i, free.to_i, extra)
        end
    end
end

class EmovityStation < BikeShareStation
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
#     JSON.parse(File.read('./schemas/emovity.json'))['instances'].each do |instance|
#         emovity = Emovity.new(instance)
#         puts emovity.meta
#         emovity.update
#         puts emovity.stations.length
#         emovity.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
#         end
#     end
# end