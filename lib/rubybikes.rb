# Copyright (C) Eduardo Mucelli Rezende Oliveira <edumucelli@gmail.com>
# Distributed under the AGPL license, see LICENSE.txt

require 'json'

RUBYBIKES_DIRECTORY = "rubybikes"
SCHEMAS_DIRECTORY = "schemas"
SCHEMAS_EXTENSION = "json"

class NoSystemFoundError < StandardError; end
class NoGetCriteriaError < StandardError; end
class APIKeyNotAvailableError < StandardError; end

class RubyBikes

	def get(options = {})
		label	= options.fetch('label', nil)
        tag     = options.fetch('tag', nil)
        api_key = options.fetch('api_key', nil)
		if tag
			class_name, schema_instance_parameters = get_class_name_and_schema_instance(tag)
			return create_class_instance(class_name, schema_instance_parameters, api_key)
		elsif label
			class_objects = []
			schemas.each do |schema_file|
				schema = JSON.parse(File.open(schema_file).read)
				if schema['label'] == label
					tags = tags_from_schema(schema)
					tags.each do |tag|
						class_name, schema_instance_parameters = get_class_name_and_schema_instance(tag)
						class_objects << create_class_instance(class_name, schema_instance_parameters, api_key)
					end
				end
			end
			class_objects
		else
			raise NoGetCriteriaError, "No 'label' or 'tag' given."
		end
	end

	def create_class_instance(class_name, schema_instance_parameters, api_key)
		class_object = Object::const_get(class_name)
		if class_object.methods.include? :authed
			begin
				return class_object.new(api_key, schema_instance_parameters)
			rescue APIKeyNotAvailableError => e
				puts "'#{tag}' system requires a API key." 
			end
		else
			return class_object.new(schema_instance_parameters)
		end
	end

	def get_class_name_and_schema_instance(tag)
		schemas.each do |schema_file|
			schema = JSON.parse(File.open(schema_file).read)
			klass 	= schema['class']	# class name, as Encicla, Cyclocity, ...
			system 	= schema['system']	# system is the name of the ruby file, without extension, as encicla, cyclocity, ...
			if klass.is_a? String
				# Schemas with one class
				instance = schema['instances'].detect{|instance| instance['tag'] == tag}
				if instance
					require_rubybikes_class(system)
					return klass, instance
				end
			else
				# Schemas with multiple classes
				klass.each do |name, instances|
					instance = instances['instances'].detect{|instance|	instance['tag'] == tag}
					if instance
						require_rubybikes_class(system)
						return name, instance
					end
				end
			end
		end
		raise NoSystemFoundError, "System '#{tag}' was not found. For the complete list of supported tags, use the 'tags' method."
	end

	def tags_from_schema(schema)
		tags = []
		if schema['class'].is_a? String
			tags.push(*schema['instances'].map {|instance| instance['tag']})
		else
			schema['class'].map do|name, instances|
				tags.push(*instances['instances'].map {|instance| instance['tag']})
			end
		end
		tags
	end

	def require_rubybikes_class(system)
		require File.dirname(__FILE__) + "/#{RUBYBIKES_DIRECTORY}/#{system}.rb"
	end

	def tags
		tags = []
		schemas.each do |schema_file| 
			schema = JSON.parse(File.open(schema_file).read)
			tags.push(*tags_from_schema(schema))
		end
		tags
	end

	def schemas
		Dir.glob(File.join(Dir.pwd, RUBYBIKES_DIRECTORY, SCHEMAS_DIRECTORY, "*.#{SCHEMAS_EXTENSION}"))
	end

	private :get_class_name_and_schema_instance, :schemas, :tags_from_schema, :create_class_instance, :require_rubybikes_class
end

if __FILE__ == $0
	bikes = RubyBikes.new
	puts bikes.tags.length
	# ====
	# By label
	# instances = bikes.get({'label' => 'Cyclocity', 'api_key' => '4b780b841057c43770f03bd06c8d30a7c41f9200'})
	# instances.each do |instance|
	# 	puts instance.meta
	# 	instance.update
	# 	instance.stations.each do |station|
	# 		puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.extra}"
	# 	end
	# end
	# ====
	# By tag
	# cyclic = bikes.get({'tag' => 'cyclic', 'api_key' => '4b780b841057c43770f03bd06c8d30a7c41f9200'})
	# cyclic.update
	# cyclic.stations.each do |station|
	#   puts "#{station.get_hash()}, #{station.name}, #{station.latitude}, #{station.longitude}, #{station.free}, #{station.bikes}, #{station.extra}"
	# end
end