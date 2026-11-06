# frozen_string_literal: true
module ZillaFurnitureTools
  module Dashboard
    extend self

    def show
      unless @window
        @window=UI::HtmlDialog.new(dialog_title:'Zilla Furniture Tools',preferences_key:'ZFT_Hub',
          width:470,height:770,resizable:true,scrollable:true,style:UI::HtmlDialog::STYLE_DIALOG)
        @window.set_file(File.join(__dir__,'dashboard.html'))
        @window.add_action_callback('action') { |_ctx,id| run(id) }
        @window.set_on_closed { @window=nil }
      end
      @window.show
    end

    def message(text)
      @window.execute_script("setStatus(#{JSON.generate(text)})") if @window
    end

    def run(id)
      m=Sketchup.active_model
      case id
      when 'select'
        roots=m.active_entities.grep(Sketchup::Group)+m.active_entities.grep(Sketchup::ComponentInstance)
        roots.reject! { |e| e.hidden? || !e.layer.visible? || e.get_attribute(Main::ATTRIBUTE,'generated',false) || e.name.start_with?('REVIEW ONLY') }
        m.selection.clear; m.selection.add(roots)
        message("Виділено збірок: #{roots.length}")
      when 'joint' then Main.start_smart_joint
      when 'drawer' then Main.drawer_box_guides
      when 'front' then Main.drawer_front_guides
      when 'slides' then Main.slide_guides
      when 'edges' then Main.apply_edge_plan_dialog
      when 'drill' then Main.drill_selected_guides_in_copy
      when 'coordinates' then export_coordinates
      when 'planner' then Main.show_dialog
      when 'csv' then export_csv
      when 'dxf' then export_dxf
      when 'xray'
        m.rendering_options['ModelTransparency']=!m.rendering_options['ModelTransparency']
        message(m.rendering_options['ModelTransparency'] ? 'X-Ray увімкнено' : 'X-Ray вимкнено')
      when 'perspective'
        m.active_view.camera.perspective=true; m.active_view.zoom_extents
        message('Перспектива. Обертання — середня кнопка миші; масштаб — коліщатко.')
      when 'scene01','scene02','scene03'
        prefix=id[-2,2]+' -'
        page=m.pages.find { |p| p.name.start_with?(prefix) }
        raise 'Ці сцени є у файлі TECHNICAL_REVIEW.skp. Відкрийте його через File → Open.' unless page
        m.pages.selected_page=page
        message(page.name)
      when 'ready'
        message("#{File.basename(m.path).empty? ? 'Нова модель' : File.basename(m.path)} • Виділено: #{m.selection.length}")
      end
      m.active_view.invalidate
    rescue StandardError => e
      message(e.message)
      UI.messagebox(e.message) unless @window
    end

    # Edge metadata is stored in each panel's LOCAL axes. Do not mix it with world dimensions.
    def cutting_rows(roots)
      parts=Main.leaf_instances(roots)
      rows=[]
      parts.each do |name,(instance,parent)|
        raw=instance.get_attribute(Main::ATTRIBUTE,'edge_plan')
        next unless raw
        transform=parent*instance.transformation
        raise "Масштабована деталь: #{name}" unless Main.rigid_transform?(transform)
        b=instance.definition.bounds
        dims=[b.width,b.height,b.depth].map { |v| v.to_f*25.4 }
        thin=(0..2).min_by { |i| dims[i] }
        raise "Очікується ДСП 18 мм: #{name}" unless (dims[thin]-18).abs<0.1
        long,short=([0,1,2]-[thin]).sort_by { |i| -dims[i] }
        edges=JSON.parse(raw).to_h { |axis,side,code| [[axis,side],code] }
        codes=[[short,'max'],[short,'min'],[long,'min'],[long,'max']].map { |key| edges.fetch(key) }
        raise "Невідома крайка: #{name}" unless codes.all? { |c| [0,1,2].include?(c) }
        thickness={0=>0.0,1=>0.5,2=>2.0}
        t,bottom,l,r=codes.map { |c| thickness.fetch(c) }
        rows << [(dims[long]-l-r).round(3),(dims[short]-t-bottom).round(3),1,*codes,'+',name,1]
      end
      raise 'Немає деталей із призначеною картою крайок. Виділіть збірку та призначте крайку.' if rows.empty?
      rows
    end

    def write_csv(path,roots)
      rows=cutting_rows(roots)
      content=CSV.generate(col_sep:';') { |csv| rows.each { |row| csv << row } }
      File.binwrite(path,"\xEF\xBB\xBF".b+content.encode('UTF-8').b)
      rows.length
    end

    def export_csv
      m=Sketchup.active_model
      roots=m.selection.grep(Sketchup::Group)+m.selection.grep(Sketchup::ComponentInstance)
      raise 'Виділіть збірку перед експортом.' if roots.empty?
      cutting_rows(roots)
      path=UI.savepanel('CSV деталей і крайки Viyar',nil,'Viyar_parts_edges.csv')
      return unless path
      count=write_csv(path,roots)
      message("CSV: #{count} деталей ДСП 18 мм з картою крайок. Імпорт: Плитні матеріали → Деталі → Імпорт із текстового файлу. Фанера та свердління не входять.")
    end

    def export_dxf
      m=Sketchup.active_model
      raise 'Для 3D DXF відкрийте чисту модель TEST.skp: у TECHNICAL_REVIEW є допоміжні осі.' if m.get_attribute('TechnicalReview','legend')
      path=UI.savepanel('3D DXF геометрії — не присадка Viyar',nil,'Furniture_3D_geometry.dxf')
      return unless path
      path+='.dxf' unless path.downcase.end_with?('.dxf')
      ok=write_dxf(path)
      raise 'Експортер SketchUp не створив DXF.' unless ok
      message('3D DXF збережено. Це геометрія збірки; перевірте одиниці та масштаб при імпорті. Операції присадки не передаються цим експортером.')
    end

    # SketchUp's native DXF exporter also exports hidden instances. Remove them
    # in an aborted operation so references/guides do not leak into the DXF.
    def write_dxf(path)
      m=Sketchup.active_model
      raise 'Вийдіть із редагування компонента перед експортом.' if m.active_path
      raise 'Відкрийте чисту TEST.skp без допоміжних осей.' if m.get_attribute('TechnicalReview','legend')
      old_unit=m.options['UnitsOptions']['LengthUnit']
      m.start_operation('ZFT temporary export filtering',true)
      begin
        walk=lambda do |entities|
          instances=entities.grep(Sketchup::Group)+entities.grep(Sketchup::ComponentInstance)
          instances.each do |e|
            next unless e.valid?
            if e.hidden? || !e.layer.visible? || e.layer.name.match?(/REFERENCE_HIDDEN/) ||
               e.get_attribute(Main::ATTRIBUTE,'generated',false) || e.name.start_with?('REVIEW ONLY')
              e.erase!
            else
              walk.call(e.definition.entities)
            end
          end
        end
        walk.call(m.entities)
        m.options['UnitsOptions']['LengthUnit']=2
        m.export(path,acad_version:'acad_2013',faces_flag:true,edges:true,
          construction_geometry:false,dimensions:false,text:false,materials:true,show_summary:false)
      ensure
        m.abort_operation
        m.options['UnitsOptions']['LengthUnit']=old_unit
      end
    end

    def export_coordinates
      m=Sketchup.active_model
      roots=m.selection.grep(Sketchup::Group)+m.selection.grep(Sketchup::ComponentInstance)
      raise 'Виділіть збірку.' if roots.empty?
      holes=Main.leaf_instances(roots).values.flat_map do |e,_parent|
        JSON.parse(e.get_attribute(Main::ATTRIBUTE,'actual_holes_json','[]'))
      end
      return Main.export_mount_guides_csv if holes.empty?
      path=UI.savepanel('Координати на момент свердління — контрольний CSV',nil,'Drilling_coordinates_REVIEW.csv')
      return unless path
      content=CSV.generate(col_sep:';') do |csv|
        csv << %w[status part_name kind x_mm y_mm z_mm dir_x dir_y dir_z diameter_mm depth_mm]
        holes.each { |h| csv << ['AS_DRILLED_NOT_VIYAR_IMPORT',h['part_name'],h['kind'],*h['xyz_mm'],*h['direction'],h['diameter_mm'],h['depth_mm']] }
      end
      File.binwrite(path,"\xEF\xBB\xBF".b+content.encode('UTF-8').b)
      message("#{holes.length} отворів. Координати на момент свердління; після переміщення деталей журнал не оновлюється. Це контрольний файл, не імпорт присадки Viyar.")
    end

    def install
      return if @installed
      menu=UI.menu('Plugins').add_submenu('Zilla Furniture Tools')
      menu.add_item('Панель інструментів') { show }
      menu.add_item('Показати панель кнопок') { @toolbar.show }
      @toolbar=UI::Toolbar.new('Zilla Furniture Tools')
      [['panel','Панель Zilla',nil],['joint','Кріплення вручну','joint'],
       ['drawer','Чотири кути шухляди','drawer'],['xray','X-Ray увімкнути / вимкнути','xray']].each do |icon,label,id|
        cmd=UI::Command.new(label) { id ? run(id) : show }
        cmd.tooltip=label;cmd.status_bar_text=label
        cmd.small_icon=cmd.large_icon=File.join(__dir__,'icons',icon+'.png')
        @toolbar.add_item(cmd)
      end
      @toolbar.restore
      @toolbar.show
      @installed=true
    end
  end
end
