# frozen_string_literal: true

class RubyBikes
  module Native
    class Engine
      MANIFEST = JSON.parse(File.read(File.join(DATA, 'upstream.json'))).freeze

      attr_reader :timeout

      def initialize(timeout: 60)
        @timeout = Float(timeout)
        raise ArgumentError, 'timeout must be positive' unless @timeout.positive? && @timeout.finite?

        @providers = JSON.parse(File.read(File.join(DATA, 'providers.json')))
        @definitions = {}
        Dir[File.join(DATA, 'pybikes/*.json')].each do |file|
          schema = JSON.parse(File.read(file))
          classes = schema['class'].is_a?(Hash) ? schema['class'] : { schema['class'] => schema }
          classes.each do |name, group|
            catalog_instances(group['instances']).each do |params|
              @definitions[params.fetch('tag')] = { 'module' => schema.fetch('system'), 'class' => name, 'parameters' => params }
            end
          end
        end
        @mutex = Mutex.new
        @cooldowns = {}
        @systems = {}
        @response_cache = ResponseCache.new
      end

      def request(operation, timeout: @timeout, **arguments)
        result = @mutex.synchronize do
          case operation
          when 'version'
            { 'implementation' => 'ruby', 'version' => RubyBikes::VERSION, 'revision' => MANIFEST.fetch('revision'), 'protocol' => 1 }
          when 'providers'
            { 'providers' => @providers.map { |spec| spec.except('meta', 'gbfs', 'required_parameters') } }
          when 'catalog'
            networks = @definitions.map do |tag, definition|
              spec = find_spec(definition)
              { 'tag' => tag, 'module' => spec['module'], 'class' => spec['class'], 'label' => spec['label'],
                'authed' => spec['authed'], 'sync' => spec['sync'], 'unifeed' => spec['unifeed'],
                'endpoint_host' => URI(definition['parameters']['feed_url'] || definition['parameters']['endpoint'] || '').host,
                'meta' => spec.fetch('meta').merge(definition['parameters'].fetch('meta')) }
            end
            { 'networks' => networks.sort_by { |row| row['tag'] } }
          when 'describe', 'update'
            definition = arguments[:definition] || @definitions[arguments.fetch(:tag)]
            raise NoSystemFoundError, 'Unknown system tag' unless definition

            spec = find_spec(definition)
            params = definition.fetch('parameters').merge('tag' => arguments.fetch(:tag))
            missing = spec.fetch('required_parameters').reject { |name| params.key?(name) }
            raise ProviderError, "Missing provider parameters: #{missing.join(', ')}" unless missing.empty?

            klass = if spec['gbfs']
                      Gbfs
                    elsif %w[Nextbike Bizkaibizi].include?(spec['class'])
                      Nextbike
                    else
                      JsonProviders
                    end
            key = JSON.parse(JSON.generate(arguments[:key]))
            identity = JSON.generate([arguments.fetch(:tag), key, definition])
            provider = @systems[identity] ||= klass.new(spec, params, key: key)
            if operation == 'describe'
              { 'tag' => provider.tag, 'meta' => provider.meta, 'module' => spec['module'], 'class' => spec['class'],
                'authed' => spec['authed'], 'sync' => spec['sync'], 'unifeed' => spec['unifeed'] }
            else
              options = JSON.parse(JSON.generate(arguments[:scraper] || {})).transform_keys(&:to_sym)
              cooldowns = @cooldowns.merge(options.delete(:cooldowns) || {})
              begin
                cache = spec['unifeed'] && !spec['authed'] ? @response_cache : nil
                transport = Transport.new(timeout: timeout, cooldowns: cooldowns, cache: cache, **options)
                transport.within_deadline { provider.snapshot(transport) }
              ensure
                @cooldowns.merge!(cooldowns)
              end
            end
          else
            raise ArgumentError, 'Unknown engine operation'
          end
        end
        JSON.parse(JSON.generate(result))
      rescue Error
        raise
      rescue StandardError => e
        raise ProviderError, "Provider update failed (#{e.class.name})"
      end

      def close; end

      private

      def catalog_instances(value) = Array(value)

      def find_spec(definition)
        @providers.find { |spec| spec['module'] == definition['module'] && spec['class'] == definition['class'] } ||
          raise(NoSystemFoundError, 'Unknown provider class')
      end
    end
  end
end
