# frozen_string_literal: true

# Drill geometry calculations, independent of the SketchUp API.
# Values are in mm; all profiles are explicitly preliminary until checked against
# the selected manufacturer's drilling instructions.
require_relative 'planner'
module ZillaFurnitureTools
  module Hardware
    PROFILES = {
      'confirmat_7x50' => {
        label: 'Конфірмат 7×50 (перевірити)', kind: 'joint', note: 'Ø7 у пласть / Ø5 у торець — стартовий профіль; перевірити свердло, зенківку та довжину',
        verified: false
      },
      'dowel_8x30' => {
        label: 'Шкант Ø8×30 + клей (перевірити)', kind: 'joint', note: 'Глухі отвори з контактного боку; Ø8, 12+16 мм — попередня схема',
        verified: false
      },
      'dowel_6x30' => {
        label: 'Шкант Ø6×30 + клей (перевірити)', kind: 'joint', note: 'Глухі отвори з контактного боку; Ø6, 12+16 мм — попередня схема',
        verified: false
      },
      'drawer_front_adjustable' => {
        label: 'Фасад шухляди: регульоване кріплення', kind: 'drawer_front', note: 'Для свердлінь потрібен конкретний артикул, профіль поки без схеми',
        verified: false, drillable: false
      },
      'manual_facade_mount' => {
        label: 'Фасад шухляди: ручна розмітка', kind: 'drawer_front',
        note: 'Парні мітки крізь передню стінку й глухо у фасад; виберіть конкретне кріплення та перевірте його креслення',
        verified: false, drillable: false, guide_only: true
      },
      'manual_side_runner' => {
        label: 'Бокова напрямна: ручна розмітка', kind: 'slide',
        note: 'Окремі координати отворів корпусної й шухлядної частин з креслення конкретного артикулу',
        verified: false, drillable: false, guide_only: true
      },
      'slide_side_mount' => {
        label: 'Телескопічна напрямна: бокова', kind: 'slide', note: 'Необхідні артикул, довжина і PDF креслення кріпильних отворів',
        verified: false, drillable: false
      },
      'slide_undermount' => {
        label: 'Напрямна прихованого монтажу', kind: 'slide', note: 'Розміри залежать від моделі фурнітури та фіксаторів',
        verified: false, drillable: false
      },
      'caster_plate' => {
        label: 'Колесо/ніжка на пластині', kind: 'foot', note: 'Необхідна схема отворів конкретної монтажної пластини',
        verified: false, drillable: false
      }
    }.freeze

    module_function

    def catalog
      PROFILES.map { |key, value| { id: key }.merge(value) }
    end

    # Explicit four-wall drawer recipe, not an all-contact auto fastener guess.
    def drawer_box(parts, count: 2, offset_mm: 25)
      names = %w[Drawer_Left Drawer_Right Drawer_Front_Wall Drawer_Rear_Wall]
      walls = names.map do |name|
        matches = parts.select { |p| p[:name] == name }
        raise ArgumentError, "Expected exactly one #{name}" unless matches.length == 1
        part = matches.first
        raise ArgumentError, "#{name}: expected vertical 18 mm panel" unless
          [0, 1].include?(part[:thickness_axis]) && (part[:thickness_mm] - 18).abs < 0.1
        part
      end
      joints = walls.first(2).product(walls.last(2)).map do |side, wall|
        plan_pair(side, wall, count: count, offset_mm: offset_mm)
      end
      { kind: 'drawer_box', profile_id: 'confirmat_7x50', joints: joints,
        count: joints.sum { |j| j[:count] }, holes: joints.flat_map { |j| j[:holes] },
        warning: 'Four wall joints only. Verify countersinks below runner rails. Bottom, facade and slides use separate fittings.' }
    end

    def plan_pair(a, b, profile_id: 'confirmat_7x50', count: 2, offset_mm: 50.0, tolerance_mm: 0.8)
      profile = PROFILES.fetch(profile_id) { raise ArgumentError, 'Unknown fitting profile' }
      raise ArgumentError, 'This fitting needs manufacturer/SKU drawing before drilling' unless profile[:kind] == 'joint'
      count = Integer(count)
      offset = Float(offset_mm)
      raise ArgumentError, 'Count must be 1–8' unless count.between?(1, 8)
      raise ArgumentError, 'Offset must be 15–150 mm' unless offset.between?(15, 150)
      opts = Planner.options('touch_tolerance_mm' => tolerance_mm)
      hits = [Planner.candidate(a, b, opts), Planner.candidate(b, a, opts)].compact
      raise ArgumentError, 'No unique perpendicular butt joint between selected panels' unless hits.length == 1
      joint = hits[0]
      shell, butt = joint.values_at(:shell, :butt)
      axis, thin, rail = joint[:axis], butt[:thickness_axis], joint[:rail]
      rail_start = joint[:start] + offset
      rail_end = joint[:finish] - offset
      raise ArgumentError, 'Not enough seam length for this offset' if rail_end < rail_start
      raise ArgumentError, 'Insufficient separation for specified number of fittings' if count > 1 && (rail_end - rail_start) / (count - 1) < 25.0
      positions = count == 1 ? [(joint[:start] + joint[:finish]) / 2.0] : Array.new(count) { |i| rail_start + (rail_end - rail_start) * i / (count - 1) }
      result = {
        id: "#{shell[:id]}--#{butt[:id]}", shell_id: shell[:id], butt_id: butt[:id],
        shell_name: shell[:name], butt_name: butt[:name],
        contact: joint[:contact], rail: rail, seam_start_mm: joint[:start], seam_finish_mm: joint[:finish],
        seam_length_mm: Planner.round(joint[:length_mm]), profile_id: profile_id, profile: profile,
        count: count, offset_mm: offset, holes: [], warning: 'Тільки розмітка! Звірити свердла/посадку з фурнітурою.'
      }
      screw_dir = joint[:direction]
      positions.each do |pos|
        center = Array.new(3, 0.0)
        center[rail] = pos
        center[thin] = (butt[:min][thin] + butt[:max][thin]) / 2.0
        if profile_id == 'confirmat_7x50'
          outer = center.dup
          outer[axis] = screw_dir == 1 ? shell[:min][axis] : shell[:max][axis]
          inner = center.dup
          inner[axis] = joint[:contact]
          pilot_depth = [30.0, 50.0 - shell[:thickness_mm] - 2.0,
                         butt[:max][axis] - butt[:min][axis] - 5.0].min
          raise ArgumentError, 'Insufficient pilot hole depth' if pilot_depth < 12
          result[:holes] << Planner.hole(result[:id], shell, 'face_through', outer, axis, screw_dir, 7.0, shell[:thickness_mm])
          result[:holes] << Planner.hole(result[:id], butt, 'edge_pilot', inner, axis, screw_dir, 5.0, pilot_depth)
        else
          # Dowel bores start at mating surfaces, *not* at the outside face.
          # 12 mm / 16 mm are provisional, and both are capped to avoid breakout.
          diameter = profile_id == 'dowel_6x30' ? 6.0 : 8.0
          face_depth = [12.0, shell[:thickness_mm] - 5.0].min
          edge_thickness = butt[:max][axis] - butt[:min][axis]
          edge_depth = [16.0, edge_thickness - 5.0].min
          raise ArgumentError, 'Panel too thin for selected dowel holes' if face_depth < 8 || edge_depth < 8
          contact = center.dup
          contact[axis] = joint[:contact]
          result[:holes] << Planner.hole(result[:id], shell, 'face_blind_dowel', contact, axis, -screw_dir, diameter, face_depth)
          result[:holes] << Planner.hole(result[:id], butt, 'edge_blind_dowel', contact, axis, screw_dir, diameter, edge_depth)
        end
      end
      result
    end
  end
end
