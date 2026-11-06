# frozen_string_literal: true
require 'sketchup.rb'
require 'json'
require 'csv'
require_relative 'planner'
require_relative 'hardware'
require_relative 'smart_joint'
require_relative 'mounting'
require_relative 'manufacturing'
require_relative 'dashboard'

module ZillaFurnitureTools
  module Main
    extend self
    ATTRIBUTE = 'ZillaFurnitureTools'.freeze
    MIN_PANEL_MM = 12.0
    MAX_PANEL_MM = 25.0
    EXCLUDED_NAME = /drawer|shuh|shukh|шухляд|ящик|висув|фасад|front panel|напрямн|runner|slide/i
    SKIPPED_NAME = /concept|envelope|reference|handle|ручк|wheel|caster|опор|колес|ніжк|ножк/i

    def show_dialog
      unless @dialog
        @dialog = UI::HtmlDialog.new(
          dialog_title: 'Zilla Furniture Tools', preferences_key: 'ZillaFurnitureTools',
          scrollable: true, resizable: true, width: 1030, height: 745,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.set_file(File.join(__dir__, 'ui.html'))
        @dialog.add_action_callback('smartJoint') { |_ctx| start_smart_joint }
        @dialog.add_action_callback('scan') { |_ctx, json| render_scan(json) }
        @dialog.add_action_callback('guides') { |_ctx, json| create_guides(json) }
        @dialog.add_action_callback('export') { |_ctx, json| export_plan(json) }
        @dialog.add_action_callback('markDrawer') { |_ctx| mark_selected('drawer') }
        @dialog.add_action_callback('markCabinet') { |_ctx| mark_selected('cabinet') }
        @dialog.add_action_callback('markExclude') { |_ctx| mark_selected('exclude') }
      end
      @dialog.show
    end

    def start_smart_joint
      parts, skipped = collect_selected(include_drawer: true)
      if parts.length < 2
        raise 'At least two suitable cabinet panels are needed for Smart Joint'
      end
      model = Sketchup.active_model
      model.select_tool(SmartJointTool.new(parts))
      dispatch(type: 'message', message: "Smart Joint увімкнено. Наведіть мишу на стик та клацніть. Пропущено: #{skipped.length}.")
    rescue StandardError => e
      report_error(e)
    end

    def dispatch(payload)
      @dialog.execute_script("window.ZFT.receive(#{JSON.generate(payload)})") if @dialog
    end

    def parsed_options(json)
      raw = json.is_a?(String) && !json.empty? ? JSON.parse(json) : {}
      raise ArgumentError, 'Expected options object' unless raw.is_a?(Hash)
      Planner.options(raw)
    end

    def render_scan(json)
      options = parsed_options(json)
      parts, skipped = collect_selected
      plan = Planner.plan(parts, options)
      dispatch(
        type: 'plan', panels: parts.map { |p| { id: p[:id], name: p[:name],
          size_mm: p[:dims_mm].map { |v| v.round(1) }, kind: p[:kind] } },
        joints: plan[:joints], holes: plan[:holes], banding: plan[:banding],
        warnings: skipped + plan[:warnings], counts: {
          panels: parts.size, joints: plan[:joints].size,
          drill_operations: plan[:holes].size, edge_candidates: plan[:banding].size
        }
      )
    rescue StandardError => e
      report_error(e)
    end

    def collect_selected(include_drawer: false)
      model = Sketchup.active_model
      raise 'No active SketchUp model' unless model
      selected = model.selection.grep(Sketchup::Group) + model.selection.grep(Sketchup::ComponentInstance)
      raise 'Select a cabinet assembly or its panel components first' if selected.empty?

      parts = []
      skipped = []
      selected.uniq.each do |instance|
        scan_instance(instance, Geom::Transformation.new, [], false, parts, skipped, 0, include_drawer)
      end
      raise 'No rectangular 12–25 mm panels found in the selection' if parts.empty?
      [parts, skipped.uniq]
    end

    def scan_instance(instance, parent_transform, parent_ids, excluded, parts, skipped, depth, include_drawer = false)
      return if depth > 20 || instance.deleted?
      return if instance.get_attribute(ATTRIBUTE, 'generated', false)

      name = instance.name.to_s.strip
      name = instance.definition.name.to_s.strip if name.empty?
      name = "Part #{instance.persistent_id}" if name.empty?
      return if SKIPPED_NAME.match?(name)
      role = instance.get_attribute(ATTRIBUTE, 'role', '').to_s
      role = 'drawer' if role.empty? && EXCLUDED_NAME.match?(name)
      excluded ||= %w[exclude hardware].include?(role) || (role == 'drawer' && !include_drawer)
      path = parent_ids + [instance.persistent_id.to_s]
      transform = parent_transform * instance.transformation
      child_entities = instance.definition.entities
      children = child_entities.grep(Sketchup::Group) + child_entities.grep(Sketchup::ComponentInstance)
      faces = child_entities.grep(Sketchup::Face)
      edges = child_entities.grep(Sketchup::Edge)
      if children.empty? && ((faces.size == 6 && edges.size == 12) || verified_drilled_stock?(instance))
        return if excluded
        panel = panel_from(instance, name, path.join('/'), transform)
        if panel
          parts << panel
        else
          skipped << "Not a valid axis-aligned 12–25 mm panel: #{name}"
        end
      elsif !children.empty?
        children.each { |child| scan_instance(child, transform, path, excluded, parts, skipped, depth + 1, include_drawer) }
      elsif !excluded
        skipped << "Non-rectangular geometry skipped: #{name}"
      end
    end

    # Only our recorded, closed drilled stock qualifies; arbitrary meshes do not.
    def verified_drilled_stock?(instance)
      raw=instance.get_attribute(ATTRIBUTE,'actual_holes_json')
      return false unless raw && instance.definition.manifold?
      holes=JSON.parse(raw)
      return false if holes.empty?
      box=instance.definition.bounds
      return false unless rigid_transform?(instance.transformation)
      stock=box.width.to_mm*box.height.to_mm*box.depth.to_mm
      removed=holes.sum { |h| 16*(Float(h.fetch('diameter_mm'))/2)**2*Math.sin(Math::PI/16)*Float(h.fetch('depth_mm')) }
      return false unless (instance.volume.to_f*25.4**3-(stock-removed)).abs<1.0
      faces=instance.definition.entities.grep(Sketchup::Face)
      (0..2).all? do |axis|
        [box.min.to_a[axis],box.max.to_a[axis]].all? do |coordinate|
          faces.any? { |f| f.normal.to_a[axis].abs>0.9999 && f.vertices.all? { |v| (v.position.to_a[axis]-coordinate).abs<0.00001 } }
        end
      end
    rescue StandardError
      false
    end

    def rigid_transform?(transform)
      # Transformation#xaxis/yaxis/zaxis are normalized by SketchUp.
      # Read the matrix to detect scale and shear, including homogeneous scale.
      a=transform.to_a
      return false unless a[15].abs>1.0e-10 && [3,7,11].all? { |i| a[i].abs<1.0e-10 }
      axes=[0,4,8].map { |i| a[i,3].map { |v| v/a[15] } }
      axes.all? { |v| (v.sum { |x| x*x }-1).abs<0.00001 } &&
        axes.combination(2).all? { |u,v| (0..2).sum { |i| u[i]*v[i] }.abs<0.00001 }
    end

    def reject_existing_holes!(plan)
      roots=Sketchup.active_model.entities.grep(Sketchup::Group)+Sketchup.active_model.entities.grep(Sketchup::ComponentInstance)
      recorded=leaf_instances(roots).values.flat_map { |e,_| JSON.parse(e.get_attribute(ATTRIBUTE,'actual_holes_json','[]')) }
      duplicate=plan[:holes].find do |h|
        recorded.any? { |r| r['part_name']==h[:part_name] && 3.times.all? { |i| (r['xyz_mm'][i]-h[:xyz_mm][i]).abs<0.1 } }
      end
      raise "Отвір у #{duplicate[:part_name]} вже вирізано. Повторні мітки не створено." if duplicate
    end

    def panel_from(instance, name, id, transform)
      # In v0.1 all parts must be axis-aligned (90-degree rotations are OK).
      basis = [transform.xaxis, transform.yaxis, transform.zaxis]
      return nil unless basis.all? do |v|
        components = [v.x.to_f, v.y.to_f, v.z.to_f]
        norm = Math.sqrt(components.sum { |n| n * n })
        norm > 1.0e-8 && components.map { |n| (n / norm).abs }.max > 0.9999
      end

      box = instance.definition.bounds
      corners = 8.times.map do |index|
        local = Geom::Point3d.new(
          (index & 1).zero? ? box.min.x : box.max.x,
          (index & 2).zero? ? box.min.y : box.max.y,
          (index & 4).zero? ? box.min.z : box.max.z
        )
        point = local.transform(transform)
        [point.x.to_f * 25.4, point.y.to_f * 25.4, point.z.to_f * 25.4]
      end
      low = 3.times.map { |axis| corners.map { |p| p[axis] }.min }
      high = 3.times.map { |axis| corners.map { |p| p[axis] }.max }
      dims = 3.times.map { |axis| high[axis] - low[axis] }
      thin_axis = dims.each_with_index.min_by { |v, _| v }.last
      return nil unless dims[thin_axis].between?(MIN_PANEL_MM, MAX_PANEL_MM)
      return nil unless dims.each_with_index.all? { |v, i| i == thin_axis || v > 45.0 }

      { id: id, name: name, min: low, max: high, dims_mm: dims,
        thickness_axis: thin_axis, thickness_mm: dims[thin_axis], kind: 'cabinet' }
    end

    def build(json)
      options = parsed_options(json)
      parts, skipped = collect_selected
      [Planner.plan(parts, options), skipped, options]
    end

    def create_guides(json)
      plan, _skipped, options = build(json)
      if plan[:holes].empty?
        dispatch(type: 'message', message: 'No safe joints detected. No guides were created.')
        return
      end
      model = Sketchup.active_model
      model.start_operation('Zilla Furniture Tools: drill guides', true)
      begin
        model.active_entities.grep(Sketchup::Group).each do |entity|
          entity.erase! if entity.get_attribute(ATTRIBUTE, 'generated', false)
        end
        group = model.active_entities.add_group
        group.name = 'ZFT DRILL GUIDES — non-cutting'
        group.set_attribute(ATTRIBUTE, 'generated', true)
        group.set_attribute(ATTRIBUTE, 'plan_json', JSON.generate(plan))
        group.set_attribute(ATTRIBUTE, 'options_json', JSON.generate(options))
        plan[:holes].each do |hole|
          center = hole[:xyz_mm]
          direction = hole[:direction]
          # Slight offset opposite to drill direction makes the face guide visible.
          placed = center.each_with_index.map { |coordinate, index| (coordinate - direction[index] * 0.6).mm }
          point = Geom::Point3d.new(*placed)
          normal = Geom::Vector3d.new(*direction)
          group.entities.add_circle(point, normal, (hole[:diameter_mm] / 2.0).mm, 24)
          mark = group.entities.add_cpoint(point)
          mark.set_attribute(ATTRIBUTE, 'hole_json', JSON.generate(hole))
        end
        model.commit_operation
        dispatch(type: 'message', message: "Created #{plan[:holes].size} non-cutting drill markers. Geometry is unchanged.")
      rescue StandardError
        model.abort_operation
        raise
      end
    rescue StandardError => e
      report_error(e)
    end

    def export_plan(json)
      plan, skipped, options = build(json)
      suggested = 'zilla_furniture_manufacturing.csv'
      path = UI.savepanel('Export Zilla Furniture CSV', nil, suggested)
      return unless path
      headings = %w[record_type joint_id part_id part_name operation x_mm y_mm z_mm local_x_mm local_y_mm local_z_mm
                    dir_x dir_y dir_z diameter_mm depth_mm edge edge_length_mm edge_banding_mm note]
      rows = []
      plan[:holes].each do |h|
        rows << { record_type: 'DRILL', joint_id: h[:joint_id], part_id: h[:part_id], part_name: h[:part_name],
                  operation: h[:kind], x_mm: h[:xyz_mm][0], y_mm: h[:xyz_mm][1], z_mm: h[:xyz_mm][2],
                  local_x_mm: h[:local_bbox_mm][0], local_y_mm: h[:local_bbox_mm][1],
                  local_z_mm: h[:local_bbox_mm][2], dir_x: h[:direction][0], dir_y: h[:direction][1],
                  dir_z: h[:direction][2], diameter_mm: h[:diameter_mm], depth_mm: h[:depth_mm],
                  note: 'REVIEW before machining; bbox-local coordinates, NOT a CNC program' }
      end
      plan[:banding].each do |b|
        rows << { record_type: 'EDGE_CANDIDATE', part_id: b[:part_id], part_name: b[:part_name],
                  operation: b[:status], edge: b[:edge], edge_length_mm: b[:length_mm],
                  edge_banding_mm: b[:band_thickness_mm], note: 'Confirm visibility and OpenCutList edge assignment' }
      end
      plan[:parts].each do |p|
        rows << { record_type: 'PANEL', part_id: p[:id], part_name: p[:name],
                  operation: 'PART_DIMENSIONS_BBOX', x_mm: p[:dims_mm][0].round(2),
                  y_mm: p[:dims_mm][1].round(2), z_mm: p[:dims_mm][2].round(2),
                  note: 'World-aligned bounding dimensions; confirm grain direction' }
      end
      content = CSV.generate(col_sep: ';', force_quotes: true) do |csv|
        csv << headings
        rows.each { |row| csv << headings.map { |key| row[key.to_sym] } }
      end
      File.binwrite(path, "\xEF\xBB\xBF".b + content.encode('UTF-8').b)
      dispatch(type: 'message', message: "Exported #{rows.size} rows to #{path}. Review #{skipped.size + plan[:warnings].size} warnings before fabrication.")
    rescue StandardError => e
      report_error(e)
    end

    def mark_selected(role)
      model = Sketchup.active_model
      selected = model.selection.grep(Sketchup::Group) + model.selection.grep(Sketchup::ComponentInstance)
      if selected.empty?
        dispatch(type: 'message', message: 'Select one or more groups/components to set their role.')
        return
      end
      model.start_operation('ZFT: set part role', true)
      begin
        selected.uniq.each { |inst| inst.set_attribute(ATTRIBUTE, 'role', role) }
        model.commit_operation
        dispatch(type: 'message', message: "Marked #{selected.size} selected component(s) as #{role}.")
      rescue StandardError
        model.abort_operation
        raise
      end
    rescue StandardError => e
      report_error(e)
    end

    def drawer_box_guides
      parts, = collect_selected(include_drawer: true)
      existing = Sketchup.active_model.active_entities.grep(Sketchup::Group).any? do |group|
        raw = group.get_attribute(ATTRIBUTE, 'plan_json')
        raw && JSON.parse(raw)['kind'] == 'drawer_box'
      end
      raise 'Drawer box guides already exist in this editing context' if existing
      values = UI.inputbox(['Confirmats per corner', 'Offset from top/bottom, mm'],
                           [2, 25], 'ZFT — four drawer wall joints')
      return unless values
      plan = Hardware.drawer_box(parts, count: values[0], offset_mm: values[1])
      add_mount_guides(plan)
    rescue StandardError => e
      report_error(e)
      UI.messagebox("ZFT: #{e.message}")
    end

    def drawer_front_guides
      parts, = collect_selected(include_drawer: true)
      front = parts.find { |p| p[:name].match?(/front_facade|фасад/i) }
      wall = parts.find { |p| p[:name].match?(/drawer_front_wall|передня.*шухляд/i) }
      raise 'Select the drawer facade and front wall, or their parent assembly' unless front && wall
      values = UI.inputbox(['Fasteners (2–4)', 'Offset from both ends, mm',
                            'Wall through-hole diameter, mm', 'Facade blind pilot diameter, mm',
                            'Facade blind depth, mm'],
                           [2, 80, 5, 5, 12], 'ZFT — drawer front, GUIDES ONLY')
      return unless values
      plan = Mounting.drawer_front(front, wall, count: values[0], offset_mm: values[1],
                                  wall_clearance_diameter_mm: values[2],
                                  front_pilot_diameter_mm: values[3], front_depth_mm: values[4])
      add_mount_guides(plan)
    rescue StandardError => e
      report_error(e)
      UI.messagebox("ZFT: #{e.message}")
    end

    def slide_guides
      parts, = collect_selected(include_drawer: true)
      sides = %w[Left Right].filter_map do |side|
        cabinet = parts.find { |p| p[:name] == "#{side}_Side" }
        drawer = parts.find { |p| p[:name] == "Drawer_#{side}" }
        [side, cabinet, drawer] if cabinet && drawer
      end
      raise 'Select a cabinet side and matching drawer side, or their parent assembly' if sides.empty?
      side, cabinet, drawer = if sides.length == 1
        sides.first
      else
        choice = UI.inputbox(['Side'], ['Left'], ['Left|Right'], 'ZFT — select slide side')
        return unless choice
        sides.find { |item| item[0] == choice[0] } || raise('Selected side is unavailable')
      end
      values = UI.inputbox(['Cabinet rail centers from front, mm (comma-separated)',
                            'Drawer rail centers from front, mm (comma-separated)',
                            'Rail center above drawer-side bottom, mm', 'Blind guide diameter, mm', 'Blind guide depth, mm'],
                           ['', '', 21, 5, 10], "ZFT — #{side} runner, enter exact SKU drawing positions")
      return unless values
      plan = Mounting.slide_pair(cabinet, drawer,
        cabinet_offsets_mm: values[0], drawer_offsets_mm: values[1],
        height_from_drawer_bottom_mm: values[2], diameter_mm: values[3], depth_mm: values[4])
      add_mount_guides(plan)
    rescue StandardError => e
      report_error(e)
      UI.messagebox("ZFT: #{e.message}")
    end

    def add_mount_guides(plan, notify: true)
      reject_existing_holes!(plan)
      model = Sketchup.active_model
      model.start_operation("ZFT: #{plan[:kind]} guides", true)
      begin
        group = model.active_entities.add_group
        group.name = "ZFT #{plan[:kind]} — non-cutting guides"
        group.set_attribute(ATTRIBUTE, 'generated', true)
        group.set_attribute(ATTRIBUTE, 'plan_json', JSON.generate(plan))
        plan[:holes].each do |hole|
          position = hole[:xyz_mm].map(&:mm)
          point = Geom::Point3d.new(*position)
          normal = Geom::Vector3d.new(*hole[:direction])
          group.entities.add_circle(point, normal, (hole[:diameter_mm] / 2.0).mm, 24)
          marker = group.entities.add_cpoint(point)
          marker.set_attribute(ATTRIBUTE, 'hole_json', JSON.generate(hole))
        end
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      UI.messagebox("Створено #{plan[:holes].length} знімних міток. ДСП не просвердлено. #{plan[:warning]}") if notify
      plan
    end

    def export_mount_guides_csv
      model = Sketchup.active_model
      groups = model.active_entities.grep(Sketchup::Group).select do |group|
        group.get_attribute(ATTRIBUTE, 'generated', false) &&
          group.name.start_with?('ZFT drawer_front', 'ZFT slide_pair', 'ZFT drawer_box')
      end
      raise 'No drawer-front or slide guide groups in the active editing context' if groups.empty?
      path = UI.savepanel('Export mounting guides CSV', nil, 'zilla_mounting_guides_REVIEW.csv')
      return unless path
      content = mount_guides_csv(groups)
      File.binwrite(path, "\xEF\xBB\xBF".b + content.encode('UTF-8').b)
      UI.messagebox('CSV збережено. Це контрольні координати, не файл імпорту свердлінь у Viyar Pro.')
      path
    rescue StandardError => e
      report_error(e)
      UI.messagebox("ZFT: #{e.message}")
    end

    def mount_guides_csv(groups)
      headings = %w[status profile operation part_id part_name x_mm y_mm z_mm dir_x dir_y dir_z diameter_mm depth_mm warning]
      CSV.generate(col_sep: ';', force_quotes: true) do |csv|
        csv << headings
        groups.each do |group|
          plan = JSON.parse(group.get_attribute(ATTRIBUTE, 'plan_json'))
          plan.fetch('holes').each do |hole|
            xyz = hole.fetch('xyz_mm')
            direction = hole.fetch('direction')
            csv << ['GUIDE_ONLY_NOT_VIYAR_IMPORT', plan['profile_id'], hole['kind'], hole['part_id'],
                    hole['part_name'], *xyz, *direction, hole['diameter_mm'], hole['depth_mm'], plan['warning']]
          end
        end
      end
    end

    def leaf_instances(roots)
      found = {}
      walk = lambda do |instance, parent_transform|
        children = instance.definition.entities.grep(Sketchup::Group) +
          instance.definition.entities.grep(Sketchup::ComponentInstance)
        if children.empty?
          raise "Duplicate component name: #{instance.name}" if found.key?(instance.name)
          found[instance.name] = [instance, parent_transform]
        else
          children.each { |child| walk.call(child, parent_transform * instance.transformation) }
        end
      end
      roots.each { |root| walk.call(root, Geom::Transformation.new) }
      found
    end

    def apply_edge_plan_dialog
      roots = Sketchup.active_model.selection.grep(Sketchup::Group) +
        Sketchup.active_model.selection.grep(Sketchup::ComponentInstance)
      raise 'Select the cabinet assembly first' if roots.empty?
      csv_path = UI.openpanel('Choose edge plan CSV', nil, 'CSV|*.csv||')
      return unless csv_path
      names = CSV.read(csv_path, headers: true, col_sep: ';', encoding: 'bom|utf-8').map { |row| row['Деталь'] }
      found = leaf_instances(roots)
      raise 'Edge plan parts are missing from selection' unless (names - found.keys).empty?
      model = Sketchup.active_model
      model.start_operation('ZFT: apply OCL edge banding', true)
      begin
        result = Manufacturing.apply_edge_plan!(model, names.map { |name| found.fetch(name).first }, csv_path)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      UI.messagebox("Крайку призначено для #{result.length} плит. Перевірте OpenCutList та пильні розміри.")
    rescue StandardError => e
      report_error(e)
      UI.messagebox("ZFT: #{e.message}")
    end

    def drill_selected_guides_in_copy
      model = Sketchup.active_model
      guides = model.selection.grep(Sketchup::Group).select do |group|
        group.get_attribute(ATTRIBUTE, 'generated', false) && group.get_attribute(ATTRIBUTE, 'plan_json')
      end
      raise 'Select one or more ZFT guide groups first' if guides.empty?
      holes = guides.flat_map { |group| JSON.parse(group.get_attribute(ATTRIBUTE, 'plan_json')).fetch('holes') }
      raise 'Selected guides contain no holes' if holes.empty?
      path = UI.savepanel('Save a NEW drilled SketchUp test copy', nil, 'ZFT_drilling_TEST.skp')
      return unless path
      path += '.skp' unless path.downcase.end_with?('.skp')
      raise 'Choose a new file name; existing files cannot be overwritten' if File.exist?(path)
      raise 'Could not save test copy' unless model.save(path)
      roots = model.entities.grep(Sketchup::Group) + model.entities.grep(Sketchup::ComponentInstance)
      found = leaf_instances(roots)
      model.start_operation('ZFT: cut selected guide holes', true)
      begin
        holes.each do |raw|
          hole = raw.transform_keys(&:to_sym)
          instance, parent_transform = found.fetch(hole.fetch(:part_name))
          Manufacturing.cut_hole!(instance, hole, parent_transform)
        end
        guides.each { |group| group.hidden = true }
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      raise 'Could not save drilled test copy' unless model.save
      UI.messagebox("Вирізано #{holes.length} отворів у тестовій копії. Перевірте кожну деталь і фурнітуру перед експортом.")
    rescue StandardError => e
      report_error(e)
      UI.messagebox("ZFT: #{e.message}")
    end

    def report_error(error)
      warn("[ZillaFurnitureTools] #{error.class}: #{error.message}\n#{Array(error.backtrace).first(4).join("\n")}")
      dispatch(type: 'error', message: error.message.to_s)
    end

    unless defined?(@menu_installed) && @menu_installed
      Dashboard.install
      @menu_installed = true
    end
  end
end
