# frozen_string_literal: true

# This consumer example is typechecked, and never contacts an operator.
require 'rubybikes'

factory = RubyBikes.new(timeout: 30, keys: { 'bicimad' => { 'clientid' => 'fixture', 'passkey' => 'fixture' } })

# @type var by_string: RubyBikes::System
by_string = factory.get('velib')
# @type var by_keyword: RubyBikes::System
by_keyword = factory.get(tag: 'velib')
# @type var by_hash: RubyBikes::System
by_hash = factory.get('tag' => 'velib')
# @type var by_label: Array[RubyBikes::System]
by_label = factory.get(label: 'gbfs')
# @type var legacy_label: Array[RubyBikes::System]
legacy_label = factory.get('label' => 'gbfs')

# @type var custom: RubyBikes::System
custom = factory.build(provider: 'NextbikeGbfs', tag: 'custom', meta: { name: 'Custom' }, domain: 'bs')

by_keyword.stations.each do |station|
  # @type var coordinates: Array[Float]
  coordinates = [station.latitude, station.longitude]
  # @type var count: Integer
  count = station.bikes || 0
  # @type var name: String?
  name = station.name&.upcase
  # @type var timestamp: Time?
  timestamp = station.timestamp
  # @type var document: String
  document = station.to_json
  [coordinates, count, name, timestamp, document]
end

# @type var tags: Array[String]
tags = RubyBikes.open(&:tags)
factory.close

[by_string, by_hash, by_label, legacy_label, custom, tags]
