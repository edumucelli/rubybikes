# frozen_string_literal: true

require_relative 'test_helper'

class NativeResponseCacheTest < Minitest::Test
  Cache = RubyBikes::Native::ResponseCache
  Transport = RubyBikes::Native::Transport
  FEED = 'https://fixtures.example/cache'

  def response(body)
    Transport::Response.new(status: 200, headers: { 'content-type' => 'text/plain' }, body: body)
  end

  def test_cache_is_shared_between_transports_only_when_explicitly_supplied
    shared = Cache.new
    request = stub_request(:get, FEED).to_return(body: 'cached')
    first = Transport.new(cache: shared)
    second = Transport.new(cache: shared)

    assert_equal 'cached', first.request(FEED)
    assert_equal 'cached', second.request(FEED)
    assert_requested request, times: 1
    Transport.new.request(FEED)
    Transport.new.request(FEED)

    assert_requested request, times: 3
  end

  def test_expiry_uses_monotonic_time_and_reads_do_not_extend_lifetime
    now = 0.0
    clock = -> { now }
    cache = Cache.new
    request = stub_request(:get, FEED).to_return({ body: 'first' }, { body: 'fresh' })

    assert_equal 'first', Transport.new(cache: cache, clock: clock).request(FEED)
    now = 59.0

    assert_equal 'first', Transport.new(cache: cache, clock: clock).request(FEED)
    now = 60.0

    assert_equal 'fresh', Transport.new(cache: cache, clock: clock).request(FEED)
    assert_requested request, times: 2
  end

  def test_query_parameters_headers_and_bodies_isolate_entries
    cache = Cache.new
    first = stub_request(:get, "#{FEED}?network=one").with(headers: { 'X-Network' => 'one' }, body: 'body-one').to_return(body: 'one')
    second = stub_request(:get, "#{FEED}?network=two").with(headers: { 'X-Network' => 'one' }, body: 'body-one').to_return(body: 'two')
    third = stub_request(:get, "#{FEED}?network=one").with(headers: { 'X-Network' => 'two' }, body: 'body-one').to_return(body: 'different-header')
    fourth = stub_request(:get, "#{FEED}?network=one").with(headers: { 'X-Network' => 'one' }, body: 'body-two').to_return(body: 'different-body')

    assert_equal 'one', Transport.new(cache: cache).request(FEED, params: { 'network' => 'one' }, headers: { 'X-Network' => 'one' }, data: 'body-one')
    assert_equal 'two', Transport.new(cache: cache).request(FEED, params: { 'network' => 'two' }, headers: { 'X-Network' => 'one' }, data: 'body-one')
    assert_equal 'different-header', Transport.new(cache: cache).request(FEED, params: { 'network' => 'one' }, headers: { 'X-Network' => 'two' }, data: 'body-one')
    assert_equal 'different-body', Transport.new(cache: cache).request(FEED, params: { 'network' => 'one' }, headers: { 'X-Network' => 'one' }, data: 'body-two')
    assert_equal 'one', Transport.new(cache: cache).request(FEED, params: { 'network' => 'one' }, headers: { 'X-Network' => 'one' }, data: 'body-one')
    [first, second, third, fourth].each { |request| assert_requested request, times: 1 }
  end

  def test_errors_posts_and_skip_cache_are_never_cached
    cache = Cache.new
    request = stub_request(:get, FEED).to_return({ status: 503, body: 'error' }, { body: 'good' }, { body: 'bypass' })

    assert_equal 'error', Transport.new(cache: cache).request(FEED)
    assert_equal 'good', Transport.new(cache: cache).request(FEED)
    assert_equal 'bypass', Transport.new(cache: cache).request(FEED, skip_cache: true)
    assert_equal 'good', Transport.new(cache: cache).request(FEED)
    assert_requested request, times: 3
    post = stub_request(:post, FEED).to_return(body: 'posted')

    2.times { assert_equal 'posted', Transport.new(cache: cache).request(FEED, method: 'POST', data: 'body') }
    assert_requested post, times: 2
  end

  def test_entry_count_and_body_byte_bounds_evict_the_oldest_entries
    cache = Cache.new(max_entries: 2, max_bytes: 6)
    cache.put('one', response('aaa'), 0)
    cache.put('two', response('bbb'), 1)

    assert_equal 'aaa', cache.get('one', 2).body
    cache.put('three', response('ccc'), 3)

    assert_nil cache.get('one', 3)
    assert_equal 'bbb', cache.get('two', 3).body
    assert_equal 'ccc', cache.get('three', 3).body
    cache.put('four', response('dddd'), 4)

    assert_nil cache.get('two', 4)
    assert_nil cache.get('three', 4)
    assert_equal 'dddd', cache.get('four', 4).body
  end

  def test_replacement_updates_byte_accounting_and_rejects_oversized_entries
    cache = Cache.new(max_bytes: 5)
    cache.put('one', response('aaaa'), 0)
    cache.put('one', response('b'), 1)
    cache.put('two', response('cccc'), 2)

    assert_equal 'b', cache.get('one', 2).body
    assert_equal 'cccc', cache.get('two', 2).body
    cache.put('too-large', response('123456'), 3)

    assert_nil cache.get('too-large', 3)
    assert_equal 'b', cache.get('one', 3).body
    cache.put('one', response('123456'), 4)

    assert_nil cache.get('one', 4)
    assert_equal 'cccc', cache.get('two', 4).body
  end

  def test_expired_entries_release_capacity_before_new_insertions
    cache = Cache.new(ttl: 10, max_entries: 2, max_bytes: 5)
    cache.put('one', response('aaa'), 0)
    cache.put('two', response('bb'), 1)

    assert_nil cache.get('one', 10)
    cache.put('three', response('ccc'), 10)

    assert_equal 'bb', cache.get('two', 10).body
    assert_equal 'ccc', cache.get('three', 10).body
    assert_nil cache.get('two', 11)
    assert_equal 'ccc', cache.get('three', 11).body
  end

  def test_cache_keys_and_responses_are_detached_from_mutable_callers
    cache = Cache.new
    key = ['GET', FEED.dup, { 'X-Network' => 'one'.dup }]
    original = response('original'.dup)
    cache.put(key, original, 0)
    key[2]['X-Network'].replace('changed')
    original.body.replace('changed')
    original.headers['content-type'] = 'changed'
    saved = cache.get(['GET', FEED, { 'X-Network' => 'one' }], 1)

    assert_equal 'original', saved.body
    assert_equal 'text/plain', saved.headers['content-type']
    assert_predicate saved, :frozen?
    assert_predicate saved.body, :frozen?
  end

  def test_concurrent_reads_and_replacements_are_consistent
    cache = Cache.new(max_entries: 8, max_bytes: 4096)
    workers = Array.new(8) do |worker|
      Thread.new do
        20.times do |iteration|
          text = "#{worker}:#{iteration}"
          cache.put(worker, response(text), iteration)

          assert_equal text, cache.get(worker, iteration).body
        end
      end
    end
    workers.each(&:value)
  end

  def test_cache_limits_are_validated
    [0, -1, Float::INFINITY, Float::NAN].each do |ttl|
      assert_raises(ArgumentError) { Cache.new(ttl: ttl) }
    end
    assert_raises(ArgumentError) { Cache.new(max_entries: 0) }
    assert_raises(ArgumentError) { Cache.new(max_bytes: 0) }
  end
end

class NativeEngineResponseCacheTest < Minitest::Test
  include NativeFixtures

  def test_public_unifeed_networks_share_one_response_within_the_factory
    factory = RubyBikes.new
    first = factory.build(provider: 'Nextbike', tag: 'first', meta: { name: 'First' }, domain: 'fixture', city_uid: '1')
    second = factory.build(provider: 'Nextbike', tag: 'second', meta: { name: 'Second' }, domain: 'fixture', city_uid: '2')
    body = <<~XML
      <markers>
      <country>
      <city uid="1">
      <place uid="s1" name="First" lat="48.85" lng="2.35" spot="1" bikes="3"/>
      </city>
      <city uid="2">
      <place uid="s2" name="Second" lat="48.86" lng="2.36" spot="1" bikes="4"/>
      </city>
      </country>
      </markers>
    XML
    request = stub_request(:get, 'https://maps.nextbike.net/maps/nextbike-live.xml?domains=fixture').to_return(body: body)
    first.update
    second.update

    assert_equal 'First', first.stations.first.name
    assert_equal 'Second', second.stations.first.name
    assert_requested request, times: 1
  ensure
    factory&.close
  end

  def test_ordinary_network_updates_get_independent_local_caches
    factory = RubyBikes.new
    payload = [{ 'label' => 'Station', 'coordinates' => [2.35, 48.85], 'availableBikes' => 3, 'availableSlots' => 9, 'id' => 's1', 'isClosed' => false }]
    request = stub_request(:get, 'https://fixtures.example/ordinary').to_return(response(payload))
    first = factory.build(provider: 'FifteenAPI', tag: 'first', meta: {}, feed_url: 'https://fixtures.example/ordinary')
    second = factory.build(provider: 'FifteenAPI', tag: 'second', meta: {}, feed_url: 'https://fixtures.example/ordinary')
    first.update
    second.update

    assert_requested request, times: 2
  ensure
    factory&.close
  end

  def test_authenticated_unifeed_networks_never_share_responses_between_updates
    factory = RubyBikes.new
    key = { 'client_id' => 'fixture-client', 'client_secret' => 'fixture-secret' }
    first = factory.build(provider: 'Callabike', tag: 'first', meta: {}, api_key: key)
    second = factory.build(provider: 'Callabike', tag: 'second', meta: {}, api_key: key)
    discovery = 'https://apis.deutschebahn.com/db-api-marketplace/apis/shared-mobility-gbfs/v2/de/CallABike/gbfs'
    feeds = %w[station_information station_status].map { |name| { 'name' => name, 'url' => "https://fixtures.example/#{name}.json" } }
    request = stub_request(:get, discovery).with(headers: { 'DB-Client-Id' => 'fixture-client', 'DB-Api-Key' => 'fixture-secret' })
                                           .to_return(response({ 'data' => { 'en' => { 'feeds' => feeds } } }))
    stub_request(:get, 'https://fixtures.example/station_information.json').to_return(response({ 'data' => { 'stations' => [
                                                                                                 { 'station_id' => 's1', 'name' => 'Station', 'lat' => 48.85, 'lon' => 2.35 }
                                                                                               ] } }))
    stub_request(:get, 'https://fixtures.example/station_status.json').to_return(response({ 'data' => { 'stations' => [
                                                                                            { 'station_id' => 's1', 'is_installed' => true, 'is_renting' => true,
                                                                                              'is_returning' => true, 'num_bikes_available' => 3, 'num_docks_available' => 9 }
                                                                                          ] } }))
    first.update
    second.update

    assert_equal 3, first.stations.first.bikes
    assert_equal 3, second.stations.first.bikes
    assert_requested request, times: 2
  ensure
    factory&.close
  end
end
