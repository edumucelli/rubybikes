# frozen_string_literal: true

class RubyBikes
  module Native
    module Geometry
      module_function

      def contains?(bounds, latitude, longitude)
        return true unless bounds && !bounds.empty?

        if bounds.is_a?(Array)
          unless bounds.length == 4 || (bounds.length == 2 && bounds.all? { |point| point.is_a?(Array) && point.length == 2 })
            raise ArgumentError, 'Bounds must contain four coordinates or two latitude/longitude pairs'
          end

          west, south, east, north = bounds.length == 4 ? bounds : [bounds[1][1], bounds[1][0], bounds[0][1], bounds[0][0]]
          horizontal = [Float(west, exception: true), Float(east, exception: true)].sort
          vertical = [Float(south, exception: true), Float(north, exception: true)].sort
          west, east = horizontal.fetch(0), horizontal.fetch(1)
          south, north = vertical.fetch(0), vertical.fetch(1)
          return west < longitude && longitude < east && south < latitude && latitude < north
        end
        geometry = bounds['geometry'] || bounds
        case geometry.fetch('type')
        when 'FeatureCollection'
          geometry.fetch('features').any? { |feature| contains?(feature, latitude, longitude) }
        when 'Polygon'
          polygon?(geometry.fetch('coordinates'), longitude, latitude)
        when 'MultiPolygon'
          geometry.fetch('coordinates').any? { |polygon| polygon?(polygon, longitude, latitude) }
        else
          raise ArgumentError, 'Unsupported geographic bounds'
        end
      end

      def polygon?(rings, x, y)
        ring(rings.first, x, y) == :inside && rings.drop(1).all? { |hole| ring(hole, x, y) == :outside }
      end

      def ring(points, x, y)
        inside = false
        points.each_with_index do |(ax, ay), index|
          bx, by = points[(index + 1) % points.size]
          cross = ((x - ax) * (by - ay)) - ((y - ay) * (bx - ax))
          return :boundary if cross.zero? && x.between?(*[ax, bx].minmax) && y.between?(*[ay, by].minmax)

          inside = !inside if (ay > y) != (by > y) && x < ((bx - ax) * (y - ay) / (by - ay).to_f) + ax
        end
        inside ? :inside : :outside
      end
    end
  end
end
