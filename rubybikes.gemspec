Gem::Specification.new do |s|
  s.name        = 'rubybikes'
  s.version     = '0.0.1'
  s.date        = '2015-09-08'
  s.summary     = "Ruby Bikes"
  s.description = "Bike-sharing system wrappers from networks systems around the world."
  s.authors     = ["Eduardo Mucelli Rezende Oliveira"]
  s.email       = 'edumucelli@gmail.com'
  s.files       = [ "lib/rubybikes.rb", "lib/rubybikes/base.rb", "lib/rubybikes/utils.rb", "lib/rubybikes/redirections.rb", "lib/rubybikes/warnings.rb"
                    "lib/rubybikes/bicipalma.rb", "lib/rubybikes/bcycle.rb", "lib/rubybikes/bikeu.rb", "lib/rubybikes/bixi.rb", 
                    "lib/rubybikes/callabike.rb", "lib/rubybikes/cyclopolis.rb", "lib/rubybikes/cyclocity.rb", "lib/rubybikes/cleanap.rb",
                    "lib/rubybikes/ciclosampa.rb", "lib/rubybikes/changzhou.rb", "lib/rubybikes/encicla.rb"]
  s.homepage    = 'http://rubygems.org/gems/rubybikes'
  s.license     = 'GPL'
end