# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../zillafurnituretools/mounting'

class TestMounting < Minitest::Test
  def part(name, from, to, thin)
    { id: name, name: name, min: from, max: to, thickness_axis: thin,
      thickness_mm: to[thin] - from[thin] }
  end

  def test_facade_guides_match_on_the_two_mating_parts
    front = part('Front_Facade', [0, -18, 0], [500, 0, 205], 1)
    wall = part('Drawer_Front_Wall', [18, 0, 50], [482, 18, 150], 1)
    result = ZillaFurnitureTools::Mounting.drawer_front(front, wall)
    assert_equal 4, result[:holes].size
    assert_equal [98.0, 18.0, 100.0], result[:holes][0][:xyz_mm]
    assert_equal [98.0, 0.0, 100.0], result[:holes][1][:xyz_mm]
    assert_equal [0, -1, 0], result[:holes][0][:direction]
  end

  def test_facade_blind_depth_cannot_break_through
    front = part('Front_Facade', [0, -18, 0], [500, 0, 205], 1)
    wall = part('Drawer_Front_Wall', [18, 0, 50], [482, 18, 150], 1)
    assert_raises(ArgumentError) { ZillaFurnitureTools::Mounting.drawer_front(front, wall, front_depth_mm: 16) }
  end

  def test_facade_uses_independent_clearance_and_pilot_diameters
    front = part('Front_Facade', [0, -18, 0], [500, 0, 205], 1)
    wall = part('Drawer_Front_Wall', [18, 0, 50], [482, 18, 150], 1)
    result = ZillaFurnitureTools::Mounting.drawer_front(front, wall,
      wall_clearance_diameter_mm: 6, front_pilot_diameter_mm: 3, front_depth_mm: 10)
    assert_equal [6.0, 3.0], result[:holes].first(2).map { |hole| hole[:diameter_mm] }
    assert_equal [18.0, 10.0], result[:holes].first(2).map { |hole| hole[:depth_mm] }
  end

  def test_slide_guides_use_separate_cabinet_and_drawer_datums
    cabinet = part('Left_Side', [0, 0, 0], [18, 500, 200], 0)
    drawer = part('Drawer_Left', [30.5, 0, 50], [48.5, 400, 157], 0)
    result = ZillaFurnitureTools::Mounting.slide_pair(cabinet, drawer,
      cabinet_offsets_mm: '37,101,165,325', drawer_offsets_mm: '49,209,369',
      height_from_drawer_bottom_mm: 21, diameter_mm: 5, depth_mm: 10)
    assert_equal 7, result[:holes].size
    assert_equal 12.5, result[:clearance_mm]
    assert_equal [18.0, 37.0, 71.0], result[:holes][0][:xyz_mm]
    assert_equal [-1, 0, 0], result[:holes][0][:direction]
    assert_equal [30.5, 49.0, 71.0], result[:holes][4][:xyz_mm]
    assert_equal [1, 0, 0], result[:holes][4][:direction]
  end

  def test_slide_rejects_unchecked_or_outside_positions
    cabinet = part('Left_Side', [0, 0, 0], [18, 500, 200], 0)
    drawer = part('Drawer_Left', [30.5, 0, 50], [48.5, 400, 157], 0)
    args = { cabinet_offsets_mm: '', drawer_offsets_mm: '49,209',
      height_from_drawer_bottom_mm: 21, diameter_mm: 5, depth_mm: 10 }
    assert_raises(ArgumentError) { ZillaFurnitureTools::Mounting.slide_pair(cabinet, drawer, **args) }
    assert_raises(ArgumentError) do
      ZillaFurnitureTools::Mounting.slide_pair(cabinet, drawer, **args.merge(cabinet_offsets_mm: '37,499'))
    end
  end
end
