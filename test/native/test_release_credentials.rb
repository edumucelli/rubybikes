# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../../.github/scripts/configure_rubygems'
require 'tmpdir'

class NativeReleaseCredentialsTest < Minitest::Test
  def with_actions_environment
    names = %w[ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN GITHUB_ENV]
    saved = names.to_h { |name| [name, ENV.fetch(name, nil)] }
    Dir.mktmpdir do |directory|
      ENV['ACTIONS_ID_TOKEN_REQUEST_URL'] = 'https://oidc.fixture.test/token?api-version=1'
      ENV['ACTIONS_ID_TOKEN_REQUEST_TOKEN'] = 'fixture-actions-token'
      ENV['GITHUB_ENV'] = File.join(directory, 'github-env')
      yield ENV.fetch('GITHUB_ENV')
    end
  ensure
    saved&.each { |name, value| ENV[name] = value }
  end

  def test_exchange_explicitly_sends_owner_and_masks_short_lived_key
    with_actions_environment do |env_file|
      github = stub_request(:get, 'https://oidc.fixture.test/token?api-version=1&audience=rubygems.org')
               .with(headers: { 'Authorization' => 'Bearer fixture-actions-token' })
               .to_return(body: JSON.generate('value' => 'fixture-jwt'))
      registry = stub_request(:post, RubyGemsCredentials::EXCHANGE_URL.to_s)
                 .with(body: JSON.generate(jwt: 'fixture-jwt', owner: 255_571), headers: { 'Content-Type' => 'application/json' })
                 .to_return(body: JSON.generate('rubygems_api_key' => 'fixture-short-lived-key'))
      output, errors = capture_io { RubyGemsCredentials.configure }

      assert_equal "::add-mask::fixture-short-lived-key\n", output
      assert_empty errors
      assert_equal "GEM_HOST_API_KEY=fixture-short-lived-key\n", File.read(env_file)
      assert_requested github
      assert_requested registry
    end
  end

  def test_failed_exchange_never_writes_credentials_or_logs_response_body
    with_actions_environment do |env_file|
      stub_request(:get, 'https://oidc.fixture.test/token?api-version=1&audience=rubygems.org').to_return(body: JSON.generate('value' => 'fixture-jwt'))
      stub_request(:post, RubyGemsCredentials::EXCHANGE_URL.to_s).to_return(status: 403, body: 'private-response')
      error = assert_raises(RuntimeError) { RubyGemsCredentials.configure }
      refute_includes error.message, 'private-response'
      refute_path_exists env_file
    end
  end

  def test_malformed_credential_responses_are_redacted
    response = Struct.new(:body).new('private malformed credential response')
    error = assert_raises(RuntimeError) { RubyGemsCredentials.response_value(response, 'value') }
    assert_equal 'Invalid credential response', error.message
    response.body = JSON.generate('value' => "invalid\nkey")
    assert_raises(RuntimeError) { RubyGemsCredentials.response_value(response, 'value') }
  end
end
