"""Original aquatic cast, modelled from the three approved concept sheets.

Run with isolated Blender: blender --background --python tools/build_aquatic.py
Units are metres. Blender +Y exports to Godot -Z. Source and QA are ignored by Godot.
"""
import bpy, math, random, os, json, struct
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'models', 'aquatic')
SOURCE = os.path.join(OUT, 'source')
os.makedirs(SOURCE, exist_ok=True)
with open(os.path.join(SOURCE, '.gdignore'), 'w') as f: f.write('')
random.seed(7411)
for obj in list(bpy.data.objects): bpy.data.objects.remove(obj, do_unlink=True)
scene = bpy.context.scene
atlas = bpy.data.images.load(os.path.join(ROOT, 'assets', 'textures', 'style-atlas.png'))
atlas.pack()
materials = []

def material(name, rgb, rough=.78, emission=0, textured=True):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*rgb, 1)
    nodes = mat.node_tree.nodes
    p = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Roughness'].default_value = rough
    if emission:
        p.inputs['Emission Color'].default_value = (*rgb, 1)
        p.inputs['Emission Strength'].default_value = emission
    if textured:
        tex = nodes.new('ShaderNodeTexImage'); tex.image = atlas
        mul = nodes.new('ShaderNodeMixRGB')
        choices = [i.identifier for i in mul.bl_rna.properties['blend_type'].enum_items]
        mul.blend_type = next(v for v in choices if v == 'MULTIPLY')
        mul.inputs[0].default_value = 1
        mul.inputs[2].default_value = (*rgb, 1)
        mat.node_tree.links.new(tex.outputs['Color'], mul.inputs[1])
        mat.node_tree.links.new(mul.outputs['Color'], p.inputs['Base Color'])
    materials.append(mat)
    return len(materials)-1

BLUE = [material('Ocean skin %02d'%i, c) for i,c in enumerate([
    (.025,.24,.39),(.026,.32,.46),(.04,.38,.49),(.015,.20,.34),(.05,.29,.43)])]
MINT = material('Pearl mint ventral skin',(.57,.84,.72))
IVORY = material('Ivory rim and shell',(.96,.88,.62))
PALE = material('Pale filter ridge',(.96,.95,.80))
GOLD = material('Warm pleat shadow',(.59,.38,.11))
AMBER = material('Lantern amber luminous throat',(1,.49,.08),.47,1.3)
AMBER_SHADOW = material('Lantern amber deep fold',(.74,.24,.025),.62,.35)
EYE = material('Glossy midnight eyes',(.006,.023,.035),.12,textured=False)
GLINT = material('Eye glint',(.85,.98,1),.2,.25,False)
TEAL = material('Shell turquoise bands',(.07,.49,.47))
MOSS = material('Salt moss olive',(.31,.42,.11))
SHELL_SHADOW = material('Warm ivory shell shade',(.76,.64,.40))

class Mesh:
    def __init__(self,name):
        self.name=name; self.v=[]; self.f=[]; self.mi=[]; self.uv=[]
    def face(self,points,mat,uv=None):
        start=len(self.v); self.v.extend([tuple(p) for p in points])
        self.f.append(tuple(range(start,start+len(points)))); self.mi.append(mat)
        # Crop the generated ivory cloth quadrant: subtle paint-grain, no wood or masonry seams.
        for i,p in enumerate(points):
            self.uv.append(uv[i] if uv else (.56+(p[0]*.034+p[1]*.023)% .34,.60+(p[2]*.034+p[1]*.017)% .31))
    def object(self):
        data=bpy.data.meshes.new(self.name+' mesh'); data.from_pydata(self.v,[],self.f); data.update()
        obj=bpy.data.objects.new(self.name,data); scene.collection.objects.link(obj)
        for mat in materials: data.materials.append(mat)
        for face,mi in zip(data.polygons,self.mi): face.material_index=mi
        uv=data.uv_layers.new(name='UVMap')
        for loop in data.loops: uv.data[loop.index].uv=self.uv[loop.vertex_index]
        return obj

def ellipsoid(name,center,scale,mat,sides=16,rings=10):
    m=Mesh(name); rows=[]
    for j in range(rings+1):
        lat=-math.pi/2+math.pi*j/rings
        rows.append([Vector(center)+Vector((scale[0]*math.cos(lat)*math.cos(i*math.tau/sides),scale[1]*math.cos(lat)*math.sin(i*math.tau/sides),scale[2]*math.sin(lat))) for i in range(sides)])
    for j in range(rings):
        for i in range(sides): m.face([rows[j][i],rows[j][(i+1)%sides],rows[j+1][(i+1)%sides],rows[j+1][i]],mat)
    return m.object()

def tube(name,points,radii,mat,sides=10,ventral=None):
    m=Mesh(name); rows=[]
    for j,p in enumerate(points):
        p=Vector(p); tangent=Vector(points[min(j+1,len(points)-1)])-Vector(points[max(j-1,0)])
        tangent.normalize(); side=tangent.cross(Vector((0,0,1)))
        if side.length<.05: side=tangent.cross(Vector((0,1,0)))
        side.normalize(); up=tangent.cross(side).normalized()
        rows.append([p+radii[j]*(side*math.cos(i*math.tau/sides)+up*math.sin(i*math.tau/sides)) for i in range(sides)])
    for j in range(len(points)-1):
        for i in range(sides):
            mid=(rows[j][i]+rows[j][(i+1)%sides])*.5
            use=ventral if ventral is not None and mid.z<Vector(points[j]).z-radii[j]*.35 else mat
            m.face([rows[j][i],rows[j][(i+1)%sides],rows[j+1][(i+1)%sides],rows[j+1][i]],use)
    m.face(list(reversed(rows[0])),mat); m.face(rows[-1],mat)
    return m.object()

def body(name,profiles,sides=24):
    m=Mesh(name); rows=[]
    for y,rx,rz,z in profiles:
        rows.append([Vector((rx*math.cos(i*math.tau/sides),y,z+rz*math.sin(i*math.tau/sides))) for i in range(sides)])
    for j in range(len(rows)-1):
        for i in range(sides):
            a=(i+.5)*math.tau/sides
            mat=MINT if math.sin(a)<-.20+random.uniform(-.18,.18) else random.choice(BLUE)
            m.face([rows[j][i],rows[j][(i+1)%sides],rows[j+1][(i+1)%sides],rows[j+1][i]],mat)
    m.face(list(reversed(rows[0])),BLUE[0]);m.face(rows[-1],BLUE[0])
    return m.object()

def petal(name,root,tip,width,arch=.15,side=1):
    m=Mesh(name); rows=[]; n=12
    root=Vector(root); tip=Vector(tip)
    for i in range(n+1):
        t=i/n; center=root.lerp(tip,t)+Vector((0,0,arch*math.sin(math.pi*t)))
        w=max(.014,width*math.sin(math.pi*t)**.8)
        rows.append([center+Vector((0,w*q,.05*(1-abs(q))*math.sin(math.pi*t))) for q in [-1,-.85,-.35,.35,.85,1]])
    for i in range(n):
        for j in range(5):
            p=[rows[i][j],rows[i+1][j],rows[i+1][j+1],rows[i][j+1]]
            if side<0:p.reverse()
            m.face(p,IVORY if j in [0,4] else BLUE[(i//3+j)%len(BLUE)])
            m.face([v-Vector((0,0,.035)) for v in reversed(p)],MINT)
    return m.object()

def eye_pair(parts,x,y,z,r):
    for sign in [-1,1]:
        parts.append(ellipsoid('Ivory eye socket', (sign*x,y,z),(r*1.23,r*.72,r*1.17),IVORY))
        parts.append(ellipsoid('Midnight eye', (sign*x,y+r*.50,z),(r,r*.43,r),EYE))
        parts.append(ellipsoid('Eye catchlight',(sign*x-r*.25,y+r*.89,z+r*.32),(r*.22,r*.10,r*.22),GLINT,8,6))

def ribbonwake():
    parts=[]
    parts.append(body('Ribbonwake tapered body',[(1.08,.22,.17,.12),(.82,.46,.25,.08),(.4,.54,.29,.04),(0,.45,.25,0),(-.5,.26,.17,-.02),(-.86,.065,.055,0)]))
    for sign in [-1,1]:
        parts.append(petal('Front petal '+str(sign),(sign*.37,.47,.05),(sign*2.08,.08,.65),.60,.25,sign))
        parts.append(petal('Rear petal '+str(sign),(sign*.25,-.37,-.03),(sign*1.38,-1.28,-.26),.46,.12,sign))
    m=Mesh('Ivory pleated feeding fan')
    center=Vector((0,1.07,.06))
    for i in range(24):
        a=i*math.pi/24;b=(i+1)*math.pi/24
        p=Vector((.53*math.cos(a),1.05+(.035 if i%2 else -.01),.07-.64*math.sin(a)))
        q=Vector((.53*math.cos(b),1.05+(.035 if (i+1)%2 else -.01),.07-.64*math.sin(b)))
        m.face([center,p,q],PALE if i%2 else IVORY)
        m.face([p,q,q+Vector((0,-.1,0)),p+Vector((0,-.1,0))],GOLD)
    parts.append(m.object())
    pts=[]; radii=[]
    for i in range(27):
        t=i/26
        pts.append((.40*t*t*math.sin(t*3),-.8-1.9*t,.02+.82*t**3))
        radii.append(.066*(1-t)+.016)
    parts.append(tube('Long curled ribbon tail',pts,radii,BLUE[1],8,IVORY))
    # A broader distal ribbon makes the silhouette readable at swimming distance.
    parts.append(petal('Ribbon tail vane',pts[14],pts[-1],.08,.05))
    eye_pair(parts,.38,.86,.17,.125)
    return parts

def lanternjaw():
    parts=[body('Lanternjaw long seal body',[(1.63,.24,.19,.09),(1.37,.39,.34,.08),(.98,.48,.40,.04),(.40,.57,.46,.02),(-.2,.51,.40,0),(-.78,.36,.30,.01),(-1.30,.13,.18,.05),(-1.61,.055,.08,.08)])]
    for sign in [-1,1]:
        parts.append(petal('Pectoral flipper '+str(sign),(sign*.39,.38,-.09),(sign*1.09,-.31,-.69),.25,.03,sign))
    # Vertical tail and restrained dorsal sail, closed on both sides.
    m=Mesh('Tail fin and dorsal ridge')
    for verts in [[(-.04,-1.44,.08),(-.04,-2.16,.63),(-.04,-1.96,.04),(-.04,-2.25,-.5),(-.04,-1.47,-.08)], [(-.04,.41,.43),(-.04,-.01,.84),(-.04,-.60,.35)]]:
        m.face(verts,BLUE[1]);m.face([(v[0]+.08,v[1],v[2]) for v in reversed(verts)],BLUE[3])
        for i in range(len(verts)):
            a=verts[i];b=verts[(i+1)%len(verts)];m.face([a,b,(b[0]+.08,b[1],b[2]),(a[0]+.08,a[1],a[2])],MINT)
    parts.append(m.object())
    parts.append(ellipsoid('Inflatable amber throat', (0,1.01,-.34),(.42,.54,.52),AMBER,24,14))
    # Long raised folds follow the curved pouch from jaw to breast.
    for i in range(11):
        theta=-1.36+2.72*i/10
        pts=[]
        for j in range(12):
            t=j/11
            yy=1.525-1.035*t
            width=math.sqrt(max(0,1-((yy-1.01)/.54)**2))
            pts.append((math.sin(theta)*.434*width,yy,-.34-.537*math.cos(theta)*width))
        parts.append(tube('Throat pleat %02d'%i,pts,[.014]*len(pts),AMBER_SHADOW if i%2 else GOLD,6))
    # Subtle lip line and nostrils; no generic tooth-filled monster mouth.
    parts.append(tube('Closed blunt jaw line',[(-.26,1.59,.04),(0,1.68,.015),(.26,1.59,.04)],[.016]*3,BLUE[3],6))
    eye_pair(parts,.35,1.36,.23,.086)
    return parts

def sucker(name,center,normal,radius):
    center=Vector(center); n=Vector(normal).normalized(); side=n.cross(Vector((0,1,0)))
    if side.length<.1:side=n.cross(Vector((1,0,0)))
    side.normalize(); up=n.cross(side); m=Mesh(name); rings=[]
    for rr,depth in [(radius,0),(radius*.73,radius*.3),(radius*.43,radius*.18)]:
        rings.append([center+side*rr*math.cos(i*math.tau/8)+up*rr*math.sin(i*math.tau/8)+n*depth for i in range(8)])
    for j in range(2):
        for i in range(8):m.face([rings[j][i],rings[j][(i+1)%8],rings[j+1][(i+1)%8],rings[j+1][i]],IVORY if j else MINT)
    m.face(rings[-1],BLUE[3]);return m.object()

def tidebell():
    parts=[];m=Mesh('Tidebell ivory spiral shell');sides=48;levels=34;rows=[]
    for j in range(levels+1):
        t=j/levels; z=.32+6.65*t
        r=4.62*(1-t)**.83+.07
        row=[]
        for i in range(sides):
            a=i*math.tau/sides
            noise=1+.018*math.sin(i*1.7+j*.74)+.012*math.cos(i*3.1)
            row.append(Vector((r*math.cos(a)*noise,r*math.sin(a)*noise,z+.085*math.sin(i*1.31+j*.73))))
        rows.append(row)
    for j in range(levels):
        for i in range(sides):
            stripe=(j/levels*6.65+(i/sides)*1.30)%1.65
            mat=TEAL if stripe<.24 and j>2 else (SHELL_SHADOW if random.random()<.12 else IVORY)
            m.face([rows[j][i],rows[j][(i+1)%sides],rows[j+1][(i+1)%sides],rows[j+1][i]],mat)
    m.face(rows[-1],IVORY);parts.append(m.object())
    m=Mesh('Golden pleated mantle skirt')
    for i in range(72):
        a=i*math.tau/72;b=(i+1)*math.tau/72
        r1=4.55 if i%2 else 4.34;r2=4.55 if (i+1)%2 else 4.34
        m.face([(4.50*math.cos(a),4.50*math.sin(a),.36),(4.50*math.cos(b),4.50*math.sin(b),.36),(r2*math.cos(b),r2*math.sin(b),-.60-.14*math.cos(b*6)),(r1*math.cos(a),r1*math.sin(a),-.60-.14*math.cos(a*6))],IVORY if i%2 else GOLD)
    parts.append(m.object())
    for arm in range(6):
        angle=math.tau*arm/6+math.pi/6
        radial=Vector((math.cos(angle),math.sin(angle),0));tangent=Vector((-radial.y,radial.x,0))
        pts=[];radii=[]
        for j in range(20):
            t=j/19;rr=2.85+4.05*math.sin(t*math.pi*.55)
            zz=-.53-4.3*math.sin(t*math.pi*.64)+.7*t*t
            pts.append(radial*rr+tangent*(.65*math.sin(t*math.pi*1.6))+Vector((0,0,zz)))
            radii.append(.77*(1-t)**.78+.07)
        parts.append(tube('Arm_%02d_heavy_curled'%(arm+1),pts,radii,BLUE[arm%5],12,MINT))
        for j in range(3,18,2):
            for sign in [-1,1]:
                normal=(tangent*sign*.38+Vector((0,0,-1))).normalized()
                p=pts[j]+normal*radii[j]*.88
                parts.append(sucker('Arm_%02d_sucker_%02d_%d'%(arm+1,j,sign),p,normal,max(.07,radii[j]*.32)))
    eye_pair(parts,1.27,4.39,-.20,.49)
    # Asymmetric salt encrustations break the perfect rotational shell silhouette.
    for i in range(18):
        a=i*2.399+.35;z=.8+(i%6)*.74;r=4.62*(1-(z-.32)/6.65)**.83
        p=(math.cos(a)*r,math.sin(a)*r,z)
        normal=Vector((math.cos(a),math.sin(a),.5)).normalized()
        parts.append(sucker('Shell barnacle %02d'%i,p,normal,.13+.05*(i%3)))
        if i%3==0: parts.append(ellipsoid('Salt moss clump %02d'%i,Vector(p)+normal*.04,(.33,.30,.16),MOSS,9,5))
    return parts

ASSETS={}
manifest={'authorship':'Original scripted Blender geometry from approved concept sheets; generated style-atlas texture reused with cropped UVs. No external models.', 'units':'metres', 'forward':'Godot -Z', 'assets':{}}
def retain_pbr_palette(path):
    # Blender 5.2's exporter preserves the texture behind MixRGB but omits its
    # constant multiply factor. Encode that factor in standard glTF PBR directly.
    # This changes material metadata only, never the generated bitmap.
    with open(path,'rb') as f: raw=f.read()
    length=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+length])
    palette={m.name:list(m.diffuse_color) for m in materials}
    for mat in doc.get('materials',[]):
        mat.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=palette[mat['name']]
    textures=doc.get('textures',[])
    if textures and all(t==textures[0] for t in textures):
        doc['textures']=[textures[0]]
        for mat in doc['materials']:
            texture=mat['pbrMetallicRoughness'].get('baseColorTexture')
            if texture: texture['index']=0
    encoded=json.dumps(doc,separators=(',',':')).encode('utf8')
    encoded+=b' '*((-len(encoded))%4)
    rest=raw[20+length:]
    output=struct.pack('<4sII',b'glTF',2,20+len(encoded)+len(rest))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+rest
    with open(path,'wb') as f:f.write(output)

for name,builder in [('ribbonwake',ribbonwake),('lanternjaw',lanternjaw),('tidebell',tidebell)]:
    parts=builder();ASSETS[name]=parts
    for obj in bpy.context.selected_objects:obj.select_set(False)
    # One exported mesh per species, with material surfaces; retain named anatomical
    # components in the packed source. Hundreds of per-sucker draw nodes are unnecessary.
    export_parts=[]
    for obj in parts:
        copy=obj.copy();copy.data=obj.data.copy();scene.collection.objects.link(copy)
        copy.select_set(True);export_parts.append(copy)
    bpy.context.view_layer.objects.active=export_parts[0]
    bpy.ops.object.join();combined=bpy.context.object;combined.name=name
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,name+'.glb'),use_selection=True,export_apply=True)
    retain_pbr_palette(os.path.join(OUT,name+'.glb'))
    bpy.data.objects.remove(combined,do_unlink=True)
    coords=[obj.matrix_world@Vector(v) for obj in parts for v in obj.bound_box]
    bounds=[[min(v[i] for v in coords) for i in range(3)],[max(v[i] for v in coords) for i in range(3)]]
    manifest['assets'][name]={'file':name+'.glb','mesh_objects':1,'source_components':len(parts),'polygons':sum(len(o.data.polygons) for o in parts),'blender_bounds':bounds,'origin':'mantle waterline' if name=='tidebell' else 'body center'}
    for obj in parts:obj.hide_render=True;obj.hide_set(True)
    print('AQUATIC_EXPORTED',name,manifest['assets'][name])

# Keep packed source and actual multi-angle model renders alongside the models, ignored by the engine.
world=bpy.data.worlds.new('Aquatic QA teal');scene.world=world;world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.037,.080,.10,1);bg.inputs['Strength'].default_value=.65
def area(name,loc,energy,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size
    ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=loc
    ob.rotation_euler=(Vector((0,0,0))-ob.location).to_track_quat('-Z','Y').to_euler()
area('Soft warm key',(10,10,18),2300,9);area('Cool rim',(-8,-9,12),2700,7);area('Front fill',(-7,12,3),950,8)
camera_data=bpy.data.cameras.new('QA Camera');camera=bpy.data.objects.new('QA Camera',camera_data);scene.collection.objects.link(camera);scene.camera=camera
camera_data.type=next(e.identifier for e in camera_data.bl_rna.properties['type'].enum_items if e.identifier=='ORTHO')
scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.render.image_settings.file_format=next(e.identifier for e in scene.render.image_settings.bl_rna.properties['file_format'].enum_items if e.identifier=='PNG')
for name,parts in ASSETS.items():
    for obj in parts:obj.hide_render=False;obj.hide_set(False)
    large=name=='tidebell'; scale=21.0 if large else (5.2 if name=='ribbonwake' else 4.8)
    target=Vector((0,0,1.2 if large else -.10))
    for angle,unit in [('three_quarter',(1.05,1.6,.90)),('side',(1.6,.1,.30)),('top',(.02,.1,2.0))]:
        camera.location=target+Vector(unit)*(15 if large else 5)
        camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera_data.ortho_scale=scale
        scene.render.filepath=os.path.join(SOURCE,name+'-'+angle+'.png')
        bpy.ops.render.render(write_still=True)
    for obj in parts:obj.hide_render=True;obj.hide_set(True)
with open(os.path.join(OUT,'manifest.json'),'w') as f:json.dump(manifest,f,indent=2)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE,'aquatic-cast.blend'))
print('AQUATIC_BUILD_COMPLETE')
