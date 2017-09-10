require 'minitest/autorun'
require 'rubybikes'

class RubyBikesTest < Minitest::Test
  
    def test_adcb_has_at_least_one_station
        bikes = RubyBikes.new
        adcb_instances = bikes.get({'label' => 'AdcbBikeshare'})
        adcb_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0
        end
    end

    def test_bcycle_has_at_least_one_station
        bikes = RubyBikes.new
        bcycle_instances = bikes.get({'label' => 'BCycle'})
        bcycle_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bicincitta_has_at_least_one_station
        bikes = RubyBikes.new
        bicincitta_instances = bikes.get({'label' => 'Bicincitta'})
        bicincitta_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    # def test_baksi_has_at_least_one_station
    #     bikes = RubyBikes.new
        
    #     baksi_antalya = bikes.get({'tag' => 'baksi-istanbul'})
    #     baksi_antalya.update
    #     # baksi_instances = bikes.get({'label' => 'Baksi'})
    #     # baksi_instances.each do |instance|
    #     #     instance.update
    #     #     # assert instance.stations.length > 0
    #     # end
    # end

end