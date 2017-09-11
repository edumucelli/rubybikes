require 'minitest/autorun'
require 'rubybikes'

class RubyBikesTest < Minitest::Test

    def setup
        @rubybikes = RubyBikes.new
    end
  
    def test_adcb_has_at_least_one_station
        adcb_instances = @rubybikes.get({'label' => 'AdcbBikeshare'})
        adcb_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0
        end
    end

    def test_bcycle_has_at_least_one_station
        bcycle_instances = @rubybikes.get({'label' => 'BCycle'})
        bcycle_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bicincitta_has_at_least_one_station
        bicincitta_instances = @rubybikes.get({'label' => 'Bicincitta'})
        bicincitta_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bicincitta_has_at_least_one_station
        bicincitta_instances = @rubybikes.get({'label' => 'Bicincitta'})
        bicincitta_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bicipalma_has_at_least_one_station
        bicipalma_instances = @rubybikes.get({'label' => 'BiciPalma'})
        bicipalma_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bikeandroll_has_at_least_one_station
        bikeandroll_instances = @rubybikes.get({'label' => 'Bike and Roll'})
        bikeandroll_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bikeshareie_has_at_least_one_station
        bikeshareie_instances = @rubybikes.get({'label' => 'BikeshareIE'})
        bikeshareie_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bikeu_has_at_least_one_station
        bikeu_instances = @rubybikes.get({'label' => 'Bikeu'})
        bikeu_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_bixi_has_at_least_one_station
        bixi_instances = @rubybikes.get({'label' => 'Bixi'})
        bixi_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    def test_opensourcebikeshare_has_at_least_one_station
        opensourcebikeshare_instances = @rubybikes.get({'label' => 'OpenSourceBikeShare'})
        opensourcebikeshare_instances.each do |instance|
            instance.update
            assert instance.stations.length > 0, "Failed for #{instance.meta}"
        end
    end

    # def test_callabike_has_at_least_one_station
    #     callabike_instances = @rubybikes.get({'label' => 'Call-A-Bike'})
    #     callabike_instances.each do |instance|
    #         instance.update
    #         assert instance.stations.length > 0, "Failed for #{instance.meta}"
    #     end
    # end

    # def test_baksi_has_at_least_one_station
        
    #     baksi_antalya = @rubybikes.get({'tag' => 'baksi-istanbul'})
    #     baksi_antalya.update
    #     # baksi_instances = bikes.get({'label' => 'Baksi'})
    #     # baksi_instances.each do |instance|
    #     #     instance.update
    #     #     # assert instance.stations.length > 0
    #     # end
    # end

end