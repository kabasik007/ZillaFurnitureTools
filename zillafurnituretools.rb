# frozen_string_literal: true
require 'sketchup.rb'
require 'extensions.rb'

module ZillaFurnitureTools
  unless defined?(EXTENSION)
    EXTENSION = SketchupExtension.new('Zilla Furniture Tools', 'zillafurnituretools/main')
    EXTENSION.creator = 'Zilla Furniture Tools'
    EXTENSION.description = 'Furniture drilling, edge plans and ABF DXF package for ViyarPro review.'
    EXTENSION.version = '0.7.0'
    Sketchup.register_extension(EXTENSION, true)
  end
end
