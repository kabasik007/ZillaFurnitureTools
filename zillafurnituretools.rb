# frozen_string_literal: true
require 'sketchup.rb'
require 'extensions.rb'

module ZillaFurnitureTools
  unless defined?(EXTENSION)
    EXTENSION = SketchupExtension.new('Zilla Furniture Tools', 'zillafurnituretools/main')
    EXTENSION.creator = 'Zilla Furniture Tools'
    EXTENSION.description = 'Furniture panel scanning, confirmat drilling guides, edge-banding and CSV plans.'
    EXTENSION.version = '0.1.0'
    Sketchup.register_extension(EXTENSION, true)
  end
end