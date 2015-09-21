# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'rexml/document'

require_relative 'base'
require_relative 'utils'

class Keolis < BikeShareSystem

# "latitude": "43.305313",
# "longitude": "-0.351039",
# "text": "\x3cdiv class=\"gmap-popup\"\x3e\x3cdiv class=\"gmap-infobulle\"\x3e\n
#          \x3cdiv class=\"gmap-titre\"\x3e#17 - Allees\x3c/div\x3e\n
#          \x3cdiv class=\"gmap-adresse\"\x3eAVENUE DES LILAS FACE AU N 26 AVENUE DES LILAS\x3c/div\x3e\x3cdiv class=\"gmap-velos\"\x3e\n
#          \x3ctable\x3e\x3ctr\x3e\n
#          \x3ctd class=\"ok\"\x3e\x3cstrong\x3e12\x3c/strong\x3e vélos disponibles\x3c/td\x3e\n                \x3ctd class=\"ok\"\x3e\x3cstrong\x3e8\x3c/strong\x3e places disponibles\x3c/td\x3e\x3ctd\x3e\x3cacronym title=\"Carte Bancaire\"\x3eCB\x3c/acronym\x3e\x3c/td\x3e\x3c/tr\x3e\x3c/table\x3e\x3c/div\x3e\x3cdiv class=\"gmap-datemaj\"\x3edernière mise à jour il y a \x3cstrong\x3e00 min\x3c/strong\x3e  \x3c/div\x3e\n              \x3c/div\x3e\x3c/div\x3e",
# "markername": "vcub"

    STATIONS_RGX = /"latitude": "([-+]?\d+.\d+)",.*?"longitude": "([-+]?\d+.\d+)",.*?"text": "(.*?)",/
    TEXT_RGX = /.*?<div class="gmap-titre">(.*?)<\/div>.*?<div class="gmap-adresse">(.*?)<\/div>.*?<strong>(\d+)<\/strong>.*?<strong>(\d+)<\/strong>.*?/

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'company' => 'Keolis'})
        super(tag, @meta)
    end

    def update
        scraper = Scraper.new()
        html = scraper.request(@feed_url)
        stations = []
        html.scan(STATIONS_RGX).each do |data|
            latitude, longitude, raw_info = data
            # Format simple scaped html as proper HTML, CGI.unescapeHTML did not worked
            info_html = raw_info.gsub('\n','').gsub('\\x3c', '<').gsub('\\x3e', '>').gsub('\\','').squeeze(' ')
            info = info_html.scan(TEXT_RGX)
            # For some stations, there is not the complete set of fields, discard them
            if info[0]
                name, address, bikes, free = info[0]
                extra = {'address' => address}
                station = KeolisStation.new(name, latitude.to_f, longitude.to_f, bikes.to_i, free.to_i, extra)
                stations << station
            end
        end
        @stations = stations
    end
end

class KeolisNew < BikeShareSystem

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        feed_url  = schema_instance_parameters.fetch('feed_url')
        @list_url = feed_url    + '/stations/xml-stations.aspx'
        @station_url = feed_url + '/stations/xml-station.aspx?borne=%{id}'
        @meta     = meta.merge({'company' => 'Keolis'})
        super(tag, @meta)
    end

    def update
        stations = []
        scraper = Scraper.new()
        stations_raw_xml = scraper.request(@list_url).encode('utf-16')
        stations_xml = REXML::Document.new(stations_raw_xml)
        # <marker id="1" lat="50.6419" lng="3.07599" name="Lille Metropole" />
        stations_xml.elements.each('markers/marker') do |marker|
            name            = marker.attributes['name']
            latitude        = marker.attributes['lat'].to_f
            longitude       = marker.attributes['lng'].to_f
            id              = marker.attributes['id']
            station_raw_xml = scraper.request(@station_url % {:id => id})
            station_xml = REXML::Document.new(station_raw_xml)
            station_xml.elements.each('station') do |data|
                # <station>
                #   <adress>RUE DU PORT BD VAUBAN </adress>
                #   <status>0</status>
                #   <bikes>10</bikes>
                #   <attachs>21</attachs>
                #   <paiement>AVEC_TPE</paiement>
                #   <lastupd>57 secondes</lastupd>
                # </station>
                bikes = data.elements['bikes'].text.to_i
                free = data.elements['attachs'].text.to_i
                extra = {'address' => data.elements['adress'].text}
                station = KeolisStation.new(name, latitude, longitude, bikes, free, extra)
                stations << station
            end
        end
        @stations = stations
    end
end

class KeolisStation < BikeShareStation
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
#     require 'json'
#     JSON.parse(File.read('./schemas/keolis.json'))['class']['Keolis']['instances'].each do |instance|
#         keolis = Keolis.new(instance)
#         puts keolis.meta
#         keolis.update
#         puts keolis.stations.length
#         keolis.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
#         end
#     end
# end