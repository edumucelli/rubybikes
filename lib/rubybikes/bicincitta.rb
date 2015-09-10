# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' bicincitta.py
# Distributed under the AGPL license, see LICENSE.txt

require_relative 'base'
require_relative 'utils'

META = {'system' => 'Bicincittà', 'company' => 'Comunicare S.r.l.'}

class BicincittaOld < BikeShareSystem

    # This is the worst thing ever made, it is impossible to believe
    # that someone had this idea of representing the latitudes, longitudes
    # names, and availability with a string separated by '_'
    # Look at this string "1000000000xxxxxxxxxxxxxxxxxxxx" and tell me how
    # many available bike stands this station has. Who had the brilliant
    # idea to model the number of zeros as the number of available stands?
    # Thanks to eskerda that figured that out.

    # One caveat here in this mess is that the values after the '+'
    # point to parameters of a bike stand in Rome, which has no relation with
    # each of the cities whatsoever! I wonder what they mean with that. Besides,
    # If you go on the Google Street View and check that position (41.900074, 12.476478),
    # that is close by a statue in Rome, which probaly names the stand in the system, 'Maddalena'.
    # Still, there is no bike station there! I am pretty sure this is some kind of voodoo-like
    # thing made by the (sic) programmer who made this shi...bicincitta.
    # Imagine, for all the cities, even the most countryside one, includes the same bike stand in Rome!

    # I've discovered that when I've seen lots of stations with the same hash.
    # Previously (well, it is pending my pull-request to PyBikes), the get_hash
    # method considered only latitude and longitude. As I've included the name on
    # that I thought that no bike stand would ever have the same name, latitude and longitude
    # parameters. Then this 'Maddalena' appeared like that! On different cities the same
    # station, but on the map it is possible to see that the location has nothing to do
    # with the rest from the respective city.

    LAT_RGX         = /var sita_x =.*?\"(.*?)\"\+.*?;/
    LNG_RGX         = /var sita_y =.*?\"(.*?)\"\+.*?;/
    NAME_RGX        = /var sita_n =.*?\"(.*?)\"\+.*?;/
    AVAILABLE_RGX   = /var sita_b =.*?\"(.*?)\"\+.*?;/

    URL = "http://www.bicincitta.com/citta_v3.asp?id=%{id}&pag=2"

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag         = schema_instance_parameters.fetch('tag')
        meta        = schema_instance_parameters.fetch('meta')
        system_id   = schema_instance_parameters.fetch('system_id')
        @feed_url   = URL % {:id => system_id}
        @meta       = meta.merge(META)
        super(tag, @meta)
    end
    def update
        scraper = Scraper.new(headers={'User-Agent' => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36
                                                        (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36"})
        html = scraper.request(@feed_url)
        latitudes = html.scan(LAT_RGX)[0][0].split('_').map{ |latitude| latitude.to_f}
        longitudes = html.scan(LNG_RGX)[0][0].split('_').map{ |longitude| longitude.to_f}
        names = html.scan(NAME_RGX)[0][0].split('_')
        availability = html.scan(AVAILABLE_RGX)[0][0].split('_')
        stations = []
        names.zip(latitudes, longitudes, availability) do |name, latitude, longitude, availability|
            bikes = availability.count('4')
            free = availability.count('0')
            station = BicincittaStation.new(name, latitude, longitude, bikes, free)
            stations << station
        end
        @stations = stations
    end
end


# class Bicincitta(BikeShareSystem):
#     sync = True
#     _RE_INFO="RefreshMap\((.*?)\)\;"
#     _endpoint = "http://bicincitta.tobike.it/frmLeStazioni.aspx?ID={id}"

#     def __init__(self, tag, meta, ** instance):
#         super(Bicincitta, self).__init__(tag, meta)

#         if 'endpoint' in instance:
#             endpoint = instance['endpoint']
#         else:
#             endpoint = Bicincitta._endpoint

#         if 'system_id' in instance:
#             self.system_id = system_id
#             self.url = [endpoint.format(id = system_id)]
#         elif 'comunes' in instance:
#             self.url = map(
#                 lambda comune: endpoint.format(id = comune['id']),
#                 instance['comunes']
#             )
#         else:
#             self.url = [endpoint]


#     def update(self, scraper = None):
#         if scraper is None:
#             scraper = utils.PyBikesScraper()
#         self.stations = []
#         for url in self.url:
#             self.stations += Bicincitta._getComuneStations(url, scraper)

#     @staticmethod
#     def _getComuneStations(url, scraper):
#         data = scraper.request(url)
#         raw  = re.findall(Bicincitta._RE_INFO, data)
#         info = raw[0].split('\',\'')
#         info = map(lambda chunk: chunk.split('|'), info)
#         # Yes, this is a joke
#         return [ BicincittaStation(name, desc, float(lat), float(lng),
#                  stat.count('4'), stat.count('0')) for name, desc, lat, lng,
#                  stat in zip(info[5], info[7], info[3], info[4], info[6]) ]

class BicincittaStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, free)
        super()
        @name       = name
        @latitude   = latitude
        @longitude  = longitude
        @bikes      = bikes
        @free       = free
    end
end

if __FILE__ == $0
    instance = {
        "tag" => "alba",
        "system_id" => 15,
        "meta" => {
            "name" => "Alba",
            "city" => "Alba",
            "country" => "IT",
            "latitude" => 44.716667,
            "longitude" => 8.083333
        }
    }
    cyclocity = BicincittaOld.new(instance)
    cyclocity.update
    puts cyclocity.stations.length
    cyclocity.stations.each do |station|
        puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
    end
end