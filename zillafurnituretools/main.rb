# frozen_string_literal: true
require 'sketchup.rb'
require 'json'
require 'csv'
require_relative 'planner'
require_relative 'hardware'
require_relative 'smart_joint'
require_relative 'mounting'

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
      parts, skipped = collect_selected
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
      if children.empty? && faces.size == 6 && edges.size == 12
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

    def drawer_front_guides
      parts, = collect_selected(include_drawer: true)
      front = parts.find { |p| p[:name].match?(/front_facade|фасад/i) }
      wall = parts.find { |p| p[:name].match?(/drawer_front_wall|передня.*шухляд/i) }
      raise 'Select the drawer facade and front wall, or their parent assembly' unless front && wall
      values = UI.inputbox(['Fasteners (2–4)', 'Offset from both ends, mm', 'Guide diameter, mm', 'Facade blind depth, mm'],
                           [2, 80, 5, 12], 'ZFT — drawer front, GUIDES ONLY')
      return unless values
      plan = Mounting.drawer_front(front, wall, count: values[0], offset_mm: values[1],
                                  diameter_mm: values[2], front_depth_mm: values[3])
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
          group.name.start_with?('ZFT drawer_front', 'ZFT slide_pair')
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

    def report_error(error)
      warn("[ZillaFurnitureTools] #{error.class}: #{error.message}\n#{Array(error.backtrace).first(4).join("\n")}")
      dispatch(type: 'error', message: error.message.to_s)
    end

    unless defined?(@menu_installed) && @menu_installed
      menu = UI.menu('Plugins')
      menu.add_item('Zilla Furniture Tools — drill planner') { show_dialog }
      menu.add_item('Zilla Furniture Tools — Smart Joint') { start_smart_joint }
      menu.add_item('Zilla Furniture Tools — Drawer front guides') { drawer_front_guides }
      menu.add_item('Zilla Furniture Tools — Slide guides') { slide_guides }
      menu.add_item('Zilla Furniture Tools — Export mounting guides CSV') { export_mount_guides_csv }
      @menu_installed = true
    end
  end
end
