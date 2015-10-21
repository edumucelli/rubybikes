# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'rexml/document'

require_relative 'base'
require_relative 'utils'

class EcobiciBuenosAires < BikeShareSystem

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag         = schema_instance_parameters.fetch('tag')
        meta        = schema_instance_parameters.fetch('meta')
        @feed_url   = schema_instance_parameters.fetch('feed_url')
        @meta       = meta.merge({  'company' => 'Buenos Aires Ciudad',
                                    'license' => {
                                        'name' => 'Terms of Service',
                                        'url' => 'http://data.buenosaires.gob.ar/tyc'}})
        super(tag, @meta)
    end

    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end
        data = scraper.request(@feed_url)
        xml = REXML::Document.new(data)
        stations = []
        xml.elements.each('//Estacion') do |station|
            name = station.elements['EstacionNombre'].text
            latitude = station.elements['Latitud'].text.to_f
            longitude = station.elements['Longitud'].text.to_f
            bikes = station.elements['BicicletaDisponibles'].text.to_i
            free = station.elements['AnclajesDisponibles'].text.to_i
            address = station.elements['Lugar'].text
            slots = station.elements['AnclajesTotales'].text.to_i
            closed = station.elements['EstacionDisponible'].text != 'SI'
            extra = {'address' => address, 'slots' => slots, 'closed' => closed}
            station = EcobiciBuenosAiresStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
    end
end

class EcobiciBuenosAiresStation < BikeShareStation
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
#     JSON.parse(File.read('./schemas/ecobici_buenos_aires.json'))['instances'].each do |instance|
#         ecobici_buenos_aires = EcobiciBuenosAires.new(instance)
#         puts ecobici_buenos_aires.meta
#         ecobici_buenos_aires.update
#         puts ecobici_buenos_aires.stations.length
#         ecobici_buenos_aires.stations.each do |station|
#             puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}, #{station.extra}"
#         end
#     end
# end