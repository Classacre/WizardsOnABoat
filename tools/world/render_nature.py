import bpy,os,math
from mathutils import Vector
root=os.path.abspath(os.path.join(os.path.dirname(__file__),'../..'))
bpy.ops.wm.open_mainfile(filepath=os.path.join(root,'tools/world/nature-kit.blend'))
for obj in bpy.context.scene.objects:
    obj.hide_render=True
for name,loc in [('wind_tree',(-5,0,0)),('mangrove',(1,0,0)),('coastal_crag_0',(6,0,0)),('kelp_fan',(-1,5,0))]:
    obj=bpy.data.objects.get(name)
    obj.hide_set(False);obj.hide_render=False;obj.location=loc
scene=bpy.context.scene
camera=bpy.data.objects.get('Camera')
camera.location=(12,-22,12)
camera.rotation_euler=(Vector((0,1,2))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type=next(i.identifier for i in camera.data.bl_rna.properties['type'].enum_items if i.identifier=='ORTHO')
camera.data.ortho_scale=19
scene.camera=camera
light=bpy.data.objects.get('Light');light.hide_render=False;light.location=(0,-6,10);light.data.energy=1800
world=scene.world;world.use_nodes=True
background=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs['Color'].default_value=(.53,.69,.75,1);background.inputs['Strength'].default_value=.75
scene.render.resolution_x=1200;scene.render.resolution_y=640;scene.render.resolution_percentage=100
scene.render.filepath=os.path.join(root,'.dream-loop/nature-qa.png')
bpy.ops.render.render(write_still=True)
