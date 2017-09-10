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

    def test_bicincitta_has_at_least_one_station
        bikes = RubyBikes.new
        bicincitta_instances = bikes.get({'label' => 'Bicincitta'})
        bicincitta_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bicipalma_has_at_least_one_station
        bikes = RubyBikes.new
        bicipalma_instances = bikes.get({'label' => 'BiciPalma'})
        bicipalma_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bikeandroll_has_at_least_one_station
        bikes = RubyBikes.new
        bikeandroll_instances = bikes.get({'label' => 'Bike and Roll'})
        bikeandroll_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bikeshareie_has_at_least_one_station
        bikes = RubyBikes.new
        bikeshareie_instances = bikes.get({'label' => 'BikeshareIE'})
        bikeshareie_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bikeu_has_at_least_one_station
        bikes = RubyBikes.new
        bikeu_instances = bikes.get({'label' => 'Bikeu'})
        bikeu_instances.each do |instance|
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