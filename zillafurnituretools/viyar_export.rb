# frozen_string_literal: true
require 'csv'
require 'json'
require 'fileutils'

module ZillaFurnitureTools
  # The official dxf2viyarpro v1.0.9 exporter exports an ABF_Flatten group
  # with SketchUp's AutoCAD 2007 options. This adapter uses that same input
  # and leaves the source assembly untouched.
  module ViyarExport
    extend self

    def flatten_groups(model)
      model.entities.grep(Sketchup::Group).select { |group| group.name == 'ABF_Flatten' && !group.hidden? }
    end

    def preflight(model, roots, require_flatten: true)
      raise 'Збережіть модель SketchUp перед експортом.' if model.path.to_s.empty?
      raise 'Вийдіть із редагування компонента.' if model.active_path
      if require_flatten && model.get_attribute('TechnicalReview', 'legend')
        raise 'Відкрийте чисту виробничу копію SKP без технічних осей.'
      end
      raise 'Виділіть збірку для експорту деталей.' if roots.empty?
      if require_flatten && flatten_groups(model).empty?
        raise 'ABF_Flatten не знайдено. Створіть розкладку кнопкою Flatten у ABF.'
      end
      parts = PartInventory.records(roots)
      edged = parts.select { |part| part[:instance].get_attribute(Main::ATTRIBUTE, 'edge_plan') }
      raise 'Немає плит із картою крайок.' if edged.empty?
      unedged = parts.select do |part|
        dims = part[:local_dimensions_mm]
        !part[:instance].name.match?(Main::SKIPPED_NAME) &&
          dims.any? { |value| (value - 18).abs < 0.1 } &&
          dims.count { |value| value > 50 } >= 2 &&
          !part[:instance].get_attribute(Main::ATTRIBUTE, 'edge_plan')
      end
      raise "18 мм плити без карти крайок: #{unedged.map { |p| p[:instance].name }.join(', ')}" unless unedged.empty?
      rows = Dashboard.cutting_rows(roots)
      holes = edged.flat_map do |part|
        raw = part[:instance].get_attribute(Main::ATTRIBUTE, 'actual_holes_json', '[]')
        JSON.parse(raw).map { |hole| hole.merge('instance_path' => part[:path]) }
      end
      raise 'Немає зафіксованих фізично вирізаних отворів. Мітки не є свердлінням.' if holes.empty?
      if require_flatten && flatten_groups(model).all? { |g| g.entities.empty? }
        raise 'Немає геометрії в ABF_Flatten.'
      end
      {parts: parts, edged: edged, rows: rows, holes: holes,
       flatten_count: flatten_groups(model).length}
    end

    def write_flatten_dxf(model, path)
      keep = flatten_groups(model)
      raise 'ABF_Flatten відсутній.' if keep.empty?
      old_units = model.options['UnitsOptions']['LengthUnit']
      old_selection = model.selection.to_a
      result = false
      model.start_operation('ZFT temporary ABF DXF export', true)
      begin
        model.entities.to_a.each { |entity| entity.erase! unless keep.include?(entity) }
        model.options['UnitsOptions']['LengthUnit'] = 2
        result = model.export(path, show_summary: false, acad_version: 'acad_2007',
                              faces_flag: true, text: false)
      ensure
        model.abort_operation
        model.options['UnitsOptions']['LengthUnit'] = old_units
        model.selection.clear
        model.selection.add(old_selection.select(&:valid?))
      end
      raise 'SketchUp не створив DXF з ABF_Flatten.' unless result && File.file?(path) && File.size(path) > 0
      path
    end

    def export_package(model, roots, directory, abf: false)
      audit = preflight(model, roots, require_flatten: abf)
      raise 'Папка експорту вже існує.' if File.exist?(directory)
      FileUtils.mkdir_p(directory)
      begin
        Dashboard.write_csv(File.join(directory, '01_parts_edges_viyar.csv'), roots)
        write_flatten_dxf(model, File.join(directory, '02_ABF_flatten_viyar.dxf')) if abf
        CSV.open(File.join(directory, '03_drilling_review.csv'), 'wb', col_sep: ';', encoding: 'UTF-8') do |csv|
          csv << %w[instance_path part_name operation x_mm y_mm z_mm dir_x dir_y dir_z diameter_mm depth_mm]
          audit[:holes].each do |hole|
            csv << [hole['instance_path'], hole['part_name'], hole['kind'],
                    *hole['xyz_mm'], *hole['direction'], hole['diameter_mm'], hole['depth_mm']]
          end
        end
        hardware = hardware_rows(model)
        CSV.open(File.join(directory, '04_hardware_review.csv'), 'wb', col_sep: ';', encoding: 'UTF-8') do |csv|
          csv << %w[type viyar_code quantity finish status note]
          hardware.each { |row| csv << row }
        end
        manifest = {
          source_model: model.path, exported_at_utc: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
          format: abf ? 'ABF_Flatten_DXF_ACAD_2007' : 'Viyar_saw_CSV_only',
          parts_with_edge_plan: audit[:edged].length,
          recorded_physical_holes: audit[:holes].length,
          abf_flatten_groups: audit[:flatten_count],
          material_selection: project_materials(model),
          files: ['01_parts_edges_viyar.csv', ('02_ABF_flatten_viyar.dxf' if abf),
                  '03_drilling_review.csv', '04_hardware_review.csv'].compact,
          hardware_rows: hardware.length,
          note: abf ? 'Hardware and drilling CSV are review sheets, not ViyarPro import files. Verify every operation after DXF import.' :
            'Only parts and edge CSV is a Viyar import candidate. Drilling and hardware CSV are review sheets and are not imported as operations.'
        }
        File.write(File.join(directory, 'manifest.json'), JSON.pretty_generate(manifest), mode: 'w:UTF-8')
        manifest
      rescue StandardError
        FileUtils.remove_entry(directory) if Dir.exist?(directory)
        raise
      end
    end

    def hardware_rows(model)
      hardware = project_data(model).fetch('hardware', {})
      hardware.map do |kind, item|
        next unless item.is_a?(Hash)
        code = item['viyar_code'] || item['model']
        quantity = item['count'] || (kind == 'slide' ? '1 pair per drawer' : '')
        status = code && !code.to_s.empty? ? 'VERIFY_QUANTITY_AND_MOUNTING' : 'MISSING_ARTICLE'
        [kind, code, quantity, item['finish'], status, 'Verify exact supplier drawing and screws']
      end.compact
    end

    def project_materials(model)
      project_data(model).fetch('materials', {}).transform_values do |item|
        item.is_a?(Hash) ? {'viyar_code' => item['viyar_code'], 'name' => item['name']} : item
      end
    end

    def project_data(model)
      project = File.expand_path('../../project.json', File.dirname(model.path))
      File.file?(project) ? JSON.parse(File.read(project, encoding: 'UTF-8')) : {}
    end
  end
end
