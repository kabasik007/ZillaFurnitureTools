# frozen_string_literal: true
require 'sketchup.rb'
require 'extensions.rb'

module ZillaFurnitureTools
  unless defined?(EXTENSION)
    EXTENSION = SketchupExtension.new('Zilla Furniture Tools', 'zillafurnituretools/main')
    EXTENSION.creator = 'Zilla Furniture Tools'
    EXTENSION.description = 'Manual joint, drawer front and runner mounting guides, edge candidates and CSV plans.'
    EXTENSION.version = '0.6.0'
    Sketchup.register_extension(EXTENSION, true)
  end
end
