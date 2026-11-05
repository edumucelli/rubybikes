# frozen_string_literal: true

class RubyBikes
  module Native
    # A bounded response cache. Expiry uses the caller's monotonic clock;
    # reads do not extend a response's lifetime.
    class ResponseCache
      Entry = Struct.new(:response, :stored_at, :bytes, keyword_init: true)

      def initialize(ttl: 60, max_bytes: 32 * 1024 * 1024, max_entries: 128)
        raise ArgumentError, 'cache TTL must be positive and finite' unless ttl.positive? && ttl.finite?
        raise ArgumentError, 'cache byte limit must be positive' unless max_bytes.positive?
        raise ArgumentError, 'cache entry limit must be positive' unless max_entries.positive?

        @ttl, @max_bytes, @max_entries = ttl, max_bytes, max_entries
        @entries = {}
        @bytes = 0
        @mutex = Mutex.new
      end

      def get(key, now)
        atomic do
          expire(now)
          @entries[key]&.response
        end
      end

      def put(key, response, now)
        size = response.body.bytesize
        if size > @max_bytes
          atomic do
            expire(now)
            previous = @entries.delete(key)
            @bytes -= previous.bytes if previous
          end
          return nil
        end
        # The transport exposes mutable configuration and last_response, so
        # neither the caller's cache key nor response should back stored data.
        saved_key = Marshal.load(Marshal.dump(key))
        saved_response = response.dup
        saved_response.body = response.body.dup.freeze
        saved_response.headers = response.headers.transform_values { |value| value.dup.freeze }.freeze
        saved_response.freeze
        atomic do
          expire(now)
          previous = @entries.delete(key)
          @bytes -= previous.bytes if previous
          while @entries.length >= @max_entries || @bytes + size > @max_bytes
            oldest = @entries.shift
            @bytes -= oldest[1].bytes if oldest
          end
          @entries[saved_key] = Entry.new(response: saved_response, stored_at: now, bytes: size)
          @bytes += size
        end
        nil
      end

      private

      def atomic(&block)
        # Defer asynchronous timer delivery only while updating accounting.
        # Synchronous errors still propagate; no network I/O runs here.
        Thread.handle_interrupt(Exception => :never) do
          @mutex.synchronize(&block)
        end
      end

      def expire(now)
        @entries.delete_if do |_, entry|
          expired = now - entry.stored_at >= @ttl
          @bytes -= entry.bytes if expired
          expired
        end
      end
    end
  end
end
