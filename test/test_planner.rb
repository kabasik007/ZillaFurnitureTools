# frozen_string_literal: true
require 'minitest/autorun'
require_relative '../zillafurnituretools/planner'

class TestPlanner < Minitest::Test
  def panel(id, from, to, thin, kind = 'cabinet')
    { id: id, name: id, min: from, max: to,
      thickness_axis: thin, thickness_mm: to[thin] - from[thin], kind: kind }
  end

  def test_butt_joint_creates_two_screws_and_four_hole_operations
    side = panel('side', [0, 0, 0], [18, 400, 300], 0)
    bottom = panel('bottom', [18, 0, 0], [400, 400, 18], 2)
    result = ZillaFurnitureTools::Planner.plan([side, bottom])
    assert_equal 1, result[:joints].size
    assert_equal 4, result[:holes].size
    face = result[:holes].find { |h| h[:kind] == 'face_through' }
    pilot = result[:holes].find { |h| h[:kind] == 'edge_pilot' }
    assert_equal [0.0, 50.0, 9.0], face[:xyz_mm]
    assert_equal [18.0, 50.0, 9.0], pilot[:xyz_mm]
    assert_equal [1, 0, 0], face[:direction]
    assert_equal 7.0, face[:diameter_mm]
    assert_equal 5.0, pilot[:diameter_mm]
    assert_equal 30.0, pilot[:depth_mm]
  end

  def test_parallel_panels_do_not_produce_holes
    a = panel('a', [0, 0, 0], [400, 500, 18], 2)
    b = panel('b', [0, 0, 200], [400, 500, 218], 2)
    assert_empty ZillaFurnitureTools::Planner.plan([a, b])[:holes]
  end

  def test_gaps_larger_than_tolerance_not_assumed_joint
    side = panel('side', [0, 0, 0], [18, 400, 300], 0)
    bottom = panel('bottom', [20, 0, 0], [400, 400, 18], 2)
    assert_empty ZillaFurnitureTools::Planner.plan([side, bottom])[:joints]
  end

  def test_drawer_not_drilled_in_cabinet_mode
    side = panel('side', [0, 0, 0], [18, 400, 300], 0)
    drawer = panel('drawer', [18, 0, 0], [400, 400, 18], 2, 'drawer')
    assert_empty ZillaFurnitureTools::Planner.plan([side, drawer])[:joints]
  end

  def test_short_seam_is_skipped
    side = panel('side', [0, 0, 0], [18, 100, 300], 0)
    bottom = panel('bottom', [18, 0, 0], [400, 100, 18], 2)
    result = ZillaFurnitureTools::Planner.plan([side, bottom])
    assert_empty result[:holes]
    assert result[:warnings].any? { |w| w.include?('Short seam') }
  end

  def test_edge_candidate_is_in_its_own_export_review_queue
    side = panel('side', [0, 0, 0], [18, 400, 300], 0)
    result = ZillaFurnitureTools::Planner.plan([side])
    assert_equal 1, result[:banding].size
    assert_equal '-Y', result[:banding].first[:edge]
    assert_equal 300.0, result[:banding].first[:length_mm]
    assert_equal 'REVIEW_EXPOSURE', result[:banding].first[:status]
  end

  def test_invalid_options_are_rejected
    assert_raises(ArgumentError) { ZillaFurnitureTools::Planner.plan([], 'face_diameter_mm' => -1) }
    assert_raises(ArgumentError) { ZillaFurnitureTools::Planner.plan([], 'front' => '+Z') }
  end

  def test_reverse_contact_axis_changes_direction
    side = panel('side', [300, 0, 0], [318, 400, 300], 0)
    bottom = panel('bottom', [0, 0, 0], [300, 400, 18], 2)
    result = ZillaFurnitureTools::Planner.plan([side, bottom])
    assert_equal 1, result[:joints].size
    assert_equal [-1, 0, 0], result[:holes].first[:direction]
  end
end