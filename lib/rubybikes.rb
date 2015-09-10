require 'json'

RUBYBIKES_DIRECTORY = "rubybikes"
SCHEMAS_DIRECTORY = "schemas"
SCHEMAS_EXTENSION = "json"

class RubyBikes
	def get(tag, api_key=nil)
		name, schema_instance_parameters = get_klass_name_and_schema_instance(tag)
		klass_object = Object::const_get(name)
		if klass_object.method_defined? :authed
			begin
				return klass_object.new(api_key, schema_instance_parameters)
			rescue APIKeyNotAvailableError => e
				puts "'#{tag}' system requires a API key." 
			end
		else
			return klass_object.new(schema_instance_parameters)
		end
	end

	def get_klass_name_and_schema_instance(tag)
		schemas.each do |schema_file|
			schema = JSON.parse(File.open(schema_file).read)
			klass 	= schema['class']	# class name, as Encicla, Cyclocity, ...
			system 	= schema['system']	# system is the name of the ruby file, without extension, as encicla, cyclocity, ...
			if klass.is_a? String
			# Schemas with one class
				schema['instances'].each do |instance|
					if instance['tag'] == tag
						require_rubybikes_class(system)
						return klass, instance
					end
				end
			else
			# Schemas with multiple classes
				klass.each do |name, instances|
					instances['instances'].each do |instance|
						if instance['tag'] == tag
							require_rubybikes_class(system)
							return name, instance
						end
					end
				end
			end
		end
		#raise "System with tag '#{tag}' was not found. For a complete list of supported tags, use 'tags' method."
	end
	def require_rubybikes_class(system)
		require File.dirname(__FILE__) + "/#{RUBYBIKES_DIRECTORY}/#{system}.rb"
	end
	def tags
		schemas.map do |schema| 
			JSON.parse(File.open(schema).read)['instances'].map {|instance| instance['tag']}
		end
	end
	def schemas
		Dir.glob(File.join(Dir.pwd, RUBYBIKES_DIRECTORY, SCHEMAS_DIRECTORY, "*.#{SCHEMAS_EXTENSION}"))
	end
	private :get_klass_name_and_schema_instance, :schemas, :require_rubybikes_class
end

if __FILE__ == $0
	bikes = RubyBikes.new
	puts bikes.tags.length
	cyclic = bikes.get('cyclic', '4b780b841057c43770f03bd06c8d30a7c41f9200')
	puts cyclic.meta
	cyclic.update
	cyclic.stations.each do |station|
	  puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.extra}"
	end
end