# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' ciclosampa.py
# Distributed under the GPL license, see LICENSE.txt

require_relative 'base'
require_relative 'utils'

DATA_RGX = /setEstacao\((.*?)\);/

class CicloSampa < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url  = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'label' => 'CicloSampa', 'company' => ['Bradesco Seguros']})
        super(tag, @meta)
    end

    def update
        stations = []
        scraper = Scraper.new(headers = {'User-Agent' => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36
                                                            (KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36"})
        html = scraper.request(@feed_url)
        html.gsub!('"','')
        html.scan(DATA_RGX).each do |data|
            latitude, longitude, id, name, address, bikes, free = data[0].split(',')
            extra = {'address' => address, 'uid' => id, 'slots' => bikes.to_i + free.to_i}
            station = CicloSampaStation.new(name, latitude.to_f, longitude.to_f, bikes.to_i, free.to_i, extra)
            stations << station
        end
        @stations = stations
    end
end

class CicloSampaStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, free, extra)
        super()
        @name        = name
        @latitude    = latitude
        @longitude   = longitude
        @bikes       = bikes
        @free        = free
        @extra       = extra
    end
end

instance = {
    "feed_url" => "http://www.ciclosampa.com.br/estacoes.php",
    "tag" => "ciclosampa",
    "meta" => {
        "latitude" => -23.55,
        "city" => "S\u00e3o Paulo",
        "name" => "CicloSampa",
        "longitude" => -46.6333,
        "country" => "BR"
    }
}

cyclosampa = CicloSampa.new(instance)
cyclosampa.update
puts cyclosampa.stations.length
cyclosampa.stations.each do |station|
    puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.extra}"
end