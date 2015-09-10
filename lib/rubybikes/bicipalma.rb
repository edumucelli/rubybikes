# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the GPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

COOKIE_URL = "http://83.36.51.60:8080/eTraffic3/Control?act=mp"
DATA_URL = "http://83.36.51.60:8080/eTraffic3/DataServer?ele=equ&type=401&li=2.6288892088318&ld=2.6721907911682&ln=39.58800054245&ls=39.55559945755&zoom=15&adm=N&mapId=1&lang=es"

INFO_RGX = /.*?Bicis Libres:<\/span>.*?(\d+).*?<\/div>.*?Anclajes Libres:<\/span>.*?(\d+).*?/

class BiciPalma < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @meta     = meta.merge({'label' => 'BiciPalma'})
        super(tag, @meta)
    end

    def update
        scraper = Scraper.new(headers = {'User-Agent' => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36",
                                        'Referer' => 'http://83.36.51.60:8080/eTraffic3/Control?act=mp'})
        # First visit just to eat the cookie ;-)
        scraper.request(COOKIE_URL)
        html = scraper.request(DATA_URL)
        markers = JSON.parse(html)
        # {
        #     "enabled" => true,
        #     "accionDblClick" => "",
        #     "accion" => "",
        #     "drawLat" => 39.57543616,
        #     "realLat" => 39.57543616,
        #     "alia" => "[63] PL. DESPANYA",
        #     "id" => "123",
        #     "picPath" => "img/icon/type.401.401001.png",
        #     "drawPxDispY" => 0,
        #     "picWidth" => 41,
        #     "drawPxDispX" => 0,
        #     "realLon" => 2.654550076,
        #     "title" => "[63] PL. DESPANYA",
        #     "paramsHtml" => "   <div id=\"popParam\" height=\"176\"  width=\"240\"  style=\"width: 240px;\">
        #                             <img id=\"img_123\" src=\"http://83.36.51.60:8080/eTraffic3/imagePIU/PIU123.jpg?time=1441837426559\"  height=\"176\"  width=\"240\">
        #                         </div>
        #                         <div id=\"popParam\"  style=\"width: 200px;\">
        #                             <span class=\"popParam\">Bicis Averiadas:</span> 0
        #                         </div>
        #                         <div id=\"popParam\"  style=\"width: 200px;\">
        #                             <span class=\"popParam\">Bicis Libres:</span> 0
        #                         </div><div id=\"popParam\"  style=\"width: 200px;\">
        #                             <span class=\"popParam\">Anclajes Usados:</span> 0
        #                         </div>
        #                         <div id=\"popParam\"  style=\"width: 200px;\">
        #                             <span class=\"popParam\">Anclajes Averiados:</span> 0 
        #                         </div>
        #                         <div id=\"popParam\"  style=\"width: 200px;\">
        #                             <span class=\"popParam\">Anclajes Libres:</span> 30 
        #                         </div>",
        #     "style" => {},
        #     "picHeigth" => 32,
        #     "zoomMaxi" => 100,
        #     "drawLon" => 2.654550076,
        #     "offset" => "-8,-32",
        #     "zoomMin" => 0,
        #     "titleHTML" => ...
        # }
        stations = []
        markers.each do |marker|
            name        = marker['title']
            latitude    = marker['realLat']
            longitude   = marker['realLon']
            info_html   = marker['paramsHtml']
            info_html.scan(INFO_RGX).each do |info|
                bikes, free = info
                station = BiciPalmaStation.new(name, latitude, longitude, bikes, free)
                stations << station
            end
        end
        @stations = stations
    end
end

class BiciPalmaStation < BikeShareStation
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
    instance = {
        "tag" => "bicipalma", 
        "meta" => {
            "latitude" => 39.57119, 
            "city" => "Palma", 
            "name" => "Bicipalma", 
            "longitude" => 2.646634, 
            "country" => "ES"
        }
    }
    bikeu = BiciPalma.new(instance)
    bikeu.update
    puts bikeu.stations.length
    bikeu.stations.each do |station|
        puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}"
    end
end