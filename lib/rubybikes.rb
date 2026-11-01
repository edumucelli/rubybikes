# Copyright (C) Eduardo Mucelli Rezende Oliveira
# Distributed under the AGPL license, see LICENSE.
require 'json'
require 'time'

class RubyBikes
  VERSION = '0.1.0'

  class Error < StandardError
    attr_reader :details
    def initialize(message, details: {})
      @details = details
      super(message)
    end
  end
  class DependencyError < Error; end
  class ProviderError < Error; end
  class ProtocolError < Error; end
  class TimeoutError < Error; end
  class RateLimitedError < ProviderError
    def retry_after = details.fetch('retry_after', 300).to_f
    def host = details['host']
  end
  class NoSystemFoundError < Error; end
  class NoGetCriteriaError < Error; end
  class APIKeyNotAvailableError < Error; end

  def initialize(python: ENV.fetch('RUBYBIKES_PYTHON', 'python3'), timeout: 60, keys: {}, engine: nil)
    @engine = engine || Engine.new(python: python, timeout: timeout)
    @keys = keys.transform_keys(&:to_s)
  end

  def catalog
    @catalog ||= @engine.request('catalog').fetch('networks')
  end

  def engine_info = @engine.request('version')
  def tags = catalog.map { |entry| entry.fetch('tag') }
  def labels = catalog.map { |entry| entry.fetch('label') }.uniq.sort

  # Original string-keyed hashes and modern keyword/string forms are accepted.
  def get(options = {}, **keywords)
    options = options.is_a?(String) ? { 'tag' => options } : options.transform_keys(&:to_s)
    options = options.merge(keywords.transform_keys(&:to_s))
    if (tag = options['tag'])
      entry = catalog.find { |row| row['tag'] == tag }
      raise NoSystemFoundError, "Unknown system tag: #{tag}" unless entry
      key = options['api_key'] || options['key'] || @keys[tag] || @keys[entry['module']] || @keys[entry['class']]
      description = @engine.request('describe', tag: tag, key: key)
      System.new(@engine, description, key)
    elsif (label = options['label'])
      entries = catalog.select do |row|
        [row['label'], row['class'], row['module']].any? { |value| value.to_s.casecmp?(label.to_s) }
      end
      entries.map { |entry| get(options.merge('tag' => entry['tag'])) }
    else
      raise NoGetCriteriaError, "Supply a 'tag' or 'label'"
    end
  end

  def close = @engine.close

  def self.open(**options)
    factory = new(**options)
    return factory unless block_given?
    begin
      yield factory
    ensure
      factory.close
    end
  end

  class Station
    attr_reader :id, :name, :latitude, :longitude, :bikes, :free, :timestamp, :extra
    def initialize(row)
      @id, @name = row.fetch('id'), row.fetch('name')
      @latitude, @longitude = row.fetch('latitude'), row.fetch('longitude')
      @bikes, @free, @extra = row['bikes'], row['free'], row.fetch('extra', {})
      @timestamp = row['timestamp'] && Time.iso8601(row['timestamp']).utc
    end
    def get_hash = id
    def to_h
      { 'id' => id, 'name' => name, 'latitude' => latitude, 'longitude' => longitude,
        'bikes' => bikes, 'free' => free, 'timestamp' => timestamp&.iso8601(6), 'extra' => extra }
    end
    alias to_dict to_h
    def to_json(*args) = to_h.to_json(*args)
    def to_geojson
      { 'type' => 'Feature', 'geometry' => { 'type' => 'Point', 'coordinates' => [longitude, latitude] },
        'properties' => to_h.reject { |key, _| %w[id timestamp].include?(key) }.merge('type' => 'station') }
    end
  end

  class Vehicle
    attr_reader :id, :latitude, :longitude, :kind, :timestamp, :extra
    def initialize(row)
      @id, @latitude, @longitude, @kind = row.values_at('id', 'latitude', 'longitude', 'kind')
      @extra = row.fetch('extra', {})
      @timestamp = row['timestamp'] && Time.iso8601(row['timestamp']).utc
    end
    def get_hash = id
    def to_h
      { 'id' => id, 'latitude' => latitude, 'longitude' => longitude, 'kind' => kind,
        'timestamp' => timestamp&.iso8601(6), 'extra' => extra }
    end
    alias to_dict to_h
    def to_json(*args) = to_h.to_json(*args)
    def to_geojson
      { 'type' => 'Feature', 'geometry' => { 'type' => 'Point', 'coordinates' => [longitude, latitude] },
        'properties' => to_h.reject { |key, _| key == 'timestamp' }.merge('type' => 'vehicle') }
    end
  end

  class System
    attr_reader :tag, :meta, :stations, :vehicles, :authed, :sync
    def initialize(engine, description, key)
      @engine, @key = engine, key
      @tag, @meta, @authed, @sync = description.values_at('tag', 'meta', 'authed', 'sync')
      @stations, @vehicles = [], []
    end
    def update(timeout: @engine.timeout, scraper: {})
      row = @engine.request('update', timeout: timeout, tag: tag, key: @key, scraper: scraper)
      raise ProtocolError, 'Provider returned a different system' unless row.fetch('tag') == tag
      # Build the complete snapshot first, retaining the previous one on failure.
      stations = row.fetch('stations').map { |station| Station.new(station) }
      vehicles = row.fetch('vehicles', []).map { |vehicle| Vehicle.new(vehicle) }
      @meta, @stations, @vehicles = row.fetch('meta'), stations, vehicles
      self
    rescue KeyError, TypeError, ArgumentError
      raise ProtocolError, 'Provider returned an invalid snapshot'
    end
    def to_h
      { 'tag' => tag, 'meta' => meta, 'stations' => stations.map(&:to_h), 'vehicles' => vehicles.map(&:to_h) }
    end
    alias to_dict to_h
    def to_json(*args) = to_h.to_json(*args)
    def to_geojson
      { 'type' => 'FeatureCollection', 'features' => (stations + vehicles).map(&:to_geojson) }
    end
  end
end

# Preserve the exception names used by existing RubyBikes consumers.
NoSystemFoundError = RubyBikes::NoSystemFoundError unless defined?(NoSystemFoundError)
NoGetCriteriaError = RubyBikes::NoGetCriteriaError unless defined?(NoGetCriteriaError)
APIKeyNotAvailableError = RubyBikes::APIKeyNotAvailableError unless defined?(APIKeyNotAvailableError)
require_relative 'rubybikes/engine'
