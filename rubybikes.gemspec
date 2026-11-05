# frozen_string_literal: true

require_relative 'lib/rubybikes/version'

Gem::Specification.new do |spec|
  spec.name = 'rubybikes'
  spec.version = RubyBikes::VERSION
  spec.summary = 'Native Ruby clients for worldwide bike-sharing providers'
  spec.description = 'Bike-sharing stations and vehicles through native Ruby provider clients, with a catalog derived from PyBikes.'
  spec.authors = ['Eduardo Mucelli Rezende Oliveira']
  spec.email = 'edumucelli@gmail.com'
  spec.homepage = 'https://github.com/edumucelli/rubybikes'
  spec.license = 'AGPL-3.0'
  spec.required_ruby_version = '>= 3.1'
  spec.require_paths = ['lib']
  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'changelog_uri' => "#{spec.homepage}/blob/master/CHANGELOG.md",
    'documentation_uri' => "#{spec.homepage}#readme",
    'allowed_push_host' => 'https://rubygems.org',
    'rubygems_mfa_required' => 'true'
  }
  spec.files = %w[
    LICENSE NOTICE README.md CHANGELOG.md
    CONTRIBUTING.md PROVIDERS.md RELEASING.md lib/rubybikes.rb
    lib/rubybikes/version.rb lib/rubybikes/engine.rb lib/rubybikes/native.rb
  ] +
               Dir.glob('{lib/rubybikes/native,sig,data}/**/*').select { |file| File.file?(file) }
  spec.add_dependency 'csv', '>= 3.2', '< 4'
  spec.add_dependency 'http-cookie', '~> 1.0'
  spec.add_dependency 'nokogiri', '>= 1.18', '< 2'
  spec.add_dependency 'timeout', '~> 0.6'
end
