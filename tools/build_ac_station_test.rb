# Run through SketchUp MCP against AC_Station_v4_banding_drilling_TEST.skp.
# Explicit test pattern: not a released drilling specification.
require 'json'
require 'csv'
require 'fileutils'
load File.expand_path('../zillafurnituretools/main.rb', __dir__)
load File.expand_path('../zillafurnituretools/manufacturing.rb', __dir__)

root = 'M:/projects/furniture/AC-Station'
out = File.join(root, 'exports', 'viyar_test_20261104')
model = Sketchup.active_model
raise 'Wrong test copy' unless File.basename(model.path) == 'AC_Station_v4_banding_drilling_TEST.skp'
raise 'Save/discard pending edits before building' if model.modified?
raise 'Test package already exists' if File.exist?(File.join(out, 'drilling_manifest.json'))
assembly = model.entities.grep(Sketchup::Group).find { |g| g.name.start_with?('AC Station v4') }
raise 'Assembly missing' unless assembly
instances = {}
walk = lambda do |parent, parent_transform|
  children = parent.definition.entities.grep(Sketchup::Group) + parent.definition.entities.grep(Sketchup::ComponentInstance)
  children.each do |child|
    grandchildren = child.definition.entities.grep(Sketchup::Group) + child.definition.entities.grep(Sketchup::ComponentInstance)
    if grandchildren.empty?
      raise "Duplicate part #{child.name}" if instances.key?(child.name)
      instances[child.name] = [child, parent_transform]
    else
      walk.call(child, parent_transform * child.transformation)
    end
  end
end
walk.call(assembly, assembly.transformation)
model.selection.clear
model.selection.add(assembly)
parts, = ZillaFurnitureTools::Main.collect_selected(include_drawer: true)
by_name = parts.to_h { |part| [part[:name], part] }
expected_names = CSV.read(File.join(root, 'manufacturing', 'edge_plan_draft.csv'),
  headers: true, col_sep: ';', encoding: 'bom|utf-8').map { |row| row['Деталь'] }
raise 'Missing board' unless (expected_names - by_name.keys).empty?

front_plan = ZillaFurnitureTools::Mounting.drawer_front(
  by_name.fetch('Front_Facade'), by_name.fetch('Drawer_Front_Wall'),
  count: 2, offset_mm: 80, diameter_mm: 5, front_depth_mm: 12)
slide_plans = %w[Left Right].map do |side|
  ZillaFurnitureTools::Mounting.slide_pair(
    by_name.fetch("#{side}_Side"), by_name.fetch("Drawer_#{side}"),
    cabinet_offsets_mm: [37, 101, 165, 325], drawer_offsets_mm: [49, 209, 369],
    height_from_drawer_bottom_mm: 21, diameter_mm: 5, depth_mm: 10)
end
bottom_plans = %w[Left Right].map do |side|
  ZillaFurnitureTools::Hardware.plan_pair(
    by_name.fetch('Bottom'), by_name.fetch("#{side}_Side"),
    profile_id: 'confirmat_7x50', count: 2, offset_mm: 50)
end
holes = front_plan[:holes] + slide_plans.flat_map { |plan| plan[:holes] } +
  bottom_plans.flat_map { |plan| plan[:holes] }
raise "Expected 26 holes, got #{holes.length}" unless holes.length == 26

model.start_operation('AC Station test banding and real holes', true)
begin
  edge_result = ZillaFurnitureTools::Manufacturing.apply_edge_plan!(model,
    expected_names.map { |name| instances.fetch(name).first },
    File.join(root, 'manufacturing', 'edge_plan_draft.csv'))
  holes.each do |hole|
    instance, parent_transform = instances.fetch(hole[:part_name])
    ZillaFurnitureTools::Manufacturing.cut_hole!(instance, hole, parent_transform)
  end
  model.commit_operation
rescue StandardError
  model.abort_operation
  raise
end

FileUtils.mkdir_p(out)
manifest = {
  status: 'TEST_ONLY_NOT_APPROVED_FOR_ORDER',
  source_model: model.path, board_material_code: 49004,
  edge_codes: { '1' => 125349, '2' => 125353 },
  assumptions: [
    'Slide candidate Viyar 52504 L400 zinc: offset lists interpreted from user drawings, SKU match and screws unverified',
    'Drawer facade: generic 5 mm through-wall and 12 mm blind facade guides, fitting SKU unselected',
    'Bottom/side confirmat: provisional 7x50 profile, screw/countersink not verified',
    '50 mm rails and stops have NO holes in this test package; Viyar drilling minimum is 70 mm'
  ],
  edge_result: edge_result, parts: expected_names.map { |name| by_name.fetch(name) }, holes: holes
}
File.write(File.join(out, 'drilling_manifest.json'), JSON.pretty_generate(manifest))
CSV.open(File.join(out, 'drilling_review.csv'), 'wb', col_sep: ';', write_headers: true,
  headers: %w[part operation x_mm y_mm z_mm local_x_mm local_y_mm local_z_mm dir_x dir_y dir_z diameter_mm depth_mm status]) do |csv|
  holes.each do |hole|
    csv << [hole[:part_name], hole[:kind], *hole[:xyz_mm], *hole[:local_bbox_mm],
            *hole[:direction], hole[:diameter_mm], hole[:depth_mm], 'TEST_REVIEW']
  end
end
raise 'Could not save test scene' unless model.save
File.write(File.join(out, 'build_result.json'), JSON.pretty_generate({model: model.path, holes: holes.length,
  edge_parts: edge_result.length, manifold: expected_names.all? { |name| instances.fetch(name).first.definition.manifold? }}))
