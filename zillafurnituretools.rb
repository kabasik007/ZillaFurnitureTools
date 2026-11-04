# frozen_string_literal: true
require 'sketchup.rb'
require 'extensions.rb'

module ZillaFurnitureTools
  unless defined?(EXTENSION)
    EXTENSION = SketchupExtension.new('Zilla Furniture Tools', 'zillafurnituretools/main')
    EXTENSION.creator = 'Zilla Furniture Tools'
    EXTENSION.description = 'Manual Smart Joint, confirmat/dowel drill guides, edge candidates and CSV plans.'
    EXTENSION.version = '0.2.0'
    Sketchup.register_extension(EXTENSION, true)
  end
end