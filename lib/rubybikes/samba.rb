# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36"
META = {'system' => 'Samba', 'company' => ['Mobilicidade Tecnologia LTD', 'Grupo Serttel LTDA']}

class Samba < BikeShareSystem

    STATIONS_RGX = /exibirEstacaMapa\(([-+]?\d+.\d+),.*?([-+]?\d+.\d+),.*?,(.*?),.*?,(.*?),(.*?),(\d+),(\d+),(.*?),.*?\)\;/
    # exibirEstacaMapa("-23.554580", 
    # "-46.691360", 
    # "img/icone-estacoes.gif", <= Discarded
    # "Fidalga",
    # "278",                    <= Discarded
    # "A",
    # "EO",
    # "1",
    # "12",
    # "Rua Fidalga, 603 / Esquina Rua Purpurina");
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag         = schema_instance_parameters.fetch('tag')
        meta        = schema_instance_parameters.fetch('meta')
        @feed_url   = schema_instance_parameters.fetch('feed_url')
        @meta       = meta.merge(META)
        super(tag, @meta)
    end
    def update
        scraper = Scraper.new(headers={'User-Agent' => USER_AGENT})
        html = scraper.request(@feed_url)
        html.gsub!(/\r\n|\r/, '').gsub!('"','')
        @stations = html.scan(STATIONS_RGX).map do |info|
            latitude, longitude, name, online_status, operation_status, bikes, slots, address = info
            slots = slots.to_i
            bikes = bikes.to_i
            extra = {'address' => address, 'closed' => !(online_status == 'A' && operation_status == 'EO'), 'slots' => slots}
            free = slots - bikes
            SambaStation.new(name, latitude.to_f, longitude.to_f, bikes, free, extra)
         end
    end
end

class SambaNew < BikeShareSystem

    STATIONS_RGX = /\['(.*?)'\s*,\s*([-+]?\d+.\d+)\s*,\s*([-+]?\d+.\d+)\s*,\s*'(.*?)','.*?','(.*?)','(.*?)',.*?,'(\d+)','(\d+)'.*?\]/

    # Different from the original Samba class, the new one deals
    # with stations' information in the following format:
    # [(0) name, (1) latitude, (2) longitude, (3) address,
    # (4) address main line, (5) onlineStatus, (6) operationStatus,
    # (7) available bikes (variable not being used in their code)
    # (8) available bikes, (9) available bike stands,
    # (10) internal station status, (11) path to image file, (12) stationId]

    # ['Rotary',
    # -10.987263,
    # -37.051898,
    # 'Avenida Rotary oposto ao Terminal Atalaia / Esquina Avenida Des. João Bosco de Andrade Lima',
    # '',                       <= Discarded
    # 'A',
    # 'EO',
    # '12',                     <= Discarded (not used in the scrapped page's source code)
    # '12',
    # '0',                      <= Discarded
    # 'Est_Cheia 0',            <= Discarded
    # 'img/estacaovazia.png',1  <= Discarded
    # ]

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag         = schema_instance_parameters.fetch('tag')
        meta        = schema_instance_parameters.fetch('meta')
        @feed_url   = schema_instance_parameters.fetch('feed_url')
        @meta       = meta.merge(META)
        super(tag, @meta)
    end

    def update
        scraper = Scraper.new(headers={'User-Agent' => USER_AGENT})
        html = scraper.request(@feed_url)
        @stations = html.scan(STATIONS_RGX).map do |info|
            name, latitude, longitude, address, online_status, operation_status, bikes, free = info
            extra = {'address' => address, 'closed' => !(online_status == 'A' && operation_status == 'EO')}
            SambaStation.new(name, latitude.to_f, longitude.to_f, bikes.to_i, free.to_i, extra)
        end
    end
end

class SambaStation < BikeShareStation
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
    JSON.parse(File.read('./schemas/samba.json'))['class']['Samba']['instances'].each do |instance|
    # JSON.parse(File.read('./schemas/samba.json'))['class']['SambaNew']['instances'].each do |instance|
        samba = Samba.new(instance)
        # samba = SambaNew.new(instance)
        puts samba.meta
        samba.update
        puts samba.stations.length
        samba.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
        end
    end
end