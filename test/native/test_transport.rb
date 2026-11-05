# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../../.github/scripts/configure_rubygems'

class NativeTransportTest < Minitest::Test
  include NativeFixtures

  def test_get_query_headers_cache_and_encoding
    stub = stub_request(:get, 'https://fixture.test/feed?existing=1&city=Paris')
           .with(headers: { 'User-Agent' => 'Fixture' })
           .to_return(
             body: "caf\xe9".b,
             headers: { 'Content-Type' => 'text/plain; charset=ISO-8859-1' }
           )
    transport = RubyBikes::Native::Transport.new(headers: { 'User-Agent' => 'Fixture' })

    2.times { assert_equal 'café', transport.request('https://fixture.test/feed?existing=1', params: { city: 'Paris' }) }
    assert_requested stub, times: 1
  end

  def test_post_forms_and_cookies
    stub_request(:post, 'https://fixture.test/login').with(body: { 'name' => 'value' }).to_return(body: 'ok', headers: { 'Set-Cookie' => 'session=fixture; Path=/; Secure' })
    stub = stub_request(:get, 'https://fixture.test/feed').with(headers: { 'Cookie' => 'session=fixture' }).to_return(body: 'data')
    transport = RubyBikes::Native::Transport.new

    assert_equal 'ok', transport.request('https://fixture.test/login', method: 'POST', data: { 'name' => 'value' })
    assert_equal 'data', transport.request('https://fixture.test/feed')
    assert_requested stub
  end

  def test_rate_limit_records_and_honors_cooldown
    cooldowns = {}
    stub = stub_request(:get, 'https://fixture.test/feed').to_return(status: 429, body: 'private response', headers: { 'Retry-After' => '120' })
    transport = RubyBikes::Native::Transport.new(cooldowns: cooldowns)
    error = assert_raises(RubyBikes::RateLimitedError) { transport.request('https://fixture.test/feed') }
    assert_equal 'fixture.test', error.host
    assert_equal 120, error.retry_after
    assert_raises(RubyBikes::RateLimitedError) { transport.request('https://fixture.test/feed') }
    assert_requested stub, times: 1
  end

  def test_redirect_does_not_forward_cross_origin_credentials
    stub_request(:get, 'https://fixture.test/feed').to_return(status: 302, headers: { 'Location' => 'https://other.test/feed' })
    stub = stub_request(:get, 'https://other.test/feed').with { |request| !request.headers.key?('Authorization') }.to_return(body: 'ok')

    assert_equal 'ok', RubyBikes::Native::Transport.new(headers: { 'authorization' => 'private' }).request('https://fixture.test/feed')
    assert_requested stub
  end

  def test_timeout_is_typed_and_expired_deadline_prevents_request
    transport = RubyBikes::Native::Transport.new
    stub_request(:get, 'https://fixture.test/feed').to_timeout
    assert_raises(RubyBikes::TimeoutError) { transport.request('https://fixture.test/feed') }
    now = 0
    expired = RubyBikes::Native::Transport.new(timeout: 1, clock: -> { now })
    now = 2
    assert_raises(RubyBikes::TimeoutError) { expired.request('https://fixture.test/expired') }
  end

  def test_oidc_first_push_names_the_configured_owner
    assert_equal({ jwt: 'fixture-jwt', owner: 255_571 }, RubyGemsCredentials.exchange_payload('fixture-jwt'))
    assert_equal 'https://rubygems.org/api/v1/oidc/trusted_publisher/exchange_token', RubyGemsCredentials::EXCHANGE_URL.to_s
  end

  def test_transport_disables_implicit_retries_and_bounds_socket_timeouts
    client = nil
    constructor = Net::HTTP.method(:new)
    capture_client = lambda do |*arguments|
      client = constructor.call(*arguments)
    end
    stub_request(:get, 'https://fixture.test/bounded').to_return(body: 'ok')

    Net::HTTP.stub(:new, capture_client) do
      assert_equal 'ok', RubyBikes::Native::Transport.new.request('https://fixture.test/bounded')
    end
    assert_equal 0, client.max_retries
    assert_equal 5, client.open_timeout
    assert_equal 20, client.read_timeout
    assert_equal 20, client.write_timeout
    assert_predicate client, :use_ssl?
  end

  def test_quoted_charset_parameters_are_decoded
    stub_request(:get, 'https://fixture.test/quoted').to_return(
      body: "caf\xe9".b, headers: { 'Content-Type' => 'text/plain; charset="ISO-8859-1"' }
    )

    assert_equal 'café', RubyBikes::Native::Transport.new.request('https://fixture.test/quoted')
  end
end
