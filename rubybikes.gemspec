Gem::Specification.new do |s|
  s.name        = 'rubybikes'
  s.version     = '0.0.1'
  s.date        = '2015-09-08'
  s.summary     = "Ruby Bikes"
  s.description = "Bike-sharing system wrappers from networks around the world."
  s.authors     = ["Eduardo Mucelli Rezende Oliveira"]
  s.email       = 'edumucelli@gmail.com'
  s.files       = Dir.glob("lib/**/*") + %w(LICENSE README.md)
  s.homepage    = 'http://rubygems.org/gems/rubybikes'
  s.license     = 'AGPL'
  s.add_development_dependency "rspec"
end