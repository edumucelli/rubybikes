# frozen_string_literal: true

# Adapted from PyBikes gbfs.py, Copyright eskerda and contributors, AGPL-3.0.
class RubyBikes
  module Native
    class Gbfs < Provider
      def initialize(spec, parameters, key: nil)
        super
        @feed_url = case spec.fetch('class')
                    when 'BCycle'
                      @meta['company'] = @parameters['meta']['company'] + spec.fetch('meta').fetch('company') if @parameters.fetch('meta').key?('company')
                      "https://gbfs.bcycle.com/#{@parameters.fetch('uid')}/gbfs.json"
                    when 'Cyclocity' then "https://api.cyclocity.fr/contracts/#{@parameters.fetch('contract').downcase}/gbfs/gbfs.json"
                    when 'Ecovelo' then "https://api.gbfs.ecovelo.mobi/#{@parameters.fetch('dataset')}/gbfs.json"
                    when 'Careem' then 'https://dubai.publicbikesystem.net/customer/gbfs/v2/en/gbfs.json'
                    when 'Ambici' then 'https://gbfs.nextbike.net/maps/gbfs/v2/nextbike_bs/gbfs.json'
                    when 'NextbikeGbfs' then "https://gbfs.nextbike.net/maps/gbfs/v2/nextbike_#{@parameters.fetch('domain')}/gbfs.json"
                    when 'DB', 'Callabike'
                      domain = spec['class'] == 'Callabike' ? 'CallABike' : @parameters.fetch('provider')
                      "https://apis.deutschebahn.com/db-api-marketplace/apis/shared-mobility-gbfs/v2/de/#{domain}/gbfs"
                    when 'HelloCycling', 'Docomo'
                      name = spec['class'] == 'Docomo' ? 'docomo-cycle' : 'hellocycling'
                      features = JSON.parse(File.read(File.join(Native::DATA, 'geojson/japan_prefectures.json'))).fetch('features')
                      feature = features.find { |item| item['properties']['id'] == @parameters.fetch('uid') }
                      raise ArgumentError, 'Unknown Japanese prefecture' unless feature

                      @parameters['bbox'] = feature.fetch('geometry')
                      "https://api-public.odpt.org/api/v4/gbfs/#{name}/gbfs.json"
                    else @parameters.fetch('feed_url')
                    end
        @meta['gbfs_href'] = @feed_url
      end

      def update
        case spec.fetch('class')
        when 'DB', 'Callabike'
          @transport.headers.merge!('DB-Client-Id' => @key.fetch('client_id'), 'DB-Api-Key' => @key.fetch('client_secret'), 'Accept' => 'application/json')
        when 'SharedMobility'
          @transport.headers['Authorization'] = @key
        end
        args = p('append_feed_args_to_req') ? URI.decode_www_form(URI(@feed_url).query || '') : nil
        feeds = discover_feeds(args)
        information = json(feeds.fetch('station_information'), params: args).fetch('data').fetch('stations')
        statuses = json(feeds.fetch('station_status'), params: args).fetch('data').fetch('stations').to_h { |item| [item.fetch('station_id'), item] }
        # @type var types: Hash[String, untyped]
        types = if feeds['vehicle_types']
                  json(feeds['vehicle_types'], params: args).fetch('data').fetch('vehicle_types', list(nil)).to_h { |item| [item.fetch('vehicle_type_id'), item] }
                else
                  {}
                end
        information.to_h { |item| [item.fetch('station_id'), item] }.each_value do |item|
          next unless statuses.key?(item['station_id'])
          next if p('region_id') && item['region_id'] != p('region_id')

          item = item.merge(statuses.fetch(item['station_id']).compact)
          next unless truthy?(item.fetch('is_installed'))

          begin
            parse_gbfs_station(item, types)
          rescue RubyBikes::Error
            raise
          rescue StandardError
            raise unless p('ignore_errors')
          end
        end
        vehicles_feed = feeds['free_bike_status'] || feeds['vehicle_status']
        return unless vehicles_feed

        data = json(vehicles_feed, params: args).fetch('data')
        list(data['bikes'] || data['vehicles']).each do |item|
          next if item.key?('station_id')

          kind = if item['vehicle_type_id']
                   type = types[item['vehicle_type_id']]
                   next unless type

                   vehicle_kind(type).last
                 else
                   'bike'
                 end
          next unless kind

          kind = { 'electric_bike' => 'ebike', 'electric_scooter' => 'scooter' }.fetch(item['type'], kind)
          extra = { 'uid' => item['bike_id'] || item['vehicle_id'], 'online' => !truthy?(item.fetch('is_disabled')) }
          extra['battery'] = Float(item['current_fuel_percent']) if item.key?('current_fuel_percent')
          vehicle(item.fetch('lat'), item.fetch('lon'), extra, kind)
        end
      end

      def vehicle_kind(type)
        form, power = type.values_at('form_factor', 'propulsion_type')
        return %w[scooters scooter] if form.is_a?(String) && form.include?('scooter') && power == 'electric'
        return %w[cargo bike] if form == 'cargo_bicycle' && power == 'human'
        return %w[ecargo ebike] if form == 'cargo_bicycle' && power == 'electric_assist'
        return %w[normal_bikes bike] if form == 'bicycle' && power == 'human'
        return %w[ebikes ebike] if form == 'bicycle' && %w[electric_assist electric].include?(power)

        [nil, nil]
      end

      private

      def discover_feeds(args)
        feeds = %w[station_information station_status vehicle_types free_bike_status vehicle_status].to_h { |name| [name, p(name)] }.compact
        if feeds.empty?
          raw = request(@feed_url, params: args)
          if @transport.last_response.status >= 400
            raise ProviderError, 'Provider authorization failed' if @transport.last_response.status == 401

            feeds = %w[station_information station_status].to_h { |name| [name, URI.join(@feed_url, "#{name}.json").to_s] }
          else
            data = JSON.parse(raw).fetch('data')
            data = data['en'] || data.values.last if data.is_a?(Hash) && !data.key?('feeds')
            data = data.fetch('feeds') if data.is_a?(Hash)
            feeds = data.to_h { |feed| [feed.fetch('name'), feed.fetch('url')] }
          end
        end
        feeds.transform_values { |url| p('force_https') ? url.sub(/^http:/, 'https:') : url }
      end

      def parse_gbfs_station(item, types)
        name = item['name'].is_a?(Array) ? item['name'].first.fetch('text') : item['name']
        bikes = integer(item.key?('num_bikes_available') ? item['num_bikes_available'] : item['num_vehicles_available'])
        extra = { 'uid' => item['station_id'], 'renting' => item.fetch('is_renting'), 'returning' => item.fetch('is_returning'),
                  'virtual' => item.fetch('is_virtual_station', false) }
        extra['last_updated'] = iso_date(item['last_reported']) if item.key?('last_reported')
        %w[address post_code altitude].each { |field| extra[field] = item[field] if item.key?(field) }
        extra['rental_uris'] = item['rental_uris'].slice('android', 'ios', 'web') if item['rental_uris'].is_a?(Hash)
        extra['slots'] = item['capacity'] if item.key?('capacity')
        if item.key?('rental_methods')
          extra['payment'] = item['rental_methods'].map(&:downcase)
          extra['payment-terminal'] = extra['payment'].include?('creditcard')
        end
        extra.merge!('has_ebikes' => true, 'ebikes' => integer(item['num_ebikes_available'])) if item.key?('num_ebikes_available')
        available_types = item['num_bikes_available_types']
        if available_types.is_a?(Hash) && available_types.key?('ebike')
          extra.merge!('has_ebikes' => true, 'ebikes' => integer(available_types['ebike']), 'normal_bikes' => integer(available_types.fetch('mechanical')))
        end
        list(item['vehicle_types_available']).each do |available|
          type = types[available['vehicle_type_id']]
          next unless type

          field, = vehicle_kind(type)
          next unless field

          extra[field] = extra.fetch(field, 0) + available.fetch('count')
          extra["has_#{field}"] = true unless field == 'normal_bikes'
        end
        bikes = extra.fetch('normal_bikes', 0) + extra.fetch('ebikes', 0) if item.key?('vehicle_types_available') && (!bikes || bikes.zero?)
        case spec['class']
        when 'Velib'
          extra['uid'] = item.fetch('stationCode')
          extra['station_id'] = item.fetch('station_id')
          extra['banking'] = extra.fetch('payment', []).include?('creditcard')
          extra['payment-terminal'] = extra['banking']
          list(available_types).each do |type|
            next unless type.is_a?(Hash)

            extra['ebikes'] = number(type['ebike']) if type.key?('ebike')
            extra['normal_bikes'] = number(type['mechanical']) if type.key?('mechanical')
          end
        when 'BCycle'
          extra.merge!('has_ebikes' => true, 'ebikes' => number(available_types.fetch('electric')), 'normal_bikes' => number(available_types.fetch('classic')))
        end
        station(name, item.fetch('lat'), item.fetch('lon'), bikes, integer(item['num_docks_available']), extra)
      end
    end
  end
end
