# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

require_relative 'base'
require_relative 'utils'

# Each station is formatted as:
# {
#     u 'code': u '036', 
#     u 'is_deleted': 0,
#     u 'name': u ' Hotel "Diplomat"  ',
#     u 'photo': None,
#     u 'is_sales': 0,
#     u 'avl_bikes': 1,
#     u 'free_slots': 7,
#     u 'address': u '\u041d\u0430 
#                     \u043f\u0435\u0440\u0435\u0441\u0435\u0447\u0435\u043d\u0438\u0438
#                     \u0443\u043b.
#                     \u0410\u043a\u043c\u0435\u0448\u0435\u0442\u044c,
#                     \u0443\u043b.\u041a\u0443\u043d\u0430\u0435\u0432\u0430.',
#     u 'lat': u '51.130769',
#     u 'lng': u '71.429361',
#     u 'total_slots': 8,
#     u 'id': 41,
#     u 'is_not_active': 0,
#     u 'desc': u ''
# }

class Velobike < BikeShareSystem

    attr_accessor :stations, :meta
    def initialize(schema_instance_parameters={})
        tag         = schema_instance_parameters.fetch('tag')
        meta        = schema_instance_parameters.fetch('meta')
        @feed_url   = schema_instance_parameters.fetch('feed_url')
        @meta       = meta.merge({
                                    'label' => 'Velobike',
                                    'company' => ['Agency for Physical Culture and Sports of \
                                                the Republic of Kazakhstan', 
                                                'Sovereign Wealth Fund "Samruk-Kazyna" JSC',
                                                'Akimat of Astana', 'Smoove']
                                })
        super(tag, @meta)
    end
    def update
        scraper = Scraper.new()
        data = JSON.parse(scraper.request(@feed_url))
        stations = []
        data['data'].each do |station|
            # Discard stations as VeloBike's 'Sales Department', which
            # does not have information about available bikes:
            # {
            #     "id":48,"code":"sales1","name":"Sales Department",
            #     "lat":"51.145528","lng":"71.413569","photo":null,
            #     "desc":"","total_slots":null,"free_slots":null,
            #     "address":"Astana city, Mega mart 2nd floor, 
            #                             Qurghalzhyn Highway 1",
            #     "avl_bikes":null,"is_deleted":0,"is_sales":1,"is_not_active":0
            # }
            bikes = station['avl_bikes']
            unless bikes
                next
            end
            name = station['name']
            latitude = station['lat'].to_f
            longitude = station['lng'].to_f
            free = station['free_slots'].to_i
            extra = {
                'slots' => station['total_slots'].to_i,
                'address' => station['address'],
                'closed' => station['is_not_active'].zero?
            }
            station = VelobikeStation.new(name, latitude, longitude, bikes, free, extra)
            stations << station
        end
        @stations = stations
    end
end

class VelobikeStation < BikeShareStation
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
    JSON.parse(File.read('./schemas/velobike.json'))['instances'].each do |instance|
        velobike = Velobike.new(instance)
        puts velobike.meta
        velobike.update
        puts velobike.stations.length
        velobike.stations.each do |station|
            puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.timestamp}"
        end
    end
end