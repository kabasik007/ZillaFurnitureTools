# frozen_string_literal: true
module ZillaFurnitureTools
  module PartInventory
    extend self
    # One record per instance, preserving nested transforms and repeated definitions.
    def records(roots)
      result=[]
      walk=lambda do |instance,parent,path|
        return if instance.hidden? || !instance.layer.visible? || instance.get_attribute('ZillaFurnitureTools','generated',false)
        transform=parent*instance.transformation
        id=path+[instance.persistent_id]
        children=instance.definition.entities.grep(Sketchup::Group)+instance.definition.entities.grep(Sketchup::ComponentInstance)
        if children.empty?
          b=instance.definition.bounds
          a=transform.to_a
          raise "Invalid transform for #{instance.name}" if a[15].abs<1.0e-10
          axes=[0,4,8].map { |i| a[i,3].map { |v| v.to_f/a[15] } }
          lengths=axes.map { |v| Math.sqrt(v.sum { |x| x*x }) }
          result << {instance:instance,path:id.join('/'),transform:transform,
            local_dimensions_mm:[b.width,b.height,b.depth].map { |v| v.to_f*25.4 },
            axis_lengths:lengths,mirrored:(axes[0][0]*(axes[1][1]*axes[2][2]-axes[1][2]*axes[2][1])-axes[0][1]*(axes[1][0]*axes[2][2]-axes[1][2]*axes[2][0])+axes[0][2]*(axes[1][0]*axes[2][1]-axes[1][1]*axes[2][0]))<0,
            rigid:lengths.all? { |v| (v-1).abs<0.00001 } &&
              axes.combination(2).all? { |u,v| (0..2).sum { |i| u[i]*v[i] }.abs<0.00001 }}
        else
          children.each { |child| walk.call(child,transform,id) }
        end
      end
      roots.each { |root| walk.call(root,Geom::Transformation.new,[]) }
      result
    end
  end
end
