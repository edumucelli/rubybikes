# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' bicincitta.py
# Distributed under the AGPL license, see LICENSE.txt

require_relative 'base'
require_relative 'utils'

META = {'system' => 'Bicincittà', 'company' => 'Comunicare S.r.l.'}

class BicincittaOld < BikeShareSystem

    # This is the one of worst things ever made in the computer history, it is 
    # impossible to believe that someone had this idea of representing the latitudes, 
    # longitudes, names, and availability with a string separated by '_'.
    # Furthermore, look at this string "1000000000xxxxxxxxxxxxxxxxxxxx" and tell me how
    # many available bike stands this station has. Who had the brilliant
    # idea to model the number of zeros as the number of available stands?
    # Thanks to eskerda that figured that out.

    # One caveat here in this mess is that the values after the '+'
    # point to parameters of a bike stand in Rome, which has no relation with
    # each of the cities whatsoever! I wonder what they mean with that. Besides,
    # if you go on the Google Street View and check that position (41.900074, 12.476478),
    # that is close by a statue in Rome, which probaly names the stand in the system, 'Maddalena'.
    # Still, there is no bike station there! I am pretty sure this is some kind of voodoo-like
    # thing made by the (sic) programmer who made this shi...bicincitta.
    # Imagine, for all the cities, even the most countryside one, includes the same bike stand in Rome!

    # I've discovered that when I've seen lots of stations with the same hash.
    # Previously (well, it is pending my pull-request to PyBikes), the get_hash
    # method considered only latitude and longitude. As I've included the name on
    # that I thought that no bike stand would ever have the same name, latitude and longitude
    # parameters. Then this 'Maddalena' appeared like that! Different cities, but the same
    # station. On the map it is possible to see that the location has nothing to do
    # with the rest of the bike stands from the respective city.

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

class Bicincitta < BikeShareSystem

    INFO_RGX    = /RefreshMap\('(.*?)'\)\}/
    URL         = "http://bicincitta.tobike.it/frmLeStazioni.aspx?ID=%{id}"

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        if schema_instance_parameters.has_key? 'comunes'
            @feed_url = schema_instance_parameters['comunes'].map {|comune| URL % {:id => comune['id']}}
        else
            @feed_url = schema_instance_parameters.fetch('feed_url')
        end
        puts @feed_url
        @meta     = meta.merge(META)
        super(tag, @meta)
    end
    def update
        scraper = Scraper.new()
        stations = []
        if @feed_url.is_a? String
            html = scraper.request(@feed_url)
            @stations = process_stations(html)
        else
            @feed_url.each do |url|
                html = scraper.request(url)
                @stations.push(*process_stations(html))
            end
        end
    end
    def process_stations(html)
        stations = []
        html.scan(INFO_RGX).each do |info|
            mess = info[0].split("\',\'")
            latitudes = mess[3].split('|')
            longitudes = mess[4].split('|')
            names = mess[5].split(':|')
            availabilities = mess[6].split('|')
            names.zip(latitudes, longitudes, availabilities).each do |name, latitude, longitude, availability|
                bikes = availability.count('4')
                free = availability.count('0')
                station = BicincittaStation.new(name, latitude.to_f, longitude.to_f, bikes, free)
                stations << station
            end
        end
        stations
    end
end
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
                    "comunes" => [
                        {
                            "id" => 22,
                            "name" => "Torino"
                        },
                        {
                            "id" => 61,
                            "name" => "Grugliasco"
                        },
                        {
                            "id" => 62,
                            "name" => "Collegno"
                        },
                        {
                            "id" => 63,
                            "name" => "Venaria Reale"
                        },
                        {
                            "id" => 64,
                            "name" => "Alpignano"
                        },
                        {
                            "id" => 65,
                            "name" => "Druento"
                        }
                    ],
                    "meta" => {
                        "latitude" => 45.07098200000001,
                        "city" => "Torino",
                        "name" => "[TO]BIKE",
                        "longitude" => 7.685676,
                        "country" => "IT"
                    },
                    "feed_url" => "http://www.tobike.it/frmLeStazioni.aspx?ID={id}",
                    "tag" => "to-bike"
    }
    cyclocity = Bicincitta.new(instance)
    cyclocity.update
    puts cyclocity.stations.length
    cyclocity.stations.each do |station|
        puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
    end
end