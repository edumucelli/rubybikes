# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' veloway.py
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class Veloway < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag     = schema_instance_parameters.fetch('tag')
        meta    = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('feed_url')
        @meta   = meta.merge({'company' => 'Veolia'})
        super(tag, @meta)
    end
    def update
        stations = []
        scraper = Scraper.new()
        data = JSON.parse(scraper.request(@feed_url))
        # "stand"=>[{"wcom"=>"",
        #             "disp"=>"1",
        #             "neutral"=>"0",
        #             "lng"=>"-2.76028299331665",
        #             "lat"=>"47.6581840515137",
        #             "tc"=>"24",
        #             "ac"=>"24",
        #             "ap"=>"16",
        #             "ab"=>"8",
        #             "id"=>"1",
        #             "name"=>"H%c3%b4tel+de+Ville"}, ...]
        data['stand'].map do |stand|
            latitude = stand['lat'].to_f
            longitude = stand['lng'].to_f
            unless latitude.zero? && longitude.zero?
                name = stand['name']
                bikes = stand['ab']
                free = stand['ap']
                extra = {'slots' => stand['ac'].to_i, 'closed' => stand['disp'] != "1"}
                station = VelowayStation.new(name, latitude, longitude, bikes, free, extra)
                stations << station
            end
        end
        @stations = stations
    end
end

class VelowayStation < BikeShareStation
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
#     JSON.parse(File.read('./schemas/veloway.json'))['instances'].each do |instance|
#         veloway = Veloway.new(instance)
#         veloway.update
#         puts veloway.stations.length
#         veloway.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}, #{station.extra}"
#         end
#     end
# end