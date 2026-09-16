"""Author low-memory, reusable stylized environmental meshes in isolated Blender.

Run: blender --background --python tools/world/build_nature.py
Original assets; every exported file contains only this script's selected objects.
"""
import bpy, math, random, os
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../..'))
OUT = os.path.join(ROOT,'assets/models/nature')
os.makedirs(OUT, exist_ok=True)
random.seed(1988)
collection = bpy.data.collections.new('WOAB_Nature_Original')
bpy.context.scene.collection.children.link(collection)

atlas_path = os.path.join(ROOT,'assets/textures/nature-atlas.png')
has_nature = os.path.exists(atlas_path)
if not has_nature:
    atlas_path = os.path.join(ROOT,'assets/textures/style-atlas.png')
atlas = bpy.data.images.load(atlas_path, check_existing=True)
atlas.pack()
material = bpy.data.materials.new('Painted Nature Atlas')
material.use_nodes = True
principled = next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
principled.inputs['Roughness'].default_value = .89
tex = material.node_tree.nodes.new('ShaderNodeTexImage')
tex.image = atlas
color = material.node_tree.nodes.new('ShaderNodeVertexColor')
color.layer_name = 'Col'
multiply = material.node_tree.nodes.new('ShaderNodeMixRGB')
valid_blends = [item.identifier for item in multiply.bl_rna.properties['blend_type'].enum_items]
multiply.blend_type = next(value for value in valid_blends if value=='MULTIPLY')
multiply.inputs[0].default_value = 1.0
material.node_tree.links.new(tex.outputs['Color'], multiply.inputs[1])
material.node_tree.links.new(color.outputs['Color'], multiply.inputs[2])
material.node_tree.links.new(multiply.outputs['Color'], principled.inputs['Base Color'])

class MeshAuthor:
    def __init__(self):
        self.vertices=[]; self.faces=[]; self.colors=[]; self.uvs=[]
    def face(self, points, color=(1,1,1,1), kind='leaf'):
        start=len(self.vertices)
        self.vertices.extend(points)
        self.faces.append(tuple(range(start,start+len(points))))
        # Generated atlas quadrants; preserve painterly detail over geometry.
        if has_nature:
            base={'bark':(0,.5),'leaf':(.5,.5),'rock':(0,0),'kelp':(.5,0)}[kind]
        else:
            base={'bark':(0,.5),'leaf':(.5,.5),'rock':(0,0),'kelp':(.5,.5)}[kind]
        for i,p in enumerate(points):
            self.colors.append(color)
            self.uvs.append((base[0]+.06+(p[0]*.14+p[1]*.07)%0.37,base[1]+.06+(p[2]*.16+p[0]*.03)%0.37))
    def branch(self,a,b,r1,r2,color,kind='bark',sides=7):
        a,b=Vector(a),Vector(b)
        axis=(b-a).normalized()
        tangent=axis.cross(Vector((0,1,0))).normalized()
        if tangent.length<.01: tangent=Vector((1,0,0))
        bitangent=axis.cross(tangent).normalized()
        rings=[]
        for center,radius in [(a,r1),(b,r2)]:
            rings.append([center+radius*(math.cos(i*math.tau/sides)*tangent+math.sin(i*math.tau/sides)*bitangent) for i in range(sides)])
        for i in range(sides):
            j=(i+1)%sides
            shade=1.0+(i%3-1)*.07
            c=tuple(min(1,v*shade) for v in color[:3])+(1,)
            self.face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],c,kind)
        self.face(rings[1],color,kind)
    def crown(self,center,scale,color):
        # Sculpted irregular polygon lobes with horizontal windswept silhouette.
        center=Vector(center)
        count=9
        ring=[]
        for i in range(count):
            a=i*math.tau/count
            r=random.uniform(.78,1.12)
            ring.append(center+Vector((math.cos(a)*scale[0]*r,math.sin(a)*scale[1]*r,random.uniform(-.1,.17)*scale[2])))
        top=center+Vector((-.18,0,scale[2]))
        bottom=center-Vector((0,0,scale[2]*.45))
        for i in range(count):
            c=tuple(min(1,v*random.uniform(.87,1.14)) for v in color[:3])+(1,)
            self.face([ring[i],ring[(i+1)%count],top],c)
            self.face([ring[(i+1)%count],ring[i],bottom],tuple(v*.70 for v in c[:3])+(1,))
    def export(self,name):
        mesh=bpy.data.meshes.new(name+'Mesh')
        mesh.from_pydata(self.vertices,[],self.faces)
        mesh.update()
        obj=bpy.data.objects.new(name,mesh)
        collection.objects.link(obj)
        obj.data.materials.append(material)
        uv=mesh.uv_layers.new(name='UVMap')
        attrs=mesh.color_attributes
        enum_type=[i.identifier for i in attrs.bl_rna.functions['new'].parameters['type'].enum_items]
        enum_domain=[i.identifier for i in attrs.bl_rna.functions['new'].parameters['domain'].enum_items]
        col=attrs.new(name='Col',type=next(v for v in enum_type if v=='BYTE_COLOR'),domain=next(v for v in enum_domain if v=='CORNER'))
        for loop in mesh.loops:
            uv.data[loop.index].uv=self.uvs[loop.vertex_index]
            col.data[loop.index].color=self.colors[loop.vertex_index]
        for other in bpy.context.selected_objects:
            other.select_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active=obj
        # Blender's own registered exporter default determines the format.
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,name+'.glb'),use_selection=True,export_apply=True)
        obj.hide_set(True)
        print('NATURE_ASSET',name,len(mesh.polygons),'faces')

def tree(mangrove=False):
    m=MeshAuthor(); bark=(.52,.41,.27,1)
    joints=[(0,0,0),(.10,0,1.35),(.34,.06,2.6),(.66,.02,3.85),(1.12,.03,4.6)]
    for i in range(len(joints)-1):m.branch(joints[i],joints[i+1],.35-i*.06,.29-i*.057,bark)
    for i in range(7 if mangrove else 4):
        a=i*math.tau/(7 if mangrove else 4)
        root=(math.cos(a)*(1.4 if mangrove else .8),math.sin(a)*(1.4 if mangrove else .8),-.15)
        m.branch(root,joints[1] if mangrove else joints[0],.12,.22,bark)
    for i in range(11):
        a=i*2.399
        z=2.4+(i%4)*.45
        end=(math.cos(a)*1.7+.6,math.sin(a)*1.3,z+1.0)
        m.branch((.3,0,z),end,.16,.045,bark)
        for j in range(4):
            center=(end[0]+random.uniform(-.6,.6),end[1]+random.uniform(-.6,.6),end[2]+random.uniform(-.15,.45))
            m.crown(center,(random.uniform(.65,1.05),random.uniform(.55,.9),random.uniform(.22,.42)),(.42,.64,.21,1) if not mangrove else (.24,.48,.22,1))
    m.export('mangrove' if mangrove else 'wind_tree')
tree();tree(True)

for variant in range(3):
    m=MeshAuthor()
    n=7
    rings=[]
    for level in range(3):
        ring=[]
        for i in range(n):
            a=i*math.tau/n
            radius=random.uniform(.8,1.15)*(1.0 if level<2 else .70)
            ring.append((math.cos(a)*radius,math.sin(a)*radius,(-.3,1.0,2.4)[level]+random.uniform(-.2,.2)))
        rings.append(ring)
    for level in range(2):
        for i in range(n):
            j=(i+1)%n
            c=(random.uniform(.6,.83),random.uniform(.64,.83),random.uniform(.66,.80),1)
            m.face([rings[level][i],rings[level][j],rings[level+1][j]],c,'rock')
            m.face([rings[level][i],rings[level+1][j],rings[level+1][i]],c,'rock')
    for i in range(n):
        m.face([rings[2][i],rings[2][(i+1)%n],(.10,0,2.6)],(.57,.66,.32,1) if variant==0 else (.80,.81,.73,1),'rock')
    m.export('coastal_crag_%d'%variant)

m=MeshAuthor()
for stalk in range(6):
    a=stalk*math.tau/6
    x,y=math.cos(a)*.32,math.sin(a)*.32
    m.branch((x,y,0),(x+.6,y,4.1),.07,.025,(.30,.47,.16,1),'kelp',5)
    for level in range(6):
        z=.5+level*.53
        direction=1 if level%2 else -1
        length=random.uniform(.7,1.45)
        origin=Vector((x+z*.15,y,z))
        tip=origin+Vector((direction*length,.12,length*.25))
        middle=origin.lerp(tip,.6)+Vector((0,.25,0))
        m.face([origin,middle,tip,middle-Vector((0,.48,0))],(.38,.56,.19,1),'kelp')
m.export('kelp_fan')

m=MeshAuthor()
for i in range(20):
    a=i*2.4
    base=(math.cos(a)*.5,math.sin(a)*.5,0)
    end=(base[0]*1.6,base[1]*1.6,random.uniform(.35,1.1))
    m.branch(base,end,.13,.035,(.69,.47,.24,1),'rock',5)
m.export('amber_coral')

m=MeshAuthor()
for i in range(18):
    a=i*2.4
    base=Vector((math.cos(a)*.4,math.sin(a)*.4,0))
    height=random.uniform(.65,1.5)
    side=Vector((math.cos(a)*.09,math.sin(a)*.09,0))
    bend=Vector((math.cos(a+.8)*.25,math.sin(a+.8)*.25,height*.68))
    tip=base+Vector((math.cos(a+.8)*.55,math.sin(a+.8)*.55,height))
    m.face([base-side,base+side,base+bend+side],(.30,.59,.28,1),'kelp')
    m.face([base-side,base+bend+side,base+bend-side],(.30,.59,.28,1),'kelp')
    m.face([base+bend-side,base+bend+side,tip],(.41,.65,.31,1),'kelp')
m.export('shoal_seagrass')

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'tools/world/nature-kit.blend'))
print('NATURE_EXPORT_COMPLETE')
