# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' callabike.py
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class Callabike < BikeShareSystem

    BASE_URL = "http://www.callabike-interaktiv.de/kundenbuchung/hal2ajax_process.php?callee=getMarker&mapstadt_id=%{city_id}&requester=bikesuche&ajxmod=hal2map&bereich=2&buchungsanfrage=N&webfirma_id=500&searchmode=default"

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag     = schema_instance_parameters.fetch('tag')
        meta    = schema_instance_parameters.fetch('meta')
        city_id = schema_instance_parameters.fetch('city_id')
        @meta   = meta.merge({'company' => 'DB Rent GmbH'})
        super(tag, @meta)
        @feed_url = BASE_URL % {:city_id => city_id}
    end
    def update
        stations = []
        scraper = Scraper.new()
        html = scraper.request(@feed_url)
        markers = JSON.parse(html)
        # {
        #     "lat" => "49.858031000000000",
        #     "lng" => "8.651165000000000",
        #     "iconName" => "bikeIconFix",
        #     "iconNameSelected" => "",
        #     "hal2option" => {
        #         "minZoom" => "11",
        #         "maxZoom" => false,
        #         "tooltip" => "'6420180&nbsp;Bessunger&nbsp;Platz'",
        #         "id" => "20768487011723",
        #         "openinfo" => "openDynamicInfoWindow",
        #         "click" => "openDynamicInfoWindow",
        #         "mouseover" => "showToolTip",
        #         "mouseout" => "hideToolTip",
        #         "dblclick" => false,
        #         "rclick" => false,
        #         "draggable" => false,
        #         "proc" => "bikesuche",
        #         "cabfixflex" => "flex",
        #         "firmen" => "500,510,530,540",
        #         "objectname" => "bikemarker",
        #         "meta_id" => "3017",
        #         "standort_id" => "238840",
        #         "bikes" => "9518",
        #         "bikelist" => [{
        #             "Number" => "9518", "Version" => "5", "canBeRented" => true, "canBeReturned" => false,
        #             "MarkeID" => "1312", "MarkeName" => "CallBike", "isPedelec" => false, "FirmaID" => "500"
        #         }], "objecttyp" => "cab_standort", "clustername" => "bikecluster", "filter" => ["cab_flex"]
        #     }
        # }
        markers['marker'].each do |marker|
            prefix = marker['hal2option']
            unless prefix['standort_id'].empty?
                name       = prefix['tooltip'].gsub('&nbsp;', ' ').gsub('\'','')
                latitude   = marker['lat'].to_f
                longitude  = marker['lng'].to_f
                bikelist   = prefix['bikelist']
                bikes      = bikelist.count {|bike| bike["canBeRented"]}
                extra      = {
                    'uid' => prefix['standort_id']
                }
                station = CallabikeStation.new(name, latitude, longitude, bikes, extra)
                stations << station
            end
        end
        @stations = stations
    end
end

class CallabikeStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, extra)
        super()
        @name = name
        @latitude = latitude
        @longitude = longitude
        @bikes = bikes
        @extra = extra
    end
end

# if __FILE__ == $0
#     JSON.parse(File.read('./schemas/callabike.json'))['instances'].each do |instance|
#         callabike = Callabike.new(instance)
#         callabike.update
#         puts callabike.stations.length
#         callabike.stations.each do |station|
#             # puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.extra}"
#         end
#     end
# end