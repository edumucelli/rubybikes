# encoding: utf-8
# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'


class OpenSourceBikeShare < BikeShareSystem

    attr_accessor :stations, :meta

    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        @feed_url = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'company' => 'Open Source Bike Share'})
        super(tag, @meta)
    end

    def update(scraper = nil)
        unless scraper
            scraper = Scraper.new
        end

        stations = []

        data = JSON.parse(scraper.request(@feed_url))

        data.each do |station|
            longitude = station['lon'].to_f
            latitude = station['lat'].to_f

            name = station['standName']
            free = nil
            bikes = station['bikecount'].to_i

            extra = {
                'photo' => station['standPhoto'],
                'description' => station['standDescription'],
                'uid' => station['standId'].to_i
            }

            station = OpenSourceBikeShareStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end

        @stations = stations
    end

end

class OpenSourceBikeShareStation < BikeShareStation
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