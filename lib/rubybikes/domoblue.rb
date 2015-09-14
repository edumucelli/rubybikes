# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' domoblue.py
# Distributed under the AGPL license, see LICENSE.txt

require 'rexml/document'

require_relative 'base'
require_relative 'utils'

BASE_URL = "http://clientes.domoblue.es/onroll/"
TOKEN_RGX = /generaXml\.php\?token=(.*?)\&/

class Domoblue < BikeShareSystem

    attr_accessor :stations, :meta

    def initialize(schema_instance_parameters={})
        tag         = schema_instance_parameters.fetch('tag')
        meta        = schema_instance_parameters.fetch('meta')
        @system_id  = schema_instance_parameters.fetch('system_id')
        @token_url  = BASE_URL + "generaMapa.php?cliente=%{system_id}&ancho=500&alto=700" % {:system_id => @system_id}
        @meta     = meta.merge({'company' => 'Domoblue'})
        super(tag, @meta)
    end
    def update
        scraper = Scraper.new(headers={'User-Agent' => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36
                                                        (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36"})

        html = scraper.request(@token_url)
        token = html.scan(TOKEN_RGX)[0][0]
        scraper.headers['Referer'] = @token_url
        xml_url = BASE_URL + "generaXml.php?token=%{token}&cliente=%{system_id}" % {:token => token, :system_id => @system_id}
        raw_xml = scraper.request(xml_url)
        xml = REXML::Document.new(raw_xml)
        # <markers>
        #     <infoSistema nombreEvento="ACTUALIZACION" inicioEvento="01/01 a las 00:00" finEvento="31/12 a las 23:59" />
        #     <marker nombre="AULARIO UNIVERSIDAD" candadosLibres="10" estado="17" bicicletas="0" lat="38.980157" lng="-1.856823" />
        #     <marker nombre="AVENIDA DE ESPAÑA" candadosLibres="10" estado="17" bicicletas="0" lat="38.986192" lng="-1.854045" />
        #     <marker nombre="I. MUNICIPAL DE DEPORTES" candadosLibres="10" estado="17" bicicletas="0" lat="38.979603" lng="-1.852836" />
        #     <marker nombre="LA PULGOSA" candadosLibres="10" estado="17" bicicletas="0" lat="38.965202" lng="-1.866303" />
        #     <marker nombre="PARQUE ABELARDO SÁNCHEZ" candadosLibres="10" estado="17" bicicletas="0" lat="38.989565" lng="-1.856283" />
        #     <marker nombre="PARQUE FIESTA DEL ÁRBOL" candadosLibres="10" estado="17" bicicletas="0" lat="39.000706" lng="-1.875631" />
        #     <marker nombre="PASEO DE LA CUBA" candadosLibres="10" estado="17" bicicletas="0" lat="39.004708" lng="-1.859562" />
        #     <marker nombre="PLAZA ALTOZANO" candadosLibres="10" estado="17" bicicletas="0" lat="38.995056" lng="-1.854443" />
        #     <marker nombre="POSADA DEL ROSARIO" candadosLibres="10" estado="17" bicicletas="0" lat="38.992994" lng="-1.857126" />
        #     <marker nombre="SEMBRADOR" candadosLibres="10" estado="17" bicicletas="0" lat="38.997114" lng="-1.851796" />
        # </markers>
        stations = []
        xml.elements.each('//marker') do |marker|
            name        = marker.attributes['nombre'].split.map(&:capitalize).join(' ') # POSADA DEL ROSARIO => Posada Del Rosario
            latitude    = marker.attributes['lat'].to_f
            longitude   = marker.attributes['lng'].to_f
            bikes       = marker.attributes['bicicletas'].to_i
            free        = marker.attributes['candadosLibres'].to_i
            station     = DomoblueStation.new(name, latitude, longitude, bikes, free)
            stations << station
        end
        @stations = stations
    end
end

class DomoblueStation < BikeShareStation
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
    require 'json'
    JSON.parse(File.read('./schemas/domoblue.json'))['instances'].each do |instance|
        domoblue = Domoblue.new(instance)
        puts domoblue.meta
        domoblue.update
        puts domoblue.stations.length
        domoblue.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
        end
    end
end