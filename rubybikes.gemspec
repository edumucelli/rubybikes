require_relative 'lib/rubybikes'
Gem::Specification.new do |s|
  s.name = 'rubybikes'
  s.version = RubyBikes::VERSION
  s.summary = 'Ruby interface to the maintained pybikes provider engine'
  s.description = 'Worldwide bike-sharing provider data through a Ruby API and a pinned pybikes engine.'
  s.authors = ['Eduardo Mucelli Rezende Oliveira']
  s.email = 'edumucelli@gmail.com'
  s.files = Dir.glob('lib/**/*').reject { |path| path.include?('__pycache__') } + %w[LICENSE README.md requirements-engine.txt]
  s.homepage = 'https://github.com/edumucelli/rubybikes'
  s.license = 'AGPL-3.0'
  s.required_ruby_version = '>= 3.1'
end
