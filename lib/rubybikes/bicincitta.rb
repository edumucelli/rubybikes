# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Inspired on PyBikes' bicincitta.py
# Distributed under the AGPL license, see LICENSE.txt

require_relative 'base'
require_relative 'utils'

META = {'company' => 'Comunicare S.r.l.'}

class Bicincitta < BikeShareSystem

    INFO_RGX    = /RefreshMap\('(.*?)'\)\}/

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url  = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge(META)
        super(tag, @meta)
    end

    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end

        unless @feed_url.instance_of?(Array)
            @feed_url = [@feed_url]
        end

        @feed_url.each do |url|
            html = scraper.request(url)
            @stations.push(*process_stations(html))
        end
    end

    def process_stations(html)
        stations = []
        
        info = html.scan(INFO_RGX)[0]
        mess = info[0].split("\',\'")
        latitudes = mess[3].split('|')
        longitudes = mess[4].split('|')
        names = mess[5].gsub(':', '').split('|')
        availabilities = mess[6].split('|')
        operation_statuses = mess[8].split('|')
        
        names.zip(latitudes, longitudes, availabilities, operation_statuses).each do |name, latitude, longitude, availability, operation_status|
            bikes = availability.count('4')
            free = availability.count('0')
            extra = {
                'closed' => operation_status != '0'
            }
            station = BicincittaStation.new(name, latitude.to_f, longitude.to_f, bikes, free, extra)
            stations << station
        end
        
        stations
    end
end

class BicincittaStation < BikeShareStation
    def initialize(name, latitude, longitude, bikes, free, extra={})
        super()
        @name       = name
        @latitude   = latitude
        @longitude  = longitude
        @bikes      = bikes
        @free       = free
        @extra      = extra
    end
end