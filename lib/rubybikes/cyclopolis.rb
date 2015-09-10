# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require_relative 'base'
require_relative 'utils'

LAT_LNG_RGX = /latLng:\[([-+]?\d+.\d+).*?([-+]?\d+.\d+)\]/
DATA_RGX = /data\:.*?<span.*?>(.*?)<\/span>/

# In some systems, e.g., maroussi, nafplio, stations come as:
# { 
#   latLng: [37.5639397319061000, 22.8093402871746000],
#   data: "<div style='line-height:1.35;overflow:hidden;white-space:nowrap;'>
#              <span style='color:#333333'>
#                 <b>ETHNOSINELFSIS SQUARE<br/>available bikes: n/a</b>
#                 <br/>capacity: 32<br/>free:n/a<br/>offline
#              </span>
#          </div>",
#   options: {
#     icon: "http://nafplio.cyclopolis.gr//images/markers/red-03.png"
#   }
# }
# In other systems, e.g., aigialeia, it is shorter, there is no 'div' tag:
# data:"<span style='color:#333333'>
#     <b>ΨΗΛΑ ΑΛΩΝΙΑ</b>
#     <br/>χωρητικοτητα: 16<br/>ελεύθερες θεσεις:n/a<br/>offline
# </span>"

class Cyclopolis < BikeShareSystem
    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag       = schema_instance_parameters.fetch('tag')
        meta      = schema_instance_parameters.fetch('meta')
        feed_url  = schema_instance_parameters.fetch('feed_url')
        @meta     = meta.merge({'label' => 'Cyclopolis', 'company' => 'Cyclopolis Systems'})
        super(tag, @meta)
        @feed_url = feed_url
    end
    def update
        stations = []
        scraper = Scraper.new()
        
        html = scraper.request(@feed_url)
        
        points = html.scan(LAT_LNG_RGX)
        data   = html.scan(DATA_RGX)
        points.zip(data).each do |point, info|
            latitude, longitude = point
            fields = info[0].gsub('<b>','').gsub('</b>','').split('<br/>')
            extra = {}
            if fields.length == 4      # there is not slots information available
                name, raw_bikes, raw_free, status = fields
            else
                name, raw_bikes, raw_slots, raw_free, status = fields
                slots = raw_slots.split(':').last.to_i
                extra['slots'] = slots
            end
            # In some circumstances, e.g., station is offline,
            # the number of 'bikes' and/or 'free' is 'n/a'
            # Ruby's to_i will cast such values to 0, just perfect
            bikes = raw_bikes.split(':').last.to_i
            free = raw_free.split(':').last.to_i
            if status == 'offline'
                extra['closed'] = true
            end
            station = CyclopolisStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
    end
end
    
class CyclopolisStation < BikeShareStation
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
    JSON.parse(File.read('./schemas/cyclopolis.json'))['instances'].each do |instance|
        cyclopolis = Cyclopolis.new(instance)
        cyclopolis.update
        puts cyclopolis.stations.length
        cyclopolis.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
        end
    end
end