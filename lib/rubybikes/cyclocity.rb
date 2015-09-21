# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' cyclocity.py
# Distributed under the AGPL license, see LICENSE.txt

require 'json'
require 'rexml/document'

require_relative 'base'
require_relative 'utils'

class APIKeyNotAvailableError < StandardError; end

class Cyclocity < BikeShareSystem

    API_URL = "https://api.jcdecaux.com/vls/v1/stations?apiKey=%{api_key}&contract=%{contract}"

    attr_accessor :stations, :meta
    def initialize(api_key = nil, schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        raise APIKeyNotAvailableError unless api_key
        @meta     = meta.merge({'company' => 'JCDecaux',
                                'license' => {
                                    'name' => 'Open Licence',
                                    'url' => 'https://developer.jcdecaux.com/#/opendata/licence'
                                },
                                'source' => 'https://developer.jcdecaux.com'})
        super(tag, @meta)
        @contract   = schema_instance_parameters.fetch('contract')
        @api_key    = api_key
        @feed_url   = API_URL % {:api_key => @api_key, :contract => @contract}
    end
    def update
        stations = []
        scraper = Scraper.new()
        data = JSON.parse(scraper.request(@feed_url))
        data.each do |info|
            name      = info['name']
            latitude  = info['position']['lat']
            longitude = info['position']['lng']
            bikes     = info['available_bikes']
            free      = info['available_bike_stands']
            extra = {
                'address' => info['address'],
                'closed' => info['status'] != 'OPEN',
                'banking' => info['banking'],
                'bonus' => info['bonus'],
                'slots' => info['bike_stands']
            }
            station = CyclocityStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
    end
    def self.authed; end
end

class CyclocityWeb < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        endpoint  = schema_instance_parameters.fetch('endpoint')
        city      = schema_instance_parameters.fetch('city')
        @meta     = meta.merge({'label' => 'Cyclocity', 'company' => 'JCDecaux'})
        super(tag, @meta)
        @carto_url = "#{schema_instance_parameters.fetch('endpoint')}/service/carto"
        @station_url = "#{schema_instance_parameters.fetch('endpoint')}/service/stationdetails/#{city}/%{id}"
    end
    def update
        stations = []
        scraper = Scraper.new()
        carto_xml = REXML::Document.new(scraper.request(@carto_url))
        carto_xml.elements.each('carto/markers/marker') do |marker|
            name        = marker.attributes['name']
            latitude    = marker.attributes['lat']
            longitude   = marker.attributes['lng']
            number      = marker.attributes['number']
            # <station>
            #   <available>0</available>
            #   <free>29</free>
            #   <total>29</total>
            #   <ticket>0</ticket>
            #   <open>1</open>
            #   <updated>1441831145</updated>
            #   <connected>1</connected>
            # </station>
            station_xml = REXML::Document.new(scraper.request(@station_url % {:id => number.to_i}))
            station_xml.elements.each('station') do |station|
                bikes   = station.elements['available'].text.to_i
                free    = station.elements['free'].text.to_i
                extra   = { 'slots' => station.elements['total'].text.to_i,
                            'ticket'=> station.elements['ticket'].text.to_bool,
                            'closed'=> !station.elements['open'].text.to_bool,
                            'connected'=> station.elements['connected'].text.to_bool}
                station = CyclocityStation.new(name, latitude, longitude, bikes, free, extra)
                stations << station
            end
        end
        @stations = stations
    end
end

class CyclocityStation < BikeShareStation
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
#     # instance = { "tag" => "cyclic", 
#     #     "meta" => {
#     #         "latitude" => 49.44323199999999, 
#     #         "country" => "FR", 
#     #         "name" => "cy'clic", 
#     #         "longitude" => 1.099971, 
#     #         "city" => "Rouen"
#     #     }, 
#     #     "contract" => "Rouen"
#     # }
#     instance = {
#         "city" => "brisbane", 
#         "meta" => {
#             "latitude" => -27.4710107, 
#             "city" => "Brisbane", 
#             "name" => "CityCycle", 
#             "longitude" => 153.0234489, 
#             "country" => "AU"
#         }, 
#         "tag" => "citycycle", 
#         "endpoint" => "http://www.citycycle.com.au"
#     }
#     cyclocity = CyclocityWeb.new(instance)
#     cyclocity.update
#     puts cyclocity.stations.length
#     cyclocity.stations.each do |station|
#         puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
#     end
# end