require 'json'
require 'open3'
require 'thread'

class RubyBikes
  class Engine
    MAX_RESPONSE_BYTES = 64 * 1024 * 1024
    BRIDGE = File.expand_path('pybikes_bridge.py', __dir__)
    MANIFEST = JSON.parse(File.read(File.expand_path('engine.json', __dir__))).freeze

    attr_reader :timeout

    def initialize(python: ENV.fetch('RUBYBIKES_PYTHON', 'python3'), timeout: 60, bridge: BRIDGE)
      @python, @timeout, @bridge = python, Float(timeout), bridge
      raise ArgumentError, 'timeout must be positive' unless @timeout.positive? && @timeout.finite?
      @mutex = Mutex.new
      @sequence = 0
      @owner = Process.pid
      @buffer = +''
    end

    def request(operation, timeout: @timeout, **arguments)
      @mutex.synchronize do
        seconds = Float(timeout)
        raise ArgumentError, 'timeout must be positive' unless seconds.positive? && seconds.finite?
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        start
        @sequence += 1
        message = arguments.merge(op: operation, id: @sequence)
        write_line(JSON.generate(message) + "\n", deadline)
        response = JSON.parse(read_line(deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)))
        unless response.is_a?(Hash) && response['protocol'] == MANIFEST['protocol'] && response['id'] == @sequence
          raise ProtocolError, 'Provider engine returned an incompatible response'
        end
        unless response['ok']
          error = response.fetch('error')
          raise ProtocolError, 'Invalid provider error response' unless error.is_a?(Hash) && error['message'].is_a?(String)
          klass = { 'not_found' => NoSystemFoundError, 'missing_key' => APIKeyNotAvailableError,
                    'dependency_missing' => DependencyError, 'rate_limited' => RateLimitedError }.fetch(error['code'], ProviderError)
          raise klass.new(error['message'], details: error)
        end
        response.fetch('result')
      rescue JSON::ParserError, KeyError, IOError, SystemCallError => error
        stop
        raise ProtocolError, "Provider engine communication failed (#{error.class})"
      rescue TimeoutError, ProtocolError
        stop
        raise
      end
    end

    def close
      @mutex.synchronize { stop }
    end

    private

    def start
      if @owner != Process.pid
        [@input, @output, @error].each { |stream| stream.close unless stream.nil? || stream.closed? }
        @input = @output = @error = @waiter = @stderr_reader = nil
        @owner = Process.pid
      end
      return if @waiter && @waiter.alive?
      stop
      @input, @output, @error, @waiter = Open3.popen3(@python, '-I', '-u', @bridge, pgroup: true)
      @buffer = +''
      @stderr_reader = Thread.new do
        begin
          @error.readpartial(4096) while !@error.closed?
        rescue EOFError, IOError
          nil
        end
      end
      @stderr_reader.report_on_exception = false
    rescue Errno::ENOENT
      raise DependencyError, 'Python is unavailable; configure RUBYBIKES_PYTHON and install the pinned provider engine'
    end

    def write_line(message, deadline)
      raise ProtocolError, 'Provider request exceeded the size limit' if message.bytesize > 2 * 1024 * 1024
      offset = 0
      while offset < message.bytesize
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        unless remaining.positive? && IO.select(nil, [@input], nil, remaining)
          raise TimeoutError, 'Provider update exceeded its deadline'
        end
        written = @input.write_nonblock(message.byteslice(offset..), exception: false)
        offset += written unless written == :wait_writable
      end
    end

    def read_line(timeout)
      raise TimeoutError, 'Provider update exceeded its deadline' unless timeout.positive?
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        if (newline = @buffer.index("\n"))
          line = @buffer.slice!(0, newline + 1)
          return line
        end
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        unless remaining.positive? && IO.select([@output], nil, nil, remaining)
          raise TimeoutError, 'Provider update exceeded its deadline'
        end
        chunk = @output.read_nonblock(65536, exception: false)
        next if chunk == :wait_readable
        raise ProtocolError, 'Provider engine exited without a response' if chunk.nil?
        @buffer << chunk
        raise ProtocolError, 'Provider response exceeded the size limit' if @buffer.bytesize > MAX_RESPONSE_BYTES
      end
    end

    def stop
      return if @owner != Process.pid
      if @waiter&.alive?
        begin
          Process.kill('TERM', -@waiter.pid)
          unless @waiter.join(0.5)
            Process.kill('KILL', -@waiter.pid)
            @waiter.join(0.5)
          end
        rescue Errno::ESRCH
          nil
        end
      end
      [@input, @output, @error].each { |stream| stream.close unless stream.nil? || stream.closed? }
      @stderr_reader&.join(0.5)
      @input = @output = @error = @waiter = @stderr_reader = nil
      @buffer = +''
    end
  end
end
