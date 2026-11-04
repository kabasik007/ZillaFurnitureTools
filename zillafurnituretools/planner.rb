# frozen_string_literal: true

# Geometry-only planning core. All coordinates and distances are in millimetres.
# No dependency on the SketchUp API: tests can run with plain Ruby.
module ZillaFurnitureTools
  module Planner
    DEFAULTS = {
      'face_diameter_mm' => 7.0,
      'edge_diameter_mm' => 5.0,
      'screw_length_mm' => 50.0,
      'edge_pilot_depth_mm' => 30.0,
      'end_offset_mm' => 50.0,
      'touch_tolerance_mm' => 0.8,
      'edge_banding_mm' => 1.0,
      'front' => '-Y'
    }.freeze

    AXES = %w[X Y Z].freeze
    module_function

    def options(raw = {})
      h = DEFAULTS.merge(raw || {})
      ranges = {
        'face_diameter_mm' => [2.0, 15.0],
        'edge_diameter_mm' => [2.0, 15.0],
        'screw_length_mm' => [20.0, 120.0],
        'edge_pilot_depth_mm' => [10.0, 100.0],
        'end_offset_mm' => [15.0, 150.0],
        'touch_tolerance_mm' => [0.05, 2.0],
        'edge_banding_mm' => [0.1, 4.0]
      }
      ranges.each do |key, (low, high)|
        n = Float(h.fetch(key))
        raise ArgumentError, "#{key} must be between #{low} and #{high}" unless n.finite? && n.between?(low, high)
        h[key] = n
      end
      raise ArgumentError, 'Invalid front direction' unless %w[+X -X +Y -Y].include?(h['front'])
      h
    end

    def plan(panels, raw_options = {})
      o = options(raw_options)
      results = { joints: [], holes: [], banding: [], warnings: [], parts: panels }
      active = panels.select { |p| p[:kind] == 'cabinet' }
      active.combination(2) do |left, right|
        possibilities = [candidate(left, right, o), candidate(right, left, o)].compact
        if possibilities.length > 1
          results[:warnings] << "Ambiguous joint: #{left[:name]} / #{right[:name]} — skipped"
          next
        end
        next if possibilities.empty?

        joint = possibilities.first
        if joint[:length_mm] < o['end_offset_mm'] * 2 + 20
          results[:warnings] << "Short seam: #{left[:name]} / #{right[:name]} — skipped"
          next
        end
        joint_id = "J#{results[:joints].length + 1}"
        shell = joint[:shell]
        butt = joint[:butt]
        axis = joint[:axis]
        rail = joint[:rail]
        thin = butt[:thickness_axis]
        contact = joint[:contact]
        screw_direction = joint[:direction]
        shell_face = screw_direction == 1 ? shell[:min][axis] : shell[:max][axis]
        pilot_depth = [o['edge_pilot_depth_mm'], o['screw_length_mm'] - shell[:thickness_mm] - 2.0,
                       butt[:max][axis] - butt[:min][axis] - 5.0].min
        if pilot_depth <= 0
          results[:warnings] << "Insufficient material for #{joint_id}; skipped"
          next
        end

        results[:joints] << {
          id: joint_id, shell_id: shell[:id], butt_id: butt[:id],
          shell_name: shell[:name], butt_name: butt[:name],
          length_mm: round(joint[:length_mm]), fastener: 'Confirmat 7x50 (verify)', screws: 2
        }
        [joint[:start] + o['end_offset_mm'], joint[:finish] - o['end_offset_mm']].each do |position|
          common = Array.new(3, 0.0)
          common[rail] = position
          common[thin] = (butt[:min][thin] + butt[:max][thin]) / 2.0
          a_pt = common.dup
          a_pt[axis] = shell_face
          b_pt = common.dup
          b_pt[axis] = contact
          results[:holes] << hole(joint_id, shell, 'face_through', a_pt, axis, screw_direction,
                                 o['face_diameter_mm'], shell[:thickness_mm])
          results[:holes] << hole(joint_id, butt, 'edge_pilot', b_pt, axis, screw_direction,
                                 o['edge_diameter_mm'], pilot_depth)
        end
      end
      results[:banding] = edge_candidates(active, o)
      results
    end

    def candidate(shell, butt, o)
      a = shell[:thickness_axis]
      b = butt[:thickness_axis]
      return nil if a == b

      rail = ([0, 1, 2] - [a, b]).first
      tol = o['touch_tolerance_mm']
      return nil if butt[:min][b] < shell[:min][b] - tol || butt[:max][b] > shell[:max][b] + tol

      if close?(butt[:min][a], shell[:max][a], tol)
        direction = 1
        contact = shell[:max][a]
      elsif close?(butt[:max][a], shell[:min][a], tol)
        direction = -1
        contact = shell[:min][a]
      else
        return nil
      end
      # In a proper butt joint there must be NO significant overlap along the screw axis.
      return nil if (direction == 1 && butt[:min][a] < shell[:max][a] - tol) ||
                    (direction == -1 && butt[:max][a] > shell[:min][a] + tol)

      start_pos = [shell[:min][rail], butt[:min][rail]].max
      end_pos = [shell[:max][rail], butt[:max][rail]].min
      return nil if end_pos - start_pos < 40.0

      { shell: shell, butt: butt, axis: a, rail: rail, direction: direction,
        contact: contact, start: start_pos, finish: end_pos, length_mm: end_pos - start_pos }
    end

    def edge_candidates(panels, o)
      front_axis = AXES.index(o['front'][-1])
      sign = o['front'][0]
      panels.filter_map do |part|
        next if front_axis == part[:thickness_axis]

        longitudinal = ([0, 1, 2] - [front_axis, part[:thickness_axis]]).first
        next if longitudinal.nil?

        {
          part_id: part[:id], part_name: part[:name],
          edge: o['front'], length_mm: round(part[:max][longitudinal] - part[:min][longitudinal]),
          band_thickness_mm: o['edge_banding_mm'], status: 'REVIEW_EXPOSURE'
        }
      end
    end

    def hole(joint_id, part, kind, coords, axis, direction, diameter, depth)
      {
        joint_id: joint_id, part_id: part[:id], part_name: part[:name], kind: kind,
        xyz_mm: coords.map { |n| round(n) },
        local_bbox_mm: coords.each_with_index.map { |n, i| round(n - part[:min][i]) },
        direction: Array.new(3) { |i| i == axis ? direction : 0 },
        diameter_mm: round(diameter), depth_mm: round(depth),
        face: "#{direction == 1 ? '-' : '+'}#{AXES[axis]}"
      }
    end

    def close?(a, b, epsilon)
      (a - b).abs <= epsilon
    end

    def round(n)
      n.round(3)
    end
  end
end