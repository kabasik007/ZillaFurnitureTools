# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../zillafurnituretools/hardware'

class TestHardware < Minitest::Test
  def panel(id, from, to, thin)
    { id: id, name: id, min: from, max: to,
      thickness_axis: thin, thickness_mm: to[thin] - from[thin], kind: 'cabinet' }
  end

  def parts
    [panel('side', [0, 0, 0], [18, 400, 300], 0),
     panel('bottom', [18, 0, 0], [400, 400, 18], 2)]
  end

  def test_confirmat_manual_pair
    result = ZillaFurnitureTools::Hardware.plan_pair(*parts)
    assert_equal 4, result[:holes].length
    assert_equal 2, result[:count]
    assert_equal 'confirmat_7x50', result[:profile_id]
    assert_equal [0.0, 50.0, 9.0], result[:holes][0][:xyz_mm]
    assert_equal [18.0, 350.0, 9.0], result[:holes][3][:xyz_mm]
  end

  def test_drawer_box_connects_four_corners_and_rejects_missing_wall
    walls = [panel('Drawer_Left', [0,0,0], [18,400,107], 0),
             panel('Drawer_Right', [482,0,0], [500,400,107], 0),
             panel('Drawer_Front_Wall', [18,0,0], [482,18,107], 1),
             panel('Drawer_Rear_Wall', [18,382,0], [482,400,107], 1)]
    plan = ZillaFurnitureTools::Hardware.drawer_box(walls)
    assert_equal 8, plan[:count]
    assert_equal 16, plan[:holes].size
    assert_equal 4, plan[:joints].size
    assert_equal [25.0,82.0], plan[:holes].map { |h| h[:xyz_mm][2] }.uniq.sort
    assert_raises(ArgumentError) { ZillaFurnitureTools::Hardware.drawer_box(walls.take(3)) }
  end

  def test_dowel_boards_have_matching_centres_and_opposite_face_direction
    result = ZillaFurnitureTools::Hardware.plan_pair(*parts, profile_id: 'dowel_8x30')
    assert_equal 4, result[:holes].length
    face, edge = result[:holes].take(2)
    assert_equal 'face_blind_dowel', face[:kind]
    assert_equal 'edge_blind_dowel', edge[:kind]
    assert_equal face[:xyz_mm], edge[:xyz_mm]
    assert_equal [-1, 0, 0], face[:direction]
    assert_equal [1, 0, 0], edge[:direction]
    assert_operator face[:depth_mm], :<, 18.0
    assert_equal 8.0, face[:diameter_mm]
  end

  def test_single_fitting_centres_at_midpoint
    result = ZillaFurnitureTools::Hardware.plan_pair(*parts, count: 1)
    assert_equal 2, result[:holes].length
    assert_equal 200, result[:holes][0][:xyz_mm][1]
  end

  def test_oversized_count_is_blocked
    assert_raises(ArgumentError) { ZillaFurnitureTools::Hardware.plan_pair(*parts, count: 8, offset_mm: 130) }
    assert_raises(ArgumentError) { ZillaFurnitureTools::Hardware.plan_pair(*parts, count: 9) }
  end

  def test_invalid_fitting_not_approved_for_joint
    assert_raises(ArgumentError) do
      ZillaFurnitureTools::Hardware.plan_pair(*parts, profile_id: 'slide_side_mount')
    end
    assert_raises(ArgumentError) do
      ZillaFurnitureTools::Hardware.plan_pair(*parts, profile_id: 'unknown')
    end
  end

  def test_disconnected_parts_are_not_assumed_connected
    other = panel('far', [30, 0, 0], [500, 400, 18], 2)
    assert_raises(ArgumentError) { ZillaFurnitureTools::Hardware.plan_pair(parts[0], other) }
  end

  def test_reversed_pair_produces_identical_geometry
    a, b = parts
    first = ZillaFurnitureTools::Hardware.plan_pair(a, b)
    second = ZillaFurnitureTools::Hardware.plan_pair(b, a)
    assert_equal first[:holes], second[:holes]
  end

  def test_catalog_has_no_unsupported_mounting_templates
    catalog = ZillaFurnitureTools::Hardware.catalog
    %w[slide_side_mount slide_undermount drawer_front_adjustable caster_plate manual_facade_mount manual_side_runner].each do |id|
      assert_equal false, catalog.find { |p| p[:id] == id }[:drillable]
    end
  end
end
