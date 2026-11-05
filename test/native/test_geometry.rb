# frozen_string_literal: true

require_relative 'test_helper'

class NativeGeometryTest < Minitest::Test
  Geometry = RubyBikes::Native::Geometry
  OUTER = [[-10, -10], [10, -10], [10, 10], [-10, 10], [-10, -10]].freeze
  HOLE = [[-2, -2], [-2, 2], [2, 2], [2, -2], [-2, -2]].freeze

  def test_missing_or_empty_bounds_do_not_filter
    [nil, [], {}].each { |bounds| assert Geometry.contains?(bounds, -22.1, -43.2) }
  end

  def test_bbox_order_is_longitude_latitude_and_boundaries_are_excluded
    bounds = [-75, 40, -70, 50]

    assert Geometry.contains?(bounds, 45, -73)
    refute Geometry.contains?(bounds, -73, 45)
    [[40, -73], [50, -73], [45, -75], [45, -70]].each do |lat, lon|
      refute Geometry.contains?(bounds, lat, lon)
    end
    assert Geometry.contains?([-70, 50, -75, 40], 45, -73)
  end

  def test_two_latitude_longitude_pairs_and_reversed_corners
    assert Geometry.contains?([[50, -70], [40, -75]], 45, -73)
    assert Geometry.contains?([[40, -75], [50, -70]], 45, -73)
    refute Geometry.contains?([[50, -70], [40, -75]], 55, -73)
  end

  def test_polygon_with_holes_and_feature_wrapper
    bounds = { 'type' => 'Polygon', 'coordinates' => [OUTER, HOLE] }

    assert Geometry.contains?(bounds, 5, 5)
    refute Geometry.contains?(bounds, 0, 0)
    refute Geometry.contains?(bounds, 2, 0)
    refute Geometry.contains?(bounds, 10, 0)
    refute Geometry.contains?(bounds, 11, 0)
    assert Geometry.contains?({ 'type' => 'Feature', 'geometry' => bounds, 'properties' => {} }, -5, -5)
  end

  def test_open_ring_and_reversed_winding_work
    bounds = { 'type' => 'Polygon', 'coordinates' => [OUTER.take(4).reverse] }

    assert Geometry.contains?(bounds, 0, 0)
    refute Geometry.contains?(bounds, 20, 20)
  end

  def test_near_boundary_inside_point_is_not_treated_as_boundary
    bounds = { 'type' => 'Polygon', 'coordinates' => [OUTER] }

    assert Geometry.contains?(bounds, 0, -10 + 1e-14)
  end

  def test_multipolygon_and_feature_collection
    shifted = OUTER.map { |x, y| [x + 40, y] }
    bounds = { 'type' => 'MultiPolygon', 'coordinates' => [[OUTER, HOLE], [shifted]] }

    assert Geometry.contains?(bounds, 5, 5)
    assert Geometry.contains?(bounds, 0, 40)
    refute Geometry.contains?(bounds, 0, 20)
    collection = { 'type' => 'FeatureCollection', 'features' => [{ 'type' => 'Feature', 'geometry' => bounds }] }

    assert Geometry.contains?(collection, 0, 40)
  end

  def test_invalid_bounds_have_actionable_errors
    assert_raises(ArgumentError) { Geometry.contains?([1, 2, 3], 0, 0) }
    assert_raises(ArgumentError) { Geometry.contains?([[1], [2]], 0, 0) }
    assert_raises(ArgumentError) { Geometry.contains?({ 'type' => 'Point', 'coordinates' => [0, 0] }, 0, 0) }
  end
end
