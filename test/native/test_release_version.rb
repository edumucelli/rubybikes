# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../../.github/scripts/release_version'
require 'tmpdir'

class NativeReleaseVersionTest < Minitest::Test
  ENDPOINT = "https://rubygems.org/api/v2/rubygems/rubybikes/versions/#{RubyBikes::VERSION}.json".freeze

  def test_unpublished_version_is_read_from_runtime_version_file
    stub_request(:get, ENDPOINT).to_return(status: 404)

    assert_equal({ 'version' => RubyBikes::VERSION, 'tag' => "v#{RubyBikes::VERSION}", 'publish' => 'true' }, RubyBikesRelease.outputs)
  end

  def test_existing_version_is_never_republished
    stub_request(:get, ENDPOINT).to_return(body: JSON.generate(name: 'rubybikes', version: RubyBikes::VERSION))

    assert_equal 'false', RubyBikesRelease.outputs.fetch('publish')
  end

  def test_registry_errors_never_treat_version_as_unpublished
    [403, 429, 500].each do |status|
      stub_request(:get, ENDPOINT).to_return(status: status)
      assert_raises(RuntimeError) { RubyBikesRelease.outputs }
    end
    stub_request(:get, ENDPOINT).to_timeout
    assert_raises(Net::OpenTimeout) { RubyBikesRelease.outputs }
  end

  def test_success_response_must_describe_the_requested_gem_version
    ['invalid-json', '{}', '[]', JSON.generate(name: 'other', version: RubyBikes::VERSION)].each do |body|
      stub_request(:get, ENDPOINT).to_return(body: body)
      assert_raises(JSON::ParserError, RuntimeError) { RubyBikesRelease.outputs }
    end
  end

  def test_version_cannot_inject_outputs_or_tag_names
    ["0.3.0\npublish=true", '../main', 'v0.3.0', ''].each do |version|
      assert_raises(RuntimeError) { RubyBikesRelease.outputs(version) }
    end
    assert_not_requested(:get, /rubygems.org/)
  end

  def test_writes_github_outputs
    stub_request(:get, ENDPOINT).to_return(status: 404)
    saved = ENV.fetch('GITHUB_OUTPUT', nil)
    Dir.mktmpdir do |directory|
      ENV['GITHUB_OUTPUT'] = File.join(directory, 'outputs')
      capture_io { RubyBikesRelease.configure }

      assert_equal "version=#{RubyBikes::VERSION}\ntag=v#{RubyBikes::VERSION}\npublish=true\n", File.read(ENV.fetch('GITHUB_OUTPUT'))
    end
  ensure
    ENV['GITHUB_OUTPUT'] = saved
  end
end
