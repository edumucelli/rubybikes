# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' smartbike.py (mainly the messy double encoded JSON, damn it!)
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

class SmartBike < BikeShareSystem

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('feed_url')
        @format = schema_instance_parameters.fetch('format')
        @meta     = meta.merge({'company' => 'ClearChannel'})
        super(tag, @meta)
    end

    def update
        stations = []
        scraper = Scraper.new()
        data = JSON.parse(scraper.request(@feed_url))
        if @format == "json_v1"
            # {"StationID":"1",
            # "DisctrictCode":"1",
            # "AddressGmapsLongitude":"-0.90466700000000000",
            # "AddressGmapsLatitude":"41.67046400000000000",
            # "StationAvailableBikes":"11",
            # "StationFreeSlot":"13",
            # "AddressZipCode":"11111",
            # "AddressStreet1":"Avda. Pablo Ruiz Picasso - Torre del Agua",
            # "AddressNumber":"0",
            # "NearbyStationList":"2,3,69",
            # "StationStatusCode":"OPN",
            # "StationName":"1 - Avda. Pablo Ruiz Picasso - Torre del Agua"}
            # Double-encoded JSON, that is nasty and messed up!
            JSON.parse(data[1]['data']).each do |info|
                name = info['StationName']
                latitude = info['AddressGmapsLatitude'].to_f
                longitude = info['AddressGmapsLongitude'].to_f
                bikes = info['StationAvailableBikes'].to_i
                free = info['StationFreeSlot']
                extra = {'address' => "#{info['AddressStreet1']}, #{info['AddressNumber']}"}
                station = SmartBikeStation.new(name, latitude, longitude, bikes, free, extra)
                stations << station
            end
        else
            # {"id"=>"488",
            # "district"=>"10",
            # "lon"=>"2.184391",
            # "lat"=>"41.423976",
            # "bikes"=>"7",
            # "slots"=>"5",
            # "zip"=>"08027",
            # "address"=>"(PK) C/ DE CIENFUEGOS",
            # "addressNumber"=>"13",
            # "nearbyStations"=>"464,468",
            # "status"=>"OPN",
            # "name"=>"488 - (PK) C/ DE CIENFUEGOS, 13",
            # "stationType"=>"ELECTRIC_BIKE"}
            data.each do |info|
                name = info['name']
                latitude = info['lat'].to_f
                longitude = info['lon'].to_f
                bikes = info['bikes'].to_i
                free = info['slots']
                extra = {'address' => "#{info['address']}, #{info['addressNumber']}"}
                station = SmartBikeStation.new(name, latitude, longitude, bikes, free, extra)
                stations << station
            end
        end
        @stations = stations
    end
end

class SmartBikeStation < BikeShareStation
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
    JSON.parse(File.read('./schemas/smartbike.json'))['class']['SmartBike']['instances'].each do |instance|
    # JSON.parse(File.read('./schemas/samba.json'))['class']['SambaNew']['instances'].each do |instance|
        smartbike = SmartBike.new(instance)
        # smartbike = smartbikeNew.new(instance)
        puts smartbike.meta
        smartbike.update
        puts smartbike.stations.length
        smartbike.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}, #{station.extra}"
        end
    end
end

# class SmartShitty(BaseSystem):
#     """
#     BikeMI decided to implement yet another way of displaying the map...
#     So, I guess what we will do here is using a regular expression to get the
#     info inside the $create function, and then load that as a JSON. Who the
#     fuck pay this guys money, seriously?

#     <script type="text/javascript">
#     //<![CDATA[
#     Sys.Application.add_init(function() {
#         $create(Artem.Google.MarkersBehavior, {
#             "markerOptions":[
#                 {
#                     "clickable":true,
#                     "icon":{
#                         ...
#                     },
#                     "optimized":true,
#                     "position":{
#                         "lat":45.464683238625966,
#                         "lng":9.18879747390747
#                     },
#                     "raiseOnDrag":true,
#                     "title":"01 - Duomo",    _____ Thank you...
#                     "visible":true,         /
#                     "info":"<div style=\"width: 240px; height: 100px;\">
#                                 <span style=\"font-weight: bold;\">
#                                     01 - Duomo
#                                 </span>
#                                 <br/>
#                                 <ul>
#                                     <li>Available bicycles: 17</li>
#                                     <li>Available electrical bicycles: 0</li>
#                                     <li>Available slots: 7</li>
#                                 </ul>
#                             </div>
#                 }, ...
#             ],
#             "name": "fuckeduplongstring"
#         }, null, null, $get("station-map"));
#     })
#     """
#     sync = True

#     _RE_MARKERS = 'Google\.MarkersBehavior\,\ (?P<data>.*?)\,\ null'

#     def __init__(self, tag, meta, feed_url):
#         super(SmartShitty, self).__init__(tag, meta)
#         self.feed_url = feed_url

#     def update(self, scraper=None):
#         if scraper is None:
#             scraper = utils.PyBikesScraper()

#         page = scraper.request(self.feed_url)
#         markers = json.loads(
#             re.search(SmartShitty._RE_MARKERS, page).group('data')
#         )['markerOptions']
#         self.stations = map(SmartShittyStation, markers)


# class SmartShittyStation(BikeShareStation):
#     def __init__(self, marker):
#         super(SmartShittyStation, self).__init__()
#         avail_soup = html.fromstring(marker['info'])
#         availability = map(
#             lambda x: int(x.split(':')[1]),
#             avail_soup.xpath("//div/ul/li/text()")
#         )
#         self.name = marker['title']
#         self.latitude = marker['position']['lat']
#         self.longitude = marker['position']['lng']
#         self.bikes = availability[0] + availability[1]
#         self.free = availability[2]
#         self.extra = {}
#         if availability[1] > 0:
#             self.extra['has_ebikes'] = True
#             self.extra['ebikes'] = availability[1]