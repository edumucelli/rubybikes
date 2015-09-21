# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class CityNotAvailableError < StandardError; end

class EasyBike < BikeShareSystem

    API_URL = 'http://api.easybike.gr/cities.php'
    
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @city_id   = schema_instance_parameters.fetch('city_id')
        @meta     = meta.merge({'company' => ['Brainbox Technology', 'Smoove SAS']})
        super(tag, @meta)
    end

    def update
        stations = []
        scraper = Scraper.new()
        networks = JSON.parse(scraper.request(API_URL))
        network = networks.detect {|network| network["city"] == @city_id }
        raise CityNotAvailableError unless network
        stations = network['stations']
        unless stations.empty?
            @stations = network['stations'].map do |station|
                name = station['name'].encode('utf-8')
                latitude = station['lat'].to_f
                longitude = station['lng'].to_f
                bikes = station['BikesAvailable'].to_i
                free = station['DocksAvailable'].to_i
                extra = {'slos' => station['TotalDocks'].to_i}
                EasyBikeStation.new(name, latitude, longitude, bikes, free, extra)
            end
        end
    end
end

class EasyBikeStation < BikeShareStation
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

# if __FILE__ == $0
#     require 'json'
#     JSON.parse(File.read('./schemas/easybike.json'))['instances'].each do |instance|
#         easybike = EasyBike.new(instance)
#         puts easybike.meta
#         easybike.update
#         puts easybike.stations.length
#         easybike.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
#         end
#     end
# end