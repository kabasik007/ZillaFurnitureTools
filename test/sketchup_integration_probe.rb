# Run with `load` from SketchUp Ruby Console or a local SketchUp MCP connection.
require 'json'
root_dir = File.expand_path('..', __dir__)
%w[zillafurnituretools.rb zillafurnituretools/planner.rb zillafurnituretools/hardware.rb
   zillafurnituretools/mounting.rb zillafurnituretools/smart_joint.rb zillafurnituretools/main.rb].each do |relative|
  RubyVM::InstructionSequence.compile_file(File.join(root_dir, relative))
end
load File.join(root_dir, 'zillafurnituretools/main.rb')

model = Sketchup.active_model
raise 'Use only the AC Station OCL draft scene for this probe' unless File.basename(model.path) == 'AC_Station_v4_technical_OCL_DRAFT.skp'
raise 'Save or discard pending changes before probe' if model.modified?
assembly = model.entities.grep(Sketchup::Group).find { |g| g.name.start_with?('AC Station v4') }
raise 'Assembly missing' unless assembly
model.selection.clear
model.selection.add(assembly)
parts, skipped = ZillaFurnitureTools::Main.collect_selected(include_drawer: true)
front = parts.find { |p| p[:name] == 'Front_Facade' }
wall = parts.find { |p| p[:name] == 'Drawer_Front_Wall' }
left = parts.find { |p| p[:name] == 'Left_Side' }
drawer_left = parts.find { |p| p[:name] == 'Drawer_Left' }
raise "Missing parts: #{parts.map { |p| p[:name] }}" unless front && wall && left && drawer_left
facade = ZillaFurnitureTools::Mounting.drawer_front(front, wall)
slide = ZillaFurnitureTools::Mounting.slide_pair(left, drawer_left,
  cabinet_offsets_mm: '37,101,165,325', drawer_offsets_mm: '49,209,369',
  height_from_drawer_bottom_mm: 21, diameter_mm: 5, depth_mm: 10)
raise 'Facade guide count' unless facade[:holes].length == 4
raise 'Slide guide count' unless slide[:holes].length == 7
raise 'Expected 12.5 mm slide clearance' unless (slide[:clearance_mm] - 12.5).abs < 0.01
before = model.entities.grep(Sketchup::Group).length
ZillaFurnitureTools::Main.add_mount_guides(facade, notify: false)
guide = model.active_entities.grep(Sketchup::Group).find { |g| g.name.include?('ZFT drawer_front') }
raise 'Guide group or four construction points missing' unless guide && guide.entities.grep(Sketchup::ConstructionPoint).length == 4
csv_rows = CSV.parse(ZillaFurnitureTools::Main.mount_guides_csv([guide]), col_sep: ';')
raise 'CSV guide rows missing' unless csv_rows.length == 5 && csv_rows[1][0] == 'GUIDE_ONLY_NOT_VIYAR_IMPORT'
Sketchup.undo
raise 'Undo did not remove guide group' unless model.entities.grep(Sketchup::Group).length == before
$zft_probe_result = JSON.generate({parts: parts.length, skipped: skipped, facade_holes: facade[:holes].length,
  slide_holes: slide[:holes].length, slide_clearance_mm: slide[:clearance_mm],
  facade_centers: facade[:holes].map { |h| h[:xyz_mm] },
  slide_first_centers: slide[:holes].map { |h| h[:xyz_mm] }.first(2)})
