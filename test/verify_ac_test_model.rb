require 'json'
root_dir = File.expand_path('..', __dir__)
%w[zillafurnituretools.rb zillafurnituretools/main.rb zillafurnituretools/manufacturing.rb].each do |relative|
  RubyVM::InstructionSequence.compile_file(File.join(root_dir, relative))
end
load File.join(root_dir, 'zillafurnituretools/main.rb')
raise '0.5 mm edge index lost' unless ZillaFurnitureTools::Manufacturing.edge_code('0.5') == 1
model = Sketchup.active_model
raise 'Wrong test model' unless File.basename(model.path) == 'AC_Station_v4_banding_drilling_TEST.skp'
assembly = model.entities.grep(Sketchup::Group).find { |g| g.name.start_with?('AC Station v4') }
raise 'Leaf traversal failed' unless ZillaFurnitureTools::Main.leaf_instances([assembly]).key?('Drawer_Left')
rows = []
walk = lambda do |parent|
  children = parent.definition.entities.grep(Sketchup::Group) + parent.definition.entities.grep(Sketchup::ComponentInstance)
  children.each do |child|
    if child.definition.entities.grep(Sketchup::Group).empty? && child.definition.entities.grep(Sketchup::ComponentInstance).empty?
      next unless child.get_attribute('ZillaFurnitureTools', 'edge_plan')
      hole_log = JSON.parse(child.get_attribute('ZillaFurnitureTools', 'actual_holes_json', '[]'))
      face_materials = child.definition.entities.grep(Sketchup::Face).map { |face| face.material&.name }.compact
      rows << { name: child.name, manifold: child.definition.manifold?,
                actual_holes: hole_log.length,
                band_05_faces: face_materials.count { |name| name.include?('125349') },
                band_2_faces: face_materials.count { |name| name.include?('125353') } }
    else
      walk.call(child)
    end
  end
end
walk.call(assembly)
File.write('M:/projects/furniture/AC-Station/exports/viyar_test_20261104/scene_qa.json',
  JSON.pretty_generate({path: model.path, modified: model.modified?, parts: rows,
                        part_count: rows.length, hole_count: rows.sum { |r| r[:actual_holes] },
                        all_manifold: rows.all? { |r| r[:manifold] }}))
