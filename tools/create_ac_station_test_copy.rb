# Run through SketchUp MCP with the saved AC Station OCL draft open.
source = Sketchup.active_model
raise 'Source scene has unsaved edits' if source.modified?
raise 'Unexpected source scene' unless File.basename(source.path) == 'AC_Station_v4_technical_OCL_DRAFT.skp'
path = 'M:/projects/furniture/AC-Station/cad/sketchup/AC_Station_v4_banding_drilling_TEST.skp'
raise 'Test copy exists already' if File.exist?(path)
raise 'Could not save copy' unless source.save_copy(path)
raise 'Could not open test copy' unless Sketchup.open_file(path)
raise 'Wrong active scene after copy' unless Sketchup.active_model.path.tr('\\', '/') == path
