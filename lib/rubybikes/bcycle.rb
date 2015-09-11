# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require_relative 'base'
require_relative 'utils'

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

class BCycle < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url  = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'label' => 'B-cycle', 'company' => ['Trek Bicycle Corporation', 'Humana', 'Crispin Porter + Bogusky']})
        super(tag, @meta)
    end
    def update
        scraper = Scraper.new(headers={'User-Agent' => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36
                                                        (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36"})

        html = scraper.request(@feed_url)
        points = html.scan(LAT_LNG_RGX)
        data = html.scan(DATA_RGX)
        points.zip(data).each do |point, info|
            name, address, bikes, free = info
            if name.downcase == 'purgatory'
                next
            end
            latitude, longitude = point
            station = BCycleStation.new(name, latitude.to_f, longitude.to_f, bikes.to_i, free.to_i)
            stations << station
        end
        @stations = stations
    end
end

class BCycleStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, free)
        super()
        @name      = name
        @latitude  = latitude
        @longitude = longitude
        @bikes     = bikes
        @free      = free
    end
end

schema_instance_parameters = {
    "tag" => "indiana-pacers-bikeshare",
    "meta" => {
        "latitude" => 39.791,
        "city" => "Indianapolis, IN",
        "name" => "Indiana Pacers Bikeshare",
        "longitude" => -86.148,
        "country" => "US"
    },
    "feed_url" => "https://www.pacersbikeshare.org/station-map"
}

bcycle = BCycle.new(schema_instance_parameters)
bcycle.update
puts bcycle.stations.length
bcycle.stations.each do |station|
    puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
end