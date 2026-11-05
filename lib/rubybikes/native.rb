# frozen_string_literal: true

# rubocop:disable Style/OneClassPerFile -- The loader establishes data paths before exposing the native Engine alias.

require_relative 'version'
class RubyBikes
  module Native
    DATA = File.expand_path('../../data', File.dirname(__FILE__))
  end
end
require_relative 'native/geometry'
require_relative 'native/response_cache'
require_relative 'native/transport'
require_relative 'native/provider'
require_relative 'native/gbfs'
require_relative 'native/nextbike'
require_relative 'native/json_providers'
require_relative 'native/engine'
require_relative 'native/authenticated'
require_relative 'native/graphql'
require_relative 'native/more_json'
require_relative 'native/remaining_clients'
require_relative 'native/html_clients'
require_relative 'native/xml_details'
class RubyBikes
  Engine = Native::Engine unless const_defined?(:Engine, false)
end
require_relative '../rubybikes' unless defined?(RubyBikes::System)

# rubocop:enable Style/OneClassPerFile
