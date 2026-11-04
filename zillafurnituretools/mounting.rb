# frozen_string_literal: true

require_relative 'planner'

module ZillaFurnitureTools
  # Explicit guide plans for a drawer facade and a pair of side runners.
  # All coordinates are in the active SketchUp edit frame, in millimetres.
  # These plans are not vendor drilling programs.
  module Mounting
    module_function

    def drawer_front(front, wall, count: 2, offset_mm: 80, diameter_mm: 5, front_depth_mm: 12, tolerance_mm: 0.8)
      axis = front[:thickness_axis]
      raise ArgumentError, 'Facade and front wall must be parallel panels' unless axis == wall[:thickness_axis]
      raise ArgumentError, 'Facade and wall must be distinct parts' if front[:id] == wall[:id]
      count = Integer(count)
      offset = Float(offset_mm)
      diameter = Float(diameter_mm)
      depth = Float(front_depth_mm)
      raise ArgumentError, 'Use 2–4 facade fixings' unless count.between?(2, 4)
      raise ArgumentError, 'Offset must be at least 30 mm' unless offset >= 30
      raise ArgumentError, 'Guide diameter must be 4–10 mm' unless diameter.between?(4, 10)
      raise ArgumentError, 'Blind depth leaves less than 3 mm of facade' unless depth > 0 && depth <= front[:thickness_mm] - 3
      contact, toward_front = if Planner.close?(front[:max][axis], wall[:min][axis], tolerance_mm)
                                [front[:max][axis], -1]
                              elsif Planner.close?(front[:min][axis], wall[:max][axis], tolerance_mm)
                                [front[:min][axis], 1]
                              end
      raise ArgumentError, 'Facade and wall must touch face to face' unless contact
      other = [0, 1, 2] - [axis]
      overlap = other.map { |i| [i, [front[:min][i], wall[:min][i]].max, [front[:max][i], wall[:max][i]].min] }
      raise ArgumentError, 'Facade and wall have no usable overlap' unless overlap.all? { |_i, low, high| high - low >= 35 }
      long, short = overlap.sort_by { |_i, low, high| high - low }.reverse
      length = long[2] - long[1]
      raise ArgumentError, 'Fixings do not fit on facade overlap' if length < 2 * offset + 25 * (count - 1)
      positions = Array.new(count) { |i| long[1] + offset + (length - 2 * offset) * i / (count - 1) }
      holes = []
      positions.each do |pos|
        center = Array.new(3, 0.0)
        center[long[0]] = pos
        center[short[0]] = (short[1] + short[2]) / 2.0
        inside = center.dup
        inside[axis] = toward_front == -1 ? wall[:max][axis] : wall[:min][axis]
        mating = center.dup
        mating[axis] = contact
        holes << Planner.hole('DRAWER_FRONT', wall, 'wall_face_through_GUIDE', inside, axis, toward_front, diameter, wall[:thickness_mm])
        holes << Planner.hole('DRAWER_FRONT', front, 'facade_blind_GUIDE', mating, axis, toward_front, diameter, depth)
      end
      { kind: 'drawer_front', profile_id: 'manual_facade_mount', front_id: front[:id], wall_id: wall[:id],
        count: count, holes: holes,
        warning: 'GUIDES ONLY. Choose exact facade connector/screw and verify head, countersink, diameters and blind depth.' }
    end

    def slide_pair(cabinet, drawer, cabinet_offsets_mm:, drawer_offsets_mm:, height_from_drawer_bottom_mm:,
                   diameter_mm:, depth_mm:, cabinet_front_setback_mm: 0, drawer_front_setback_mm: 0)
      axis = cabinet[:thickness_axis]
      raise ArgumentError, 'Runner mounts need parallel cabinet and drawer side panels' unless axis == drawer[:thickness_axis]
      raise ArgumentError, 'Runner mounts need vertical side panels' unless [0, 1].include?(axis)
      rail = 1 - axis
      vertical = 2
      cab_offsets = numeric_offsets(cabinet_offsets_mm)
      drawer_offsets = numeric_offsets(drawer_offsets_mm)
      raise ArgumentError, 'Enter at least two mounting positions on each rail' if cab_offsets.length < 2 || drawer_offsets.length < 2
      height = Float(height_from_drawer_bottom_mm)
      diameter = Float(diameter_mm)
      depth = Float(depth_mm)
      raise ArgumentError, 'Guide diameter must be 4–10 mm' unless diameter.between?(4, 10)
      raise ArgumentError, 'Blind hole exceeds 3 mm residual panel thickness' unless depth > 0 && depth <= [cabinet[:thickness_mm], drawer[:thickness_mm]].min - 3
      z = drawer[:min][vertical] + height
      raise ArgumentError, 'Rail height outside drawer side' unless z >= drawer[:min][vertical] + diameter / 2 + 4 && z <= drawer[:max][vertical] - diameter / 2 - 4
      raise ArgumentError, 'Rail height outside cabinet side' unless z >= cabinet[:min][vertical] + diameter / 2 + 4 && z <= cabinet[:max][vertical] - diameter / 2 - 4
      gap, cab_face, drawer_face, cab_dir, drawer_dir = if cabinet[:max][axis] < drawer[:min][axis]
        [drawer[:min][axis] - cabinet[:max][axis], cabinet[:max][axis], drawer[:min][axis], -1, 1]
      elsif drawer[:max][axis] < cabinet[:min][axis]
        [cabinet[:min][axis] - drawer[:max][axis], cabinet[:min][axis], drawer[:max][axis], 1, -1]
      end
      raise ArgumentError, 'Side panels must face each other across a runner gap' unless gap && gap.between?(8, 20)
      holes = []
      [[cabinet, cab_offsets, Float(cabinet_front_setback_mm), cab_face, cab_dir, 'cabinet_slide_blind_GUIDE'],
       [drawer, drawer_offsets, Float(drawer_front_setback_mm), drawer_face, drawer_dir, 'drawer_slide_blind_GUIDE']].each do |part, offsets, setback, face, direction, kind|
        offsets.each do |offset|
          p = Array.new(3, 0.0)
          p[axis] = face
          p[rail] = part[:min][rail] + setback + offset
          p[vertical] = z
          raise ArgumentError, "Runner hole outside #{part[:name]}" unless p[rail] >= part[:min][rail] + diameter / 2 + 4 && p[rail] <= part[:max][rail] - diameter / 2 - 4
          holes << Planner.hole('SLIDE_PAIR', part, kind, p, axis, direction, diameter, depth)
        end
      end
      { kind: 'slide_pair', profile_id: 'manual_side_runner', cabinet_id: cabinet[:id], drawer_id: drawer[:id],
        clearance_mm: Planner.round(gap), holes: holes,
        warning: 'GUIDES ONLY. Enter hole coordinates from the exact runner SKU drawing; check screws, height and front datum.' }
    end

    def numeric_offsets(value)
      numbers = (value.is_a?(String) ? value.split(/[;,\s]+/) : Array(value)).reject { |v| v.to_s.empty? }.map { |v| Float(v) }
      raise ArgumentError, 'Offsets must be unique positive finite numbers' unless numbers.all? { |v| v.finite? && v > 0 } && numbers.uniq.length == numbers.length
      numbers
    end
  end
end
