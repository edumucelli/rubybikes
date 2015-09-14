# RubyBikes

RubyBikes works with 2 concepts, _labels_ and _tags_.

For instance, if you want to get information from the stations in the 'encicla' (Medellin, Colombia) system, you'd use:

```ruby
require 'rubybikes'

bikes = RubyBikes.new
encicla = bikes.get({'tag' => 'encicla'})
encicla.update
encicla.stations.each do |station|
  puts "#{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}"
end
```

Currently, RubyBikes supports 270 system tags, i.e., 270 bike-sharing systems around the world.
For the complete list of tags, check out documentation, or use the tags method, 'puts bikes.tags`.

However, generally a set bike-sharing systems belong to the same company, which we call _label_.

If you want, for instance, get all the systems within JCDecaux' Cyclocity system, which encompasses, 'velib' (Paris, France), 'velov' (Lyon, France), 'sevici' (Sevilla, Spain), etc., you'd use:

```ruby
instances = bikes.get({'label' => 'Cyclocity', 'api_key' => 'API_KEY'})
# each 'instance' is a system, i.e., a 'tag' system
instances.each do |instance|
	instance.stations.each do |station|
		puts "#{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}"
	end
end
```
