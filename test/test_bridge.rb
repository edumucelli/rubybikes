require 'minitest/autorun'
require 'tmpdir'
require 'rubybikes'

class RubyBikesBridgeTest < Minitest::Test
  def setup
    @factory = RubyBikes.new
  end
  def teardown
    @factory.close
  end
  def test_catalog_matches_the_pinned_engine
    assert_equal 815, @factory.tags.size
    assert_includes @factory.tags, 'velib'
    assert_includes @factory.labels, 'Gbfs'
    assert_equal 53, @factory.catalog.map { |row| row['meta']['country'] }.uniq.size
    assert_equal 81, @factory.catalog.map { |row| row['class'] }.uniq.size
    assert_equal RubyBikes::Engine::MANIFEST['revision'], @factory.engine_info['revision']
  end
  def test_every_catalogued_network_is_available_through_the_ruby_factory
    keys = {
      'bicimad' => { 'clientid' => 'fixture', 'passkey' => 'fixture' },
      'deutschebahn' => { 'client_id' => 'fixture', 'client_secret' => 'fixture' },
      'weelo' => { 'client_id' => 'fixture', 'client_secret' => 'fixture' }
    }
    @factory.catalog.each do |entry|
      network = @factory.get(tag: entry['tag'], api_key: keys.fetch(entry['module'], 'fixture-token-1234567890'))
      assert_equal entry['tag'], network.tag
      assert_equal entry['module'], network.provider
      assert_equal entry['class'], network.client_class
      assert_equal entry['authed'], network.authed
      assert_equal entry['sync'], network.sync
      assert_equal entry['unifeed'], network.unifeed
    end
  end
  def test_clients_without_networks_are_discoverable_and_can_be_built
    assert_equal 85, @factory.providers.size
    nextbike = @factory.providers.find { |entry| entry['class'] == 'NextbikeGbfs' }
    assert_equal [], nextbike['tags']
    network = @factory.build(provider: 'nextbike_gbfs', tag: 'custom-nextbike',
      meta: { name: 'Custom Nextbike' }, domain: 'bs')
    assert_equal 'NextbikeGbfs', network.client_class
    assert_equal 'https://gbfs.nextbike.net/maps/gbfs/v2/nextbike_bs/gbfs.json', network.meta['gbfs_href']
    assert_raises(RubyBikes::NoSystemFoundError) do
      @factory.build(provider: 'nonexistent', tag: 'custom', meta: {})
    end
    assert_raises(ArgumentError) do
      @factory.build(provider: 'keolis', tag: 'custom', meta: {})
    end
    network = @factory.build(provider: 'keolis', class_name: 'VCub', tag: 'custom-vcub',
      meta: { name: 'Custom VCub' }, feed_url: 'https://example.org/feed')
    assert_equal 'VCub', network.client_class
    network = @factory.build(provider: 'Cyclopolis', tag: 'custom-cyclopolis',
      meta: { name: 'Custom Cyclopolis' }, mapstyle: 'fixture', feed_url: 'https://example.org/feed')
    assert_equal 'Cyclopolis', network.client_class
  end
  def test_custom_authenticated_clients_use_configured_keys
    assert_raises(APIKeyNotAvailableError) do
      @factory.build(provider: 'Bicimad', tag: 'custom-madrid', meta: {})
    end
    RubyBikes.open(keys: { bicimad: { clientid: 'fixture', passkey: 'fixture' } }) do |factory|
      network = factory.build(provider: 'bicimad', tag: 'custom-madrid', meta: {})
      assert network.authed
      assert_equal 'bicimad', network.provider
    end
  end
  def test_old_hash_and_new_string_factory_interfaces
    old = @factory.get('tag' => 'velib')
    modern = @factory.get('velib')
    assert_equal old.meta, modern.meta
    assert_equal 'Paris', old.meta['city']
    assert_empty old.stations
    assert @factory.get(label: 'bixi').any?
    assert_raises(NoGetCriteriaError) { @factory.get }
    assert_raises(NoSystemFoundError) { @factory.get('nonexistent-provider') }
  end
  def test_missing_provider_key_is_typed_and_does_not_stop_the_engine
    assert_raises(APIKeyNotAvailableError) { @factory.get('callabike-koln') }
    assert_equal 'velib', @factory.get('velib').tag
  end
  def test_station_keeps_engine_identity_unknown_counts_and_utc_timestamp
    station = RubyBikes::Station.new('id' => 'engine-hash', 'name' => 'École',
      'latitude' => -22.1, 'longitude' => -43.2, 'bikes' => nil, 'free' => 0,
      'timestamp' => '2026-11-01T17:00:00+01:00', 'extra' => { 'uid' => 'abc' })
    assert_equal 'engine-hash', station.get_hash
    assert_nil station.bikes
    assert_equal '2026-11-01T16:00:00Z', station.timestamp.iso8601
    assert_equal [-43.2, -22.1], station.to_geojson['geometry']['coordinates']
    assert_equal 'École', JSON.parse(station.to_json)['name']
  end
  def with_bridge(source, timeout: 1)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'bridge.py')
      File.write(path, source)
      engine = RubyBikes::Engine.new(bridge: path, timeout: timeout)
      begin
        yield engine
      ensure
        engine.close
      end
    end
  end
  def test_partial_response_times_out_and_terminates_child
    with_bridge("import sys,time\nfor line in sys.stdin:\n sys.stdout.write('{');sys.stdout.flush();time.sleep(60)\n", timeout: 0.1) do |engine|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_raises(RubyBikes::TimeoutError) { engine.request('catalog') }
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
      assert_nil engine.instance_variable_get(:@waiter)
    end
  end
  def test_wrong_protocol_is_rejected
    with_bridge("import sys,json\nfor line in sys.stdin:\n q=json.loads(line);print(json.dumps({'id':q['id'],'protocol':999,'ok':True,'result':{}}),flush=True)\n") do |engine|
      assert_raises(RubyBikes::ProtocolError) { engine.request('catalog') }
    end
  end
  def test_rate_limit_details_are_preserved
    with_bridge("import sys,json\nfor line in sys.stdin:\n q=json.loads(line);print(json.dumps({'id':q['id'],'protocol':1,'ok':False,'error':{'code':'rate_limited','message':'Provider rate limit reached','host':'example.org','retry_after':120}}),flush=True)\n") do |engine|
      error = assert_raises(RubyBikes::RateLimitedError) { engine.request('update') }
      assert_equal 120, error.retry_after
      assert_equal 'example.org', error.host
    end
  end
  def test_missing_python_has_an_actionable_error
    engine = RubyBikes::Engine.new(python: '/nonexistent/python')
    assert_raises(RubyBikes::DependencyError) { engine.request('catalog') }
  end
  def test_block_closes_the_engine_on_failure
    factory = nil
    assert_raises(RuntimeError) do
      RubyBikes.open do |instance|
        factory = instance
        instance.tags
        raise 'test'
      end
    end
    assert_nil factory.instance_variable_get(:@engine).instance_variable_get(:@waiter)
  end
end

class RubyBikesProviderIntegrationTest < Minitest::Test
  def test_custom_network_updates_and_recovers_after_a_process_restart
    engine = RubyBikes::Engine.new(bridge: File.expand_path('fixtures/provider_bridge.py', __dir__))
    factory = RubyBikes.new(engine: engine)
    meta = { name: 'Fixture', company: ['Original'] }
    network = factory.build(provider: 'NextbikeGbfs', tag: 'custom', meta: meta, domain: 'fixture')
    meta[:company][0] = 'Changed'
    network.update
    assert_equal 'Fixture Station', network.stations.first.name
    assert_equal 3, network.stations.first.bikes
    assert_equal 9, network.stations.first.free
    assert_equal 'bike', network.vehicles.first.kind
    assert_equal 2, network.to_geojson['features'].size
    previous_id = network.stations.first.id
    factory.close
    network.update
    assert_equal previous_id, network.stations.first.id
    assert_equal ['Original'], network.meta['company']
  ensure
    factory&.close
  end
  def test_custom_definitions_with_the_same_tag_do_not_share_provider_state
    engine = RubyBikes::Engine.new(bridge: File.expand_path('fixtures/provider_bridge.py', __dir__))
    factory = RubyBikes.new(engine: engine)
    first = factory.build(provider: 'gbfs', tag: 'custom', meta: { name: 'First' }, feed_url: 'https://example.org/first')
    second = factory.build(provider: 'gbfs', tag: 'custom', meta: { name: 'Second' }, feed_url: 'https://example.org/second')
    first.update
    second.update
    assert_equal 'First', first.meta['name']
    assert_equal 'Second', second.meta['name']
    assert_equal 'https://example.org/first', first.meta['gbfs_href']
    assert_equal 'https://example.org/second', second.meta['gbfs_href']
  ensure
    factory&.close
  end
end

class RubyBikesSnapshotTest < Minitest::Test
  class FakeEngine
    attr_accessor :result
    def timeout = 1
    def request(*) = result
  end
  def test_failed_snapshot_does_not_replace_previous_stations
    engine = FakeEngine.new
    system = RubyBikes::System.new(engine, { 'tag' => 'fixture', 'meta' => {} }, nil)
    engine.result = { 'tag' => 'fixture', 'meta' => { 'name' => 'Good' }, 'stations' => [
      { 'id' => 'one', 'name' => 'Good', 'latitude' => 1, 'longitude' => 2, 'timestamp' => '2026-11-01T00:00:00Z' }
    ] }
    assert_same system, system.update
    previous = system.stations
    engine.result = { 'tag' => 'fixture', 'meta' => { 'name' => 'Bad' }, 'stations' => [{}] }
    assert_raises(RubyBikes::ProtocolError) { system.update }
    assert_same previous, system.stations
    assert_equal 'Good', system.meta['name']
  end
end
