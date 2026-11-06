# Run with load in SketchUp on the AC Station v5 test/review model.
# All temporary metadata/scale changes are rolled back.
module ZillaFurnitureTools
  module DashboardProbe
    extend self
    def run
      m=Sketchup.active_model
      roots=m.entities.grep(Sketchup::Group).reject { |g| g.name.start_with?('REVIEW ONLY') }
      parts=Main.leaf_instances(roots)
      panel=parts.fetch('Drawer_Left').first
      raise 'Expected 15 CSV panels' unless Dashboard.cutting_rows(roots).length==15
      raise 'Recorded drilled stock rejected' unless Main.verified_drilled_stock?(panel)
      m.start_operation('ZFT dashboard probe',true)
      begin
        original=panel.get_attribute(Main::ATTRIBUTE,'actual_holes_json')
        panel.set_attribute(Main::ATTRIBUTE,'actual_holes_json','[]')
        raise 'Unrecorded cut stock accepted' if Main.verified_drilled_stock?(panel)
        panel.set_attribute(Main::ATTRIBUTE,'actual_holes_json',original)
        panel.transformation=panel.transformation*Geom::Transformation.scaling(2,1,1)
        raise 'Scaled drilled stock accepted' if Main.verified_drilled_stock?(panel)
        rejected=false
        begin
          Dashboard.cutting_rows(roots)
        rescue StandardError => e
          rejected=e.message.include?('Масштабована деталь')
        end
        raise 'Scaled stock exported to cutting CSV' unless rejected
      ensure
        m.abort_operation
      end
      raise 'Probe did not restore geometry' unless Main.verified_drilled_stock?(panel)
      'PASS: 15 CSV panels; drilled stock accepted; missing log/scaled stock rejected; model restored'
    end
  end
end
ZillaFurnitureTools::DashboardProbe.run
