# frozen_string_literal: true

require 'digest/md5'
require 'json'
require 'csv'
require 'nokogiri'

class RubyBikes
  module Native
    class Provider
      attr_reader :tag, :meta, :spec, :parameters

      def initialize(spec, parameters, key: nil)
        @spec = spec
        @parameters = Marshal.load(Marshal.dump(parameters))
        @tag = @parameters.fetch('tag')
        defaults = Marshal.load(Marshal.dump(spec.fetch('meta')))
        @meta = { 'name' => nil, 'city' => nil, 'country' => nil, 'latitude' => nil, 'longitude' => nil, 'company' => nil }.merge(defaults).merge(@parameters.fetch('meta'))
        @meta['name'] ||= @meta['system'] || spec.fetch('class')
        @key = key
        raise APIKeyNotAvailableError, 'This provider requires an API key' if spec['authed'] && !truthy?(key)
      end

      def snapshot(transport)
        @transport = transport
        @stations, @vehicles = [], []
        update
        { 'tag' => tag, 'meta' => meta, 'stations' => @stations, 'vehicles' => @vehicles }
      end

      def station(name, latitude, longitude, bikes = nil, free = nil, extra = {})
        latitude, longitude = Float(latitude), Float(longitude)
        bounds = parameters['bbox']
        return if bounds && !Geometry.contains?(bounds, latitude, longitude)

        id = Digest::MD5.hexdigest("#{(latitude * 1e6).to_i},#{(longitude * 1e6).to_i}")
        @stations << { 'id' => id, 'name' => name, 'latitude' => latitude, 'longitude' => longitude,
                       'bikes' => bikes, 'free' => free, 'extra' => extra, 'timestamp' => Time.now.utc.iso8601(6) }
      end

      def vehicle(latitude, longitude, extra = {}, kind = 'bike')
        latitude, longitude = Float(latitude), Float(longitude)
        return if parameters['bbox'] && !Geometry.contains?(parameters['bbox'], latitude, longitude)

        # @type var components: Array[String | Integer]
        components = [tag]
        if truthy?(extra['uid'])
          components << extra['uid']
        else
          components.push((latitude * 1e6).to_i, (longitude * 1e6).to_i, kind)
        end
        @vehicles << { 'id' => Digest::MD5.hexdigest(components.join(',')), 'latitude' => latitude,
                       'longitude' => longitude, 'kind' => kind, 'extra' => extra, 'timestamp' => Time.now.utc.iso8601(6) }
      end

      def request(url, **options) = @transport.request(url, **options)
      def json(url, **options) = JSON.parse(request(url, **options))

      def xml(url, **options)
        Nokogiri::XML(request(url, **options)) { |config| config.nonet } # rubocop:disable Style/SymbolProc -- Preserve the typed parser configuration block.
      end

      def html(url, **options) = Nokogiri::HTML(request(url, **options))
      def p(name, fallback = nil) = parameters.fetch(name, fallback)
      def number(value) = value.is_a?(String) ? Integer(value, 10) : Integer(value)
      def list(value) = Array(value)
      def integer(value) = value.nil? ? nil : number(value)

      def truthy?(value)
        # @type var empty_list: Array[untyped]
        empty_list = []
        # @type var empty_object: RubyBikes::object
        empty_object = {}
        value && value != 0 && value != '' && value != empty_list && value != empty_object
      end

      def iso_date(value)
        value.is_a?(Numeric) ? Time.at(value).utc.iso8601 : Time.iso8601(value).utc.iso8601
      rescue ArgumentError, TypeError, RangeError
        nil
      end
    end
  end
end
