# frozen_string_literal: true

# Native adaptations of PyBikes HTML clients. Original work Copyright eskerda,
# Martín González Gómez, Eduardo Mucelli Rezende Oliveira, thesebas and iomartin.
# Distributed under the AGPL-3.0 license; see LICENSE.
require 'strscan'

class RubyBikes
  module Native
    # A data-only reader for the array/tuple literals published by Samba.
    # Identifiers, calls, interpolation and executable expressions are rejected.
    class DataLiteral
      def self.parse(source)
        raise ProviderError, 'Provider literal is too large' if source.bytesize > 2 * 1024 * 1024

        new(source).parse
      end

      def initialize(source)
        @scanner = StringScanner.new(source)
      end

      def parse
        result = value(0)
        whitespace
        raise ProviderError, 'Invalid provider data literal' unless @scanner.eos?

        result
      end

      private

      def whitespace
        @scanner.skip(/\s*/)
      end

      def value(depth)
        raise ProviderError, 'Provider literal is too deeply nested' if depth > 64

        whitespace
        opening = @scanner.peek(1)
        return sequence(depth, opening == '[' ? ']' : ')') if ['[', '('].include?(opening)
        return string if ["'", '"'].include?(opening)

        number = @scanner.scan(/[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/)
        return number.match?(/[.eE]/) ? Float(number) : Integer(number, 10) if number

        token = @scanner.scan(/(?:True|False|None|true|false|null)\b/)
        return { 'True' => true, 'true' => true, 'False' => false, 'false' => false, 'None' => nil, 'null' => nil }.fetch(token) if token

        raise ProviderError, 'Invalid provider data literal'
      end

      def sequence(depth, closing)
        @scanner.getch
        # @type var items: Array[RubyBikes::json]
        items = []
        whitespace
        return items if @scanner.scan(Regexp.new(Regexp.escape(closing)))

        loop do
          items << value(depth + 1)
          whitespace
          return items if @scanner.scan(Regexp.new(Regexp.escape(closing)))
          unless @scanner.scan(/,/) # rubocop:disable Style/RedundantRegexpArgument -- Ruby 3.1 compatibility.
            raise ProviderError,
                  'Invalid provider data literal'
          end

          whitespace
          return items if @scanner.scan(Regexp.new(Regexp.escape(closing)))
        end
      end

      def string
        quote = @scanner.getch
        result = +''
        until @scanner.eos?
          character = @scanner.getch
          return result if character == quote

          if character == '\\'
            escaped = @scanner.getch
            raise ProviderError, 'Invalid provider string literal' unless escaped

            character = case escaped
                        when 'n' then "\n"
                        when 'r' then "\r"
                        when 't' then "\t"
                        when 'b' then "\b"
                        when 'f' then "\f"
                        when 'v' then "\v"
                        when 'a' then "\a"
                        when '\\', "'", '"', '/' then escaped
                        when "\n" then ''
                        when 'x', 'u', 'U'
                          width = { 'x' => 2, 'u' => 4, 'U' => 8 }.fetch(escaped)
                          hexadecimal = @scanner.scan(/[0-9a-fA-F]{#{width}}/)
                          raise ProviderError, 'Invalid provider string escape' unless hexadecimal

                          [hexadecimal.to_i(16)].pack('U')
                        else "\\#{escaped}"
                        end
          end
          raise ProviderError, 'Invalid provider string literal' unless character

          result << character
        end
        raise ProviderError, 'Unterminated provider string literal'
      end
    end

    class JsonProviders
      EMOVITY_USER_AGENT = 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4572.0 Safari/537.36'
      SAMBA_USER_AGENT = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/31.0.1650.63 Chrome/31.0.1650.63 Safari/537.36'

      def update_bicielx
        raw = request('https://gestion.bicielx.es/mapa_prestamo.php')
        html_scan(raw, %r{var circle = .*?</div>"\)}m).each do |marker|
          name = html_capture(marker, %r{'>(.*?)</h2}m)
          coordinates = html_capture(marker, /\[([^\]]+)\]/).split(',')
          availability = html_match(marker, /libres: (\d+).*disponibles: (\d+)/m)
          uid = html_capture(marker, /"([^"]+)"/)
          station(name, coordinates.fetch(0), coordinates.fetch(1), number(availability[2]), number(availability[1]), { 'uid' => number(uid) })
        end
      end

      def update_biciferrolterra
        raw = request(p('url'))
        coordinates = html_scan(raw, /new GMarker\([\s\S]*?\)\s*;/).uniq
        availability = html_scan(raw, /GEvent.addListener\(marker_subguri[\s\S]*?\)\s*;/)
        coordinates.zip(availability).each do |coords, info|
          raise ProviderError, 'Provider station availability is missing' unless info

          lat, lon = html_scan(coords, /-?\d+\.\d+/).map { |number| Float(number) }
          bikes = number(html_capture(info, /Bicicletas dispoñibles: (-?\d+)/))
          free = number(html_capture(info, /Postos libres: (-?\d+)/))
          station(html_capture(coords, /title:'(.*?)'/), lat, lon, bikes, free,
                  { 'slots' => bikes + free, 'schedule' => html_capture(info, %r{Horario: ([^<]+)</}) })
        end
      end

      def update_bikeu
        raw = request(p('url'))
        data = JSON.parse(html_capture(raw, /setConfig\('StationsData',(\[.*\])\);/))
        data.each do |info|
          bikes = number(info.fetch('TotalAvailableBikes'))
          station(info.fetch('Name'), info.fetch('Latitude'), info.fetch('Longitude'), bikes,
                  number(info.fetch('TotalLocks')) - bikes, { 'uid' => info.fetch('id') })
        end
      end

      def update_emovity
        @transport.headers['User-Agent'] = EMOVITY_USER_AGENT
        raw = request(p('feed_url'))
        html_scan(raw, /addMarker\((-?\d+[.,]\d+),(-?\d+[.,]\d+),(\d+),(\d+),'(.*)'\);/).each do |lat, lon, bikes, free, popup|
          name = Nokogiri::HTML.fragment(popup).xpath('.//div/text()').first&.text
          raise ProviderError, 'Provider station name is missing' unless name

          station(name, lat.tr(',', '.'), lon.tr(',', '.'), number(bikes), number(free),
                  { 'uid' => html_capture(name, /(\d+)\s*-/) })
        end
      end

      def update_gyorbike
        raw = request('https://www.gyorbike.hu/en/stations')
        document = Nokogiri::HTML(raw)
        markers = JSON.parse(html_capture(raw, /gMap.markerData=(.*);gMap.listenerParams/))
        rows = document.xpath('//table[@id="cmeStationInfo"]//tr[@id]').to_h { |row| [row['id'].sub(/\Atr-/, ''), row] }
        markers.each do |marker|
          row = rows[marker.fetch('station_num').to_s]
          next unless row

          name = html_text(row, '[data-title="Station name"] .inner').split('Offline').first.to_s.strip
          normal = gyorbike_count(row, 'Standard bike')
          electric = gyorbike_count(row, 'E-bike')
          station(name, marker.fetch('lat'), marker.fetch('lng'), normal + electric, gyorbike_count(row, 'Available dock'),
                  { 'uid' => marker.fetch('station_num'), 'slots' => marker.fetch('docks'), 'normal_bikes' => normal,
                    'ebikes' => electric, 'online' => !row['class'].to_s.include?('offline') })
        end
      end

      def update_meiob
        html(p('endpoint')).css('.bikes > .bike').each do |item|
          names = html_text(item, '.stationlon + .border-right-blue > h2').split(' - ')
          name = names.length == 2 ? names[1] : names[0]
          availability = item.css('.bike__available').map(&:text)
          addresses = item.css('.bike__distance__title').map(&:text)
          station(name, html_text(item, '.stationlat'), html_text(item, '.stationlon'), number(availability.fetch(0)), number(availability.fetch(1)),
                  { 'address' => addresses.fetch(0), 'city' => addresses.fetch(1) })
        end
      end

      def update_mobhis
        raw = request(p('feed_url'))
        coordinates = html_scan(raw, /var marker = L\.marker\(\[(-?\d+\.\d+),\s*(-?\d+\.\d+)\]/)
        popups = html_scan(raw, /marker.bindPopup\("(.*)"\)/).flatten
        coordinates.zip(popups).each do |(lat, lon), popup|
          raise ProviderError, 'Provider station popup is missing' unless popup

          online = !popup.include?('Estação offline')
          unless online
            station(nil, lat, lon, 0, 0, { 'online' => false })
            next
          end
          texts = Nokogiri::HTML.fragment(popup).xpath('.//text()').map(&:text)
          name = texts.shift
          remaining = texts.join(' ')
          bikes = html_scan(remaining, /(\d+) bikes/).flatten.map { |number| number(number) }
          spaces = html_scan(remaining, /(\d+) vagas/).flatten.map { |number| number(number) }
          extra = { 'online' => true }
          extra.merge!('kid_bikes' => bikes[1], 'kid_slots' => spaces[1]) if bikes.length > 1 && spaces.length > 1
          station(name, lat, lon, bikes.fetch(0), spaces.fetch(0), extra)
        end
      end

      def update_movus
        raw = request(p('feed_url'))
        match = raw.match(/var misPuntos = \[(.*?)\];/m)
        markers = if match
                    JSON.parse("[#{match[1].to_s.sub(/,\s*\z/, '')}]")
                  else
                    # Current MIBISI pages publish station records through the
                    # JSON endpoint referenced by their map script.
                    document = Nokogiri::HTML(raw)
                    script = document.at_css('script[src$="assets/js/map.js"], script[src$="/map.js"]')
                    raise ProviderError, 'Provider page is missing its station map' unless script

                    script_url = URI.join(p('feed_url'), script['src']).to_s
                    endpoint = html_capture(request(script_url), /fetch\(\s*['"]([^'"]+)['"]\s*\)/)
                    json(URI.join(p('feed_url'), endpoint).to_s).map do |record|
                      [record.fetch('nombre'), record.fetch('lat'), record.fetch('lng'), nil, record.fetch('html')]
                    end
                  end
        markers.each do |name, lat, lon, _unused, info|
          next unless truthy?(lat) && truthy?(lon)

          if info.match?(/Actualiz[aá]ndose/i)
            station(name, lat, lon, 0)
          elsif p('ebikes')
            counts = html_match(info, /mecánicas:\s*(\d+).*eléctricas:\s*(\d+).*libres:\s*(\d+)/m)
            electric = number(counts[2])
            station(name, lat, lon, number(counts[1]) + electric, number(counts[3]), { 'ebikes' => electric })
          else
            counts = html_match(info, /Totales\s*=\s*(\d+).*disponibles\s*=\s*(\d+).*libres\s*=\s*(-?\d+)/m)
            station(name, lat, lon, number(counts[2]), [number(counts[3]), 0].max, { 'slots' => number(counts[1]) })
          end
        end
      end

      def update_samba
        @transport.headers['User-Agent'] = SAMBA_USER_AGENT
        raw = request(p('url'))
        literal = html_capture(raw, /var\s+beaches\s*=\s*(\[.*?\])\s*;/m)
        data = DataLiteral.parse(literal)
        raise ProviderError, 'Provider stations must be a list' unless data.is_a?(Array)

        data.each do |data|
          # @type var data: untyped
          operation = data.fetch(6)
          status = if %w[EI EM].include?(operation)
                     'maintenance/implementation'
                   elsif data.fetch(5) == 'A' && operation == 'EO'
                     'open'
                   else
                     'closed'
                   end
          station(data.fetch(0), data.fetch(1), data.fetch(2), number(data.fetch(8)), number(data.fetch(9)),
                  { 'address' => data.fetch(4), 'description' => data.fetch(3), 'status' => status })
        end
      end

      def update_velobike_kz
        html(p('feed_url')).xpath('//table[contains(@class, "table-stations")]//tbody//tr').each do |row|
          extra = { 'online' => row.xpath('.//td[span]').empty?, 'slots' => velobike_number(row['data-total-slots']),
                    'address' => html_text(row, 'td.address').strip, 'uid' => html_text(row, 'th.code').strip }
          station(html_text(row, 'td.name').strip, row['data-latitude'], row['data-longitude'],
                  velobike_number(html_text(row, 'td.avl-bikes').strip), velobike_number(html_text(row, 'td.free-slots').strip), extra)
        end
      end

      private

      def html_scan(source, pattern) = source.scan(pattern)

      def html_match(source, pattern)
        source.match(pattern) || raise(ProviderError, 'Provider page is missing required station data')
      end

      def html_capture(source, pattern)
        html_match(source, pattern)[1] || raise(ProviderError, 'Provider page is missing a capture')
      end

      def html_text(node, selector)
        element = node.at_css(selector)
        raise ProviderError, 'Provider page is missing a required station field' unless element

        element.text
      end

      def gyorbike_count(row, title)
        value = html_text(row, "[data-title=\"#{title}\"] .inner")
        value.include?('--') ? 0 : number(value)
      end

      def velobike_number(value)
        number(value)
      rescue ArgumentError
        0
      end
    end
  end
end
