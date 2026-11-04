# frozen_string_literal: true
require 'sketchup.rb'
require 'json'
require 'csv'
require_relative 'hardware'

module ZillaFurnitureTools
  # Interactive, non-destructive manual joint planner.
  # Assumes 90-degree rectangular stock; transformed/non-rectangular parts are
  # filtered out by Main's conservative panel scanner.
  class SmartJointTool
    attr_reader :parts, :active, :last_plan

    def initialize(parts)
      @parts = parts.select { |p| p[:kind] == 'cabinet' }
      @part_by_id = @parts.each_with_object({}) { |p, h| h[p[:id]] = p }
      @links = []
      opts = Planner.options
      @parts.combination(2) do |a, b|
        hits = [Planner.candidate(a, b, opts), Planner.candidate(b, a, opts)].compact
        @links << hits.first.merge(a_id: a[:id], b_id: b[:id]) if hits.length == 1
      end
      @hover = nil
      @active = nil
      @last_plan = nil
      @profile_id = 'confirmat_7x50'
      @count = 2
      @offset_mm = 50.0
    end

    def activate
      Sketchup.set_status_text('ZFT Smart Joint: наведiть на край стику, клацніть. Esc — закрити.', SB_PROMPT)
    end

    def deactivate(view)
      @dialog.close if @dialog && @dialog.visible?
      view.invalidate
    end

    def onCancel(_reason, view)
      if @active
        @active = nil
        @last_plan = nil
        @dialog.close if @dialog && @dialog.visible?
        view.invalidate
      else
        Sketchup.active_model.select_tool(nil)
      end
    end

    def pick_part(view, x, y)
      helper = view.pick_helper
      helper.do_pick(x, y, 5)
      helper.count.times do |index|
        path = helper.path_at(index)
        next unless path
        ids = path.select { |entity| entity.respond_to?(:persistent_id) &&
                            (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) }
                  .map { |item| item.persistent_id.to_s }
        next if ids.empty?
        # Keep full nested path. An explicit group selection can start at a root.
        match = @parts.find { |p| ids.join('/').end_with?(p[:id]) }
        return match if match
      end
      nil
    end

    def onMouseMove(_flags, x, y, view)
      return if @active
      panel = pick_part(view, x, y)
      viable = panel ? @links.select { |link| [link[:a_id], link[:b_id]].include?(panel[:id]) } : []
      @hover = viable.min_by { |link| screen_distance_sq(view, link, x, y) }
      @hover = nil if @hover && screen_distance_sq(view, @hover, x, y) > 90 * 90
      view.tooltip = @hover ? "З’єднання: #{@hover[:shell][:name]} ↔ #{@hover[:butt][:name]}" : 'Наведіть на стик двох ДСП-деталей'
      view.invalidate
    rescue StandardError => e
      warn("[ZFT SmartJoint] hover: #{e.message}")
      @hover = nil
    end

    def onLButtonDown(_flags, x, y, view)
      return if @active
      onMouseMove(0, x, y, view)
      return unless @hover
      @active = @hover
      @hover = nil
      recalculate
      open_dialog
      view.invalidate
    rescue StandardError => e
      UI.messagebox("ZFT Smart Joint: #{e.message}")
    end

    def onKeyDown(key, _repeat, _flags, view)
      onCancel(0, view) if key == 27
    end

    def update_settings(json)
      data = JSON.parse(json)
      @profile_id = data.fetch('profile_id').to_s
      @count = Integer(data.fetch('count'))
      @offset_mm = Float(data.fetch('offset_mm'))
      recalculate
      Sketchup.active_model.active_view.invalidate
    rescue StandardError => e
      communicate(type: 'error', message: e.message)
    end

    def recalculate
      return unless @active
      @last_plan = Hardware.plan_pair(
        @active[:shell], @active[:butt], profile_id: @profile_id,
        count: @count, offset_mm: @offset_mm
      )
      communicate(type: 'preview', plan: @last_plan)
    rescue StandardError => e
      @last_plan = nil
      communicate(type: 'error', message: e.message)
    end

    def draw(view)
      joint = @active || @hover
      return unless joint
      endpoints = joint_points(joint)
      view.line_width = 5
      view.drawing_color = @active ? Sketchup::Color.new(58, 205, 165) : Sketchup::Color.new(40, 178, 239)
      view.draw(GL_LINES, endpoints)
      return unless @last_plan
      @last_plan[:holes].each do |h|
        axis = h[:direction].index { |v| v != 0 }
        other = [0, 1, 2] - [axis]
        xyz = h[:xyz_mm]
        center = xyz.map { |n| n.mm }
        first = center.dup
        second = center.dup
        third = center.dup
        fourth = center.dup
        first[other[0]] -= 6.mm
        second[other[0]] += 6.mm
        third[other[1]] -= 6.mm
        fourth[other[1]] += 6.mm
        view.drawing_color = h[:kind].include?('dowel') ? Sketchup::Color.new(244, 195, 64) : Sketchup::Color.new(236, 86, 84)
        view.line_width = 2
        view.draw(GL_LINES, [Geom::Point3d.new(*first), Geom::Point3d.new(*second),
                             Geom::Point3d.new(*third), Geom::Point3d.new(*fourth)])
      end
    end

    def joint_points(joint)
      center = Array.new(3, 0.0)
      center[joint[:axis]] = joint[:contact]
      b = joint[:butt]
      center[b[:thickness_axis]] = (b[:min][b[:thickness_axis]] + b[:max][b[:thickness_axis]]) / 2.0
      a = center.dup
      z = center.dup
      a[joint[:rail]] = joint[:start]
      z[joint[:rail]] = joint[:finish]
      [Geom::Point3d.new(*a.map(&:mm)), Geom::Point3d.new(*z.map(&:mm))]
    end

    def screen_distance_sq(view, joint, px, py)
      a, b = joint_points(joint).map { |p| view.screen_coords(p) }
      vx, vy = b.x - a.x, b.y - a.y
      t = vx * vx + vy * vy
      t = t.zero? ? 0 : [[((px - a.x) * vx + (py - a.y) * vy) / t, 0].max, 1].min
      (px - a.x - t * vx)**2 + (py - a.y - t * vy)**2
    end

    def apply_guides
      unless @last_plan && @last_plan[:holes].any?
        communicate(type: 'error', message: 'Немає безпечної розмітки. Перевірте параметри.')
        return
      end
      model = Sketchup.active_model
      model.start_operation('ZFT: manual joint drill guides', true)
      begin
        group = model.active_entities.add_group
        group.name = "ZFT • #{@profile_id} • non-cutting guides"
        group.set_attribute(Main::ATTRIBUTE, 'generated', true)
        group.set_attribute(Main::ATTRIBUTE, 'manual', true)
        group.set_attribute(Main::ATTRIBUTE, 'plan_json', JSON.generate(@last_plan))
        @last_plan[:holes].each do |hole|
          coordinates = hole[:xyz_mm]
          dir = hole[:direction]
          point = Geom::Point3d.new(*coordinates.each_with_index.map { |v, i| (v - dir[i] * 0.6).mm })
          normal = Geom::Vector3d.new(*dir)
          group.entities.add_circle(point, normal, (hole[:diameter_mm] / 2.0).mm, 24)
          marker = group.entities.add_cpoint(point)
          marker.set_attribute(Main::ATTRIBUTE, 'hole_json', JSON.generate(hole))
        end
        model.commit_operation
        communicate(type: 'message', message: "Створено #{@last_plan[:holes].length} маркерів. ДСП не змінено. Ctrl+Z для скасування.")
      rescue StandardError
        model.abort_operation
        raise
      end
    rescue StandardError => e
      communicate(type: 'error', message: e.message)
    end

    def export_manual
      unless @last_plan && @last_plan[:holes].any?
        communicate(type: 'error', message: 'Немає плану для експорту')
        return
      end
      path = UI.savepanel('ZFT — Manual joint drilling CSV', nil, 'zilla_joint_drillings.csv')
      return unless path
      columns = %w[joint_id profile part_id part_name operation x_mm y_mm z_mm
                   local_bbox_x_mm local_bbox_y_mm local_bbox_z_mm dir_x dir_y dir_z
                   diameter_mm depth_mm warning]
      result = CSV.generate(col_sep: ';', force_quotes: true) do |csv|
        csv << columns
        @last_plan[:holes].each do |hole|
          row = {
            joint_id: hole[:joint_id], profile: @profile_id,
            part_id: hole[:part_id], part_name: hole[:part_name],
            operation: hole[:kind], x_mm: hole[:xyz_mm][0], y_mm: hole[:xyz_mm][1],
            z_mm: hole[:xyz_mm][2], local_bbox_x_mm: hole[:local_bbox_mm][0],
            local_bbox_y_mm: hole[:local_bbox_mm][1], local_bbox_z_mm: hole[:local_bbox_mm][2],
            dir_x: hole[:direction][0], dir_y: hole[:direction][1], dir_z: hole[:direction][2],
            diameter_mm: hole[:diameter_mm], depth_mm: hole[:depth_mm],
            warning: 'PREVIEW ONLY; verify manufacturer drill pattern and part orientation'
          }
          csv << columns.map { |key| row[key.to_sym] }
        end
      end
      File.binwrite(path, "\xEF\xBB\xBF".b + result.encode('UTF-8').b)
      communicate(type: 'message', message: "CSV збережено: #{path}. Це НЕ верстатний файл.")
    rescue StandardError => e
      communicate(type: 'error', message: e.message)
    end

    def open_dialog
      @dialog ||= UI::HtmlDialog.new(dialog_title: 'ZFT — Smart Joint', preferences_key: 'ZFTSmartJoint',
                                    width: 450, height: 660, resizable: true, style: UI::HtmlDialog::STYLE_DIALOG)
      @dialog.set_file(File.join(__dir__, 'smart_joint.html'))
      @dialog.add_action_callback('updateFitting') { |_ctx, value| update_settings(value) }
      @dialog.add_action_callback('applyManual') { |_ctx| apply_guides }
      @dialog.add_action_callback('exportManual') { |_ctx| export_manual }
      @dialog.add_action_callback('resetManual') { |_ctx| reset_selection }
      @dialog.add_action_callback('getManual') { |_ctx| sync_dialog }
      @dialog.show
      sync_dialog
    end

    def sync_dialog
      communicate(type: 'init', catalog: Hardware.catalog,
                  selected: { profile_id: @profile_id, count: @count, offset_mm: @offset_mm },
                  joint: @active && { name: "#{@active[:shell][:name]} ↔ #{@active[:butt][:name]}",
                                      length_mm: Planner.round(@active[:length_mm]) })
      communicate(type: 'preview', plan: @last_plan) if @last_plan
    end

    def reset_selection
      @active = nil
      @last_plan = nil
      @dialog.close if @dialog && @dialog.visible?
      Sketchup.active_model.active_view.invalidate
    end

    def communicate(payload)
      return unless @dialog && @dialog.visible?
      @dialog.execute_script("window.ZFTManual.receive(#{JSON.generate(payload)})")
    end
  end
end
