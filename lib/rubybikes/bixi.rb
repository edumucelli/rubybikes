require 'json'
require 'rexml/document'

require_relative 'base'
require_relative 'utils'

FORMAT_JSON = 'json'
FORMAT_XML  = 'xml'
FORMAT_JSON_FROM_XML = 'json_from_xml'

class Bixi < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        feed_url  = schema_instance_parameters.fetch('feed_url')
        @format   = schema_instance_parameters.fetch('format')
        @meta     = meta.merge({'label' => 'Bixi', 'company' => 'PBSC'})
        super(tag, @meta)
        @feed_url = feed_url
    end

    def update
        stations = []
        scraper = Scraper.new()
        html = scraper.request(@feed_url)
        if @format == FORMAT_JSON
            # {
            #   "id":2026,
            #   "stationName":"Broadway & W 60 Street",
            #   "availableDocks":0,
            #   "totalDocks":0,
            #   "latitude":40.76915505,
            #   "longitude":-73.98191841,
            #   "statusValue":"Planned",
            #   "statusKey":2,
            #   "availableBikes":0,
            #   "stAddress1":"Broadway & W 60 Street",
            #   "stAddress2":"",
            #   "city":"",
            #   "postalCode":"",
            #   "location":"",
            #   "altitude":"",
            #   "testStation":false,
            #   "lastCommunicationTime":null,
            #   "landMark":""
            # }
            data = JSON.parse(html)
            data['stationBeanList'].each do |marker|
                if marker['statusValue'] == 'Planned' or marker['testStation']
                    next
                end
                name        = "#{marker['id']} - #{marker['stationName']}"
                latitude    = marker['latitude']
                longitude   = marker['longitude']
                bikes       = marker['availableBikes']
                free        = marker['availableDocks']
                extra       = {'slots' => marker['totalDocks']}
                station     = BixiStation.new(name, latitude, longitude, bikes, free, extra)
                stations << station
            end
            @stations = stations
        elsif @format == FORMAT_XML
            # <station>
            #     <id>1</id>
            #     <name>Notre Dame / Place Jacques Cartier</name>
            #     <terminalName>6001</terminalName>
            #     <lat>45.508183</lat>
            #     <long>-73.554094</long>
            #     <installed>true</installed>
            #     <locked>false</locked>
            #     <installDate>1276012920000</installDate>
            #     <removalDate />
            #     <temporary>false</temporary>
            #     <nbBikes>14</nbBikes>
            #     <nbEmptyDocks>17</nbEmptyDocks>
            # </station>
            xml = REXML::Document.new(html)
            xml.elements.each('stations/station') do |station|
                name        = "#{station.elements['terminalName'].text} - #{station.elements['name'].text}"
                latitude    = station.elements['lat'].text.to_f
                longitude   = station.elements['long'].text.to_f
                bikes       = station.elements['nbBikes'].text.to_f
                free        = station.elements['nbEmptyDocks'].text.to_i
                extra       = {'closed' => station.elements['locked'].text.to_bool}
                station     = BixiStation.new(name, latitude, longitude, bikes, free, extra)
                stations << station
            end
            @stations = stations
        else # FORMAT_JSON_FROM_XML
            # { 
            # "id": "2", 
            # "name": "Docklands Drive - Docklands", 
            # "terminalName": "60000", 
            # "lastCommWithServer": "1375644471147", 
            # "lat": "-37.814022", 
            # "long": "144.939521", 
            # "installed": "true", 
            # "locked": "false", 
            # "installDate": "1313724600000", 
            # "removalDate": {  }, 
            # "temporary": "false", 
            # "public": "true", 
            # "nbBikes": "15", 
            # "nbEmptyDocks": "8", 
            # "latestUpdateTime": "1375592453128" 
            # }
            data = JSON.parse(html)
            data.each do |station|
                name        = "#{station['terminalName']} - #{station['name']}"
                latitude    = station['lat'].to_f
                longitude   = station['long'].to_f
                bikes       = station['nbBikes'].to_f
                free        = station['nbEmptyDocks'].to_i
                extra       = {'closed' => station['locked'].to_bool}
                station     = BixiStation.new(name, latitude, longitude, bikes, free, extra)
                stations << station
            end
            @stations = stations
        end
    end
end

class BixiStation < BikeShareStation
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

# schema_instance_parameters = {
#     "tag" => "melbourne-bike-share", 
#     "meta" => {
#         "city" => "Melbourne", 
#         "name" => "Melbourne Bike Share", 
#         "country" => "AU", 
#         "company" => [
#             "PBSC", 
#             "Alta Bicycle Share, Inc"
#         ], 
#         "longitude" => 144.96328, 
#         "latitude" => -37.814107
#     }, 
#     "feed_url" => "http://www.melbournebikeshare.com.au/stationmap/data", 
#     "format" => "json_from_xml"
# }

# bikeu = Bixi.new(schema_instance_parameters)
# bikeu.update
# puts bikeu.stations.length
# bikeu.stations.each do |station|
#     puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}"
# end