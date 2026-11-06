# Technical review copy only; does not modify the manufacturing source.
require 'json'
root = 'M:/projects/furniture/AC-Station'
m = Sketchup.active_model
raise 'Open the drilled TEST model first' unless ['AC_Station_v4_banding_drilling_TEST.skp','AC_Station_v5_drawer_joints_TEST.skp'].include?(File.basename(m.path))
raise 'Save pending edits first' if m.modified?
v5 = File.basename(m.path).include?('_v5_')
out = root + '/exports/' + (v5 ? 'viyar_test_20261105' : 'viyar_test_20261104')
manifest = JSON.parse(File.read(out + '/drilling_manifest.json'))
dest = root + '/cad/sketchup/' + (v5 ? 'AC_Station_v5_TECHNICAL_REVIEW.skp' : 'AC_Station_v4_TECHNICAL_REVIEW.skp')
raise 'Review already exists; preserve it before rebuilding' if File.exist?(dest)
raise 'Save copy failed' unless m.save(dest)
m.start_operation('Technical perspective review', true)
begin
  grey = m.materials.add('REVIEW_Panel_Grey'); grey.color = '#dce1e7'
  red = m.materials.add('REVIEW_Edge_0.5_Red'); red.color = '#e53845'
  green = m.materials.add('REVIEW_Edge_2_Green'); green.color = '#12a35d'
  blue = m.materials.add('REVIEW_Drill_Blue'); blue.color = '#086ddb'
  visited = {}
  walk = lambda do |entities|
    entities.each do |e|
      if e.is_a?(Sketchup::Face)
        old = e.material && e.material.name
        mat = old && old.include?('VIYAR_125349_EDGE') ? red : old && old.include?('VIYAR_125353_EDGE') ? green : grey
        e.material = mat; e.back_material = mat
      elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        e.material = nil
        unless visited[e.definition.object_id]
          visited[e.definition.object_id] = true
          walk.call(e.definition.entities)
        end
      end
    end
  end
  walk.call(m.entities)
  tag = m.layers.add('REVIEW_ONLY_Drill_axes')
  markers = m.entities.add_group
  markers.name = "REVIEW ONLY - #{manifest['holes'].length} drilling axes - not hardware"
  markers.layer = tag
  manifest['holes'].each_with_index do |h, i|
    g = markers.entities.add_group
    g.name = "H#{i+1} #{h['part_name']} D#{h['diameter_mm']} depth#{h['depth_mm']}"
    p = Geom::Point3d.new(h['xyz_mm'].map(&:mm))
    direction = Geom::Vector3d.new(h['direction'])
    start = p.offset(direction, -16.mm)
    ring = g.entities.add_circle(start, direction, (h['diameter_mm']/2).mm, 24)
    face = g.entities.add_face(ring)
    face.reverse! if face.normal.dot(direction) < 0
    face.pushpull((h['depth_mm']+16).mm)
    g.entities.grep(Sketchup::Face).each { |f| f.material=blue; f.back_material=blue }
    g.set_attribute('TechnicalReview', 'hole', h.to_json)
  end
  r = m.rendering_options
  {'RenderMode'=>2, 'DrawEdges'=>true, 'DrawProfiles'=>false, 'BackgroundColor'=>Sketchup::Color.new(248,249,252),
   'DrawGround'=>false,'DrawHorizon'=>false, 'ModelTransparency'=>false}.each { |key,value| r[key]=value if r.keys.include?(key) }
  m.shadow_info['DisplayShadows']=false
  m.selection.clear
  m.active_view.camera = Sketchup::Camera.new([1150.mm,-1350.mm,1000.mm],[280.mm,250.mm,190.mm],[0,0,1],true,35)
  m.active_view.zoom_extents
  m.active_view.zoom(0.85)
  m.pages.add('01 - Perspective - edge colours')
  m.active_view.write_image(filename:out+'/technical_perspective.png',width:1800,height:1300,antialias:true)
  r['ModelTransparency']=true
  m.pages.add('02 - XRay - drilling axes')
  m.active_view.write_image(filename:out+'/technical_xray.png',width:1800,height:1300,antialias:true)
  r['ModelTransparency']=false
  r['DisplaySketchAxes']=false
  r['DrawSilhouettes']=false
  hide_names = %w[Top_Platform Front_Stop Left_Stop Right_Stop Front_Facade Right_Side]
  hide_parts = lambda do |entities|
    entities.each do |e|
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      if hide_names.include?(e.name)
        e.hidden=true
      else
        hide_parts.call(e.definition.entities)
      end
    end
  end
  hide_parts.call(m.entities)
  markers.entities.grep(Sketchup::Group).each do |g|
    h = JSON.parse(g.get_attribute('TechnicalReview','hole'))
    g.hidden = %w[Right_Side Front_Facade].include?(h['part_name'])
  end
  m.layers['AC_DRAWING_DIMENSIONS'].visible=false
  m.layers['AC_HARDWARE_CONCEPT'].visible=false
  m.pages.add('03 - Open view - drawer and drilling')
  m.active_view.write_image(filename:out+'/technical_open.png',width:1800,height:1300,antialias:true)
  m.set_attribute('TechnicalReview','legend','RED: nominal 0.5 mm edge; GREEN: 2 mm edge; BLUE: drilling axes, not fasteners. TEST ONLY.')
  m.commit_operation
  # Each scene needs its own saved style; unsaved style edits disappear on switching.
  styles_dir = 'C:/ProgramData/SketchUp/SketchUp 2026/SketchUp/Styles/Default Styles/'
  style_files = ['03Shaded.style','05X-ray.style','06Simple Style.style']
  %w[01 02 03].each_with_index do |prefix,i|
    page=m.pages.find { |p| p.name.start_with?(prefix+' -') }
    m.pages.selected_page=page
    m.styles.add_style(styles_dir+style_files[i],true)
    m.styles.selected_style.name='AC REVIEW '+prefix
    r['RenderMode']=2
    r['ModelTransparency']=(prefix=='02')
    r['BackgroundColor']=Sketchup::Color.new(248,249,252)
    r['DisplaySketchAxes']=false
    r['DrawGround']=false
    r['DrawHorizon']=false
    r['DrawSilhouettes']=false
    m.styles.update_selected_style
    page.use_style=true
    page.update
  end
  m.save
  m.active_view.refresh
rescue StandardError
  m.abort_operation
  raise
end
puts JSON.generate({path:dest,markers:manifest['holes'].length,pages:m.pages.map(&:name)})
