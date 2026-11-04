# frozen_string_literal: true

require 'csv'
require 'json'
require 'sketchup.rb'

module ZillaFurnitureTools
  # Explicitly approved geometry operations. The caller must work in a test copy
  # and supply a checked fitting plan; guide circles alone never invoke this.
  module Manufacturing
    module_function

    def edge_material(model, code, nominal_mm, color)
      name = "VIYAR_#{code}_EDGE_#{nominal_mm}MM"
      material = model.materials[name] || model.materials.add(name)
      material.color = color
      material.set_attribute('ladb_opencutlist', 'type', 4)
      material.set_attribute('ladb_opencutlist', 'thickness', "#{nominal_mm} mm")
      material.set_attribute('ladb_opencutlist', 'std_widths', '22 mm')
      material.set_attribute('ladb_opencutlist', 'edge_decremented', true)
      material.set_attribute('ZillaFurnitureTools', 'viyar_code', code.to_s)
      material
    end

    def apply_edge_plan!(model, instances, csv_path)
      rows = CSV.read(csv_path, headers: true, col_sep: ';', encoding: 'bom|utf-8').map(&:to_h)
      by_name = instances.to_h { |instance| [instance.name, instance] }
      raise 'Duplicate component names in edge plan selection' unless by_name.length == instances.length
      names = rows.map { |row| row.fetch('Деталь') }
      raise 'Edge plan and model part names differ' unless names.sort == by_name.keys.sort
      materials = {
        1 => edge_material(model, 125349, 0.5, Sketchup::Color.new(181, 125, 80)),
        2 => edge_material(model, 125353, 2, Sketchup::Color.new(181, 125, 80))
      }
      result = []
      rows.each do |row|
        instance = by_name.fetch(row.fetch('Деталь'))
        instance.make_unique
        bounds = instance.definition.bounds
        extents = [bounds.width, bounds.height, bounds.depth].map { |n| n.to_f * 25.4 }
        thin = extents.each_with_index.min_by(&:first).last
        raise "Not an 18 mm sheet part: #{instance.name}" unless (extents[thin] - 18).abs < 0.1
        long, short = ([0, 1, 2] - [thin]).sort_by { |axis| -extents[axis] }
        codes = {
          [short, :max] => edge_code(row.fetch('Крайка В мм')),
          [short, :min] => edge_code(row.fetch('Крайка Н мм')),
          [long, :min] => edge_code(row.fetch('Крайка Л мм')),
          [long, :max] => edge_code(row.fetch('Крайка П мм'))
        }
        dimensions = [[bounds.min.x, bounds.max.x], [bounds.min.y, bounds.max.y], [bounds.min.z, bounds.max.z]]
        codes.each do |(axis, side), code|
          raise "Unsupported edge code #{code}" unless [0, 1, 2].include?(code)
          coordinate = side == :min ? dimensions[axis][0] : dimensions[axis][1]
          faces = instance.definition.entities.grep(Sketchup::Face).select do |face|
            face.vertices.all? { |vertex| (vertex.position.to_a[axis] - coordinate).abs < 0.001.mm }
          end
          raise "Missing #{side} edge face on #{instance.name}" if faces.empty?
          faces.each { |face| face.material = materials[code] }
        end
        instance.set_attribute('ZillaFurnitureTools', 'edge_plan', codes.map { |(axis, side), code| [axis, side, code] }.to_json)
        result << { name: instance.name, edges: codes.values.count { |code| code > 0 } }
      end
      result
    end

    def edge_code(value)
      thickness = Float(value)
      return 0 if thickness == 0
      return 1 if (thickness - 0.5).abs < 0.06
      return 2 if thickness == 2
      raise "Unsupported edge thickness #{value} mm"
    end

    def cut_hole!(instance, hole, parent_transform = Geom::Transformation.new)
      raise "Wrong target for hole: #{hole[:part_name]}" unless instance.name == hole[:part_name]
      diameter = Float(hole.fetch(:diameter_mm))
      depth = Float(hole.fetch(:depth_mm))
      raise 'Invalid hole dimensions' unless diameter.between?(3, 35) && depth > 0
      instance.make_unique
      transform = parent_transform * instance.transformation
      point = Geom::Point3d.new(*hole.fetch(:xyz_mm).map(&:mm)).transform(transform.inverse)
      direction = Geom::Vector3d.new(*hole.fetch(:direction)).transform(transform.inverse)
      direction.normalize!
      entities = instance.definition.entities
      face = entities.grep(Sketchup::Face).find do |candidate|
        candidate.normal.dot(direction) < -0.999 &&
          candidate.classify_point(point) == Sketchup::Face::PointInside
      end
      raise "Hole entry face not found on #{instance.name}: #{hole[:xyz_mm]}" unless face
      before = instance.volume.to_f
      edges = entities.add_circle(point, face.normal, (diameter / 2).mm, 32)
      circle = entities.grep(Sketchup::Face).find do |candidate|
        candidate.valid? && edges.all? { |edge| candidate.edges.include?(edge) } &&
          candidate.area.to_f * 25.4**2 < Math::PI * (diameter / 2)**2 * 1.01
      end
      raise "Circular face failed on #{instance.name}" unless circle
      circle.pushpull(-depth.mm)
      removed_mm3 = (before - instance.volume.to_f) * 25.4**3
      expected_mm3 = 32 * (diameter / 2)**2 * Math.sin(2 * Math::PI / 32) / 2 * depth
      raise "Hole volume mismatch on #{instance.name}" unless (removed_mm3 - expected_mm3).abs < expected_mm3 * 0.03
      raise "Non-manifold board after hole on #{instance.name}" unless instance.definition.manifold?
      log = JSON.parse(instance.get_attribute('ZillaFurnitureTools', 'actual_holes_json', '[]'))
      log << hole
      instance.set_attribute('ZillaFurnitureTools', 'actual_holes_json', JSON.generate(log))
      removed_mm3
    end
  end
end
