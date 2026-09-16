"""Original Spellwake assets. Run with Blender --background --python tools/build_assets.py.

All design coordinates are Godot metres (Y up, forward -Z). Blender's glTF
export converts the internal Z-up geometry back to that convention. The build
uses a new scene and never removes objects from an existing Blender document.
Generated style-atlas.png is required; no substitute texture is generated.
"""
import bpy, bmesh, math, random, json, sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models'
OUT.mkdir(parents=True, exist_ok=True)
ATLAS = ROOT / 'assets/textures/style-atlas.png'
random.seed(9247)
SCENE = bpy.data.scenes.new('Spellwake_Asset_Workshop')
if bpy.context.window:
    bpy.context.window.scene = SCENE
COL = SCENE.collection
MATS = {}
PARTS = []
RECORDS = []

def g(p): return (p[0], -p[2], p[1])

def material(name, color, quadrant=None, metallic=0, emission=0, tint=None):
    m=bpy.data.materials.new('SW_'+name)
    m.diffuse_color=(*color,1)
    m.use_nodes=True
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=.8 if not metallic else .36
    bs.inputs['Metallic'].default_value=metallic
    if emission:
        bs.inputs['Emission Color'].default_value=(*color,1)
        bs.inputs['Emission Strength'].default_value=emission
    if quadrant is not None:
        if not ATLAS.exists(): raise RuntimeError('Missing generated texture: '+str(ATLAS))
        tex=m.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image=bpy.data.images.load(str(ATLAS),check_existing=True)
        if tint:
            mix=m.node_tree.nodes.new('ShaderNodeMix')
            mix.data_type=next(i.identifier for i in mix.bl_rna.properties['data_type'].enum_items if i.identifier=='RGBA')
            mix.blend_type=next(i.identifier for i in mix.bl_rna.properties['blend_type'].enum_items if i.identifier=='MULTIPLY')
            inputs=[s for s in mix.inputs if s.type=='RGBA']
            factor=next(s for s in mix.inputs if s.name=='Factor' and s.type=='VALUE')
            factor.default_value=1.0
            inputs[1].default_value=(*tint,1)
            m.node_tree.links.new(tex.outputs['Color'],inputs[0])
            m.node_tree.links.new(next(s for s in mix.outputs if s.type=='RGBA'),bs.inputs['Base Color'])
        else:
            m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
        m['atlas_quadrant']=quadrant
    m['original_design']='Wizards on a Boat; approved preproduction art'
    MATS[name]=m
    return m

def materials():
    material('wood',(.54,.28,.105),0)
    material('sail',(.94,.84,.61),1)
    material('stone',(.7,.65,.48),2)
    material('teal',(.04,.29,.34),3,tint=(.62,1,.52))
    material('cloth',(.04,.29,.34),1,tint=(.035,.22,.29))['uv_rect']=(.79,.58,.11,.26)
    material('cloth_green',(.08,.24,.13),1,tint=(.10,.26,.15))['uv_rect']=(.79,.58,.11,.26)
    material('cloth_rust',(.47,.14,.055),1,tint=(.56,.14,.047))['uv_rect']=(.79,.58,.11,.26)
    material('cloth_navy',(.03,.09,.17),1,tint=(.035,.08,.16))['uv_rect']=(.79,.58,.11,.26)
    material('carapace',(.76,.68,.48),2)['uv_rect']=(.025,.423,.17,.065)
    material('navy',(.045,.10,.18))
    material('brass',(.65,.40,.12),metallic=.68)
    material('rope',(.48,.34,.16))
    material('darkwood',(.18,.082,.035))
    material('skin',(.53,.27,.13))
    material('cream',(.90,.78,.53))
    material('black',(.018,.024,.027))
    material('white',(.91,.90,.77))
    material('red',(.59,.185,.055))
    material('red_light',(.68,.225,.070))
    material('red_dark',(.49,.132,.035))
    material('crystal',(.05,.65,.79),metallic=.28,emission=.35)
    material('lamp',(.98,.64,.15),emission=2.6)
    material('leaf',(.24,.38,.035))
    material('leaf_light',(.44,.55,.065))
    material('blue',(.035,.20,.39))

def uv_project(obj, mat):
    mesh=obj.data
    uv=mesh.uv_layers.new(name='UVMap')
    q=mat.get('atlas_quadrant',None)
    # PNG quadrants: TL timber, TR canvas, BL stone, BR teal fabric.
    ox=.025 if q in (None,0,2) else .525
    oy=.525 if q in (0,1) else .025
    sx=sy=.45
    if mat.get('uv_rect') is not None:ox,oy,sx,sy=mat['uv_rect']
    for poly in mesh.polygons:
        axis=max(range(3),key=lambda i:abs(poly.normal[i]))
        axes=[i for i in range(3) if i!=axis]
        coords=[mesh.vertices[mesh.loops[li].vertex_index].co for li in poly.loop_indices]
        lo=[min(v[a] for v in coords) for a in axes]
        hi=[max(v[a] for v in coords) for a in axes]
        for li,v in zip(poly.loop_indices,coords):
            u=(v[axes[0]]-lo[0])/max(hi[0]-lo[0],.001)
            vv=(v[axes[1]]-lo[1])/max(hi[1]-lo[1],.001)
            uv.data[li].uv=(ox+u*sx,oy+vv*sy)

def mapped_uv(obj,coords,rect=None):
    mat=obj.data.materials[0];q=mat.get('atlas_quadrant',None)
    if rect is None:
        rect=mat.get('uv_rect',(.025 if q in (None,0,2) else .525,.525 if q in (0,1) else .025,.45,.45))
    ox,oy,sx,sy=rect
    for p in obj.data.polygons:
        for li in p.loop_indices:
            u,v=coords[obj.data.loops[li].vertex_index];obj.data.uv_layers.active.data[li].uv=(ox+u*sx,oy+v*sy)

def mesh(name,vs,fs,mat='wood',smooth=False):
    data=bpy.data.meshes.new(name)
    data.from_pydata([g(v) for v in vs],[],fs)
    data.update()
    bm=bmesh.new();bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    obj=bpy.data.objects.new(name,data); COL.objects.link(obj)
    obj.data.materials.append(MATS[mat]);uv_project(obj,MATS[mat])
    for p in data.polygons:p.use_smooth=smooth
    PARTS.append(obj)
    return obj

def box(name,c,size,mat='wood',bevel=0):
    x,y,z=c; a,b,d=(v/2 for v in size)
    vs=[(x+sx*a,y+sy*b,z+sz*d) for sx,sy,sz in [(-1,-1,-1),(1,-1,-1),(1,-1,1),(-1,-1,1),(-1,1,-1),(1,1,-1),(1,1,1),(-1,1,1)]]
    o=mesh(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)
    if bevel:
        mod=o.modifiers.new('soft hand-cut corners','BEVEL');mod.width=bevel;mod.segments=1
        bpy.context.view_layer.objects.active=o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

def tube(name,points,radii,mat='wood',sides=10):
    vs=[]
    for i,p in enumerate(points):
        tangent=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        tangent.normalize(); up=Vector((0,1,0))
        if abs(tangent.dot(up))>.94:up=Vector((1,0,0))
        u=tangent.cross(up).normalized();v=tangent.cross(u).normalized()
        r=radii[i] if hasattr(radii,'__len__') else radii
        for j in range(sides):
            pt=Vector(p)+r*(u*math.cos(j*math.tau/sides)+v*math.sin(j*math.tau/sides));vs.append(tuple(pt))
    fs=[]
    for i in range(len(points)-1):
        for j in range(sides):fs.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    fs += [tuple(range(sides-1,-1,-1)),tuple((len(points)-1)*sides+j for j in range(sides))]
    obj=mesh(name,vs,fs,mat)
    mapped_uv(obj,[(j/sides,i/max(1,len(points)-1)) for i in range(len(points)) for j in range(sides)])
    return obj

def cylinder(name,c,r,h,mat='wood',sides=14,r2=None):
    x,y,z=c;return tube(name,[(x,y-h/2,z),(x,y+h/2,z)],[r,r if r2 is None else r2],mat,sides)

def lathe(name,rows,c=(0,0,0),mat='wood',sides=20):
    vs=[];fs=[]
    for y,r in rows:
        for j in range(sides):vs.append((c[0]+r*math.cos(j*math.tau/sides),c[1]+y,c[2]+r*math.sin(j*math.tau/sides)))
    for i in range(len(rows)-1):
        for j in range(sides):fs.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    fs.extend([tuple(range(sides-1,-1,-1)),tuple((len(rows)-1)*sides+j for j in range(sides))])
    obj=mesh(name,vs,fs,mat)
    mapped_uv(obj,[(j/sides,i/max(1,len(rows)-1)) for i in range(len(rows)) for j in range(sides)])
    return obj

def sphere(name,c,size,mat='stone',rings=7,sides=12):
    vs=[];fs=[]
    for i in range(rings+1):
        t=math.pi*i/rings
        for j in range(sides):
            a=math.tau*j/sides;vs.append((c[0]+size[0]*math.sin(t)*math.cos(a),c[1]+size[1]*math.cos(t),c[2]+size[2]*math.sin(t)*math.sin(a)))
    for i in range(rings):
        for j in range(sides):fs.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    obj=mesh(name,vs,fs,mat)
    mapped_uv(obj,[(j/sides,i/rings) for i in range(rings+1) for j in range(sides)])
    return obj

def ring(name,c,r,thickness,mat='brass',plane='xz',n=24):
    pts=[]
    for j in range(n+1):
        a=j*math.tau/n
        offset=(r*math.cos(a),0,r*math.sin(a)) if plane=='xz' else ((r*math.cos(a),r*math.sin(a),0) if plane=='xy' else (0,r*math.sin(a),r*math.cos(a)))
        pts.append(tuple(c[k]+offset[k] for k in range(3)))
    return tube(name,pts,thickness,mat,6)

def rope(name,a,b,sag=.15,r=.022):
    pts=[]
    for j in range(13):
        t=j/12;pts.append((a[0]*(1-t)+b[0]*t,a[1]*(1-t)+b[1]*t-sag*math.sin(t*math.pi),a[2]*(1-t)+b[2]*t))
    return tube(name,pts,r,'rope',6)

def lantern(c,s=1):
    x,y,z=c
    cylinder('Lantern foot',(x,y-.23*s,z),.18*s,.08*s,'brass',6)
    cylinder('Warm lantern glass',(x,y,z),.125*s,.4*s,'lamp',6)
    cylinder('Lantern roof',(x,y+.27*s,z),.23*s,.18*s,'brass',6,r2=.055*s)
    for j in range(4):
        a=j*math.pi/2;xx=x+math.cos(a)*.14*s;zz=z+math.sin(a)*.14*s
        tube('Lantern frame',[(xx,y-.23*s,zz),(xx,y+.21*s,zz)],.018*s,'darkwood',5)
    ring('Lantern hook',(x,y+.46*s,z),.08*s,.018*s,'brass','xy',12)

def barrel(c,scale=1):
    x,y,z=c
    lathe('Barrel staves',[(0,.32*scale),(.12*scale,.39*scale),(.52*scale,.43*scale),(.93*scale,.35*scale)],c,'wood',14)
    for yy,rr in [(.10,.385),(.73,.385),(.91,.35)]:ring('Barrel iron hoops',(x,y+yy*scale,z),rr*scale,.035*scale,'navy')
    cylinder('Barrel lid',(x,y+.938*scale,z),.333*scale,.026*scale,'wood',14)

def crystal(c,s=1):
    x,y,z=c
    return lathe('Faceted aether crystal',[(-.34*s,.10*s),(-.10*s,.25*s),(.26*s,.19*s),(.53*s,0)],c,'crystal',6)

def focus(c,s=1):
    x,y,z=c
    cylinder('Focus pedestal',(x,y+.30*s,z),.20*s,.60*s,'wood',10,r2=.13*s)
    cylinder('Focus brass foot',(x,y+.05*s,z),.29*s,.10*s,'brass',10)
    crystal((x,y+.87*s,z),s*.74)
    ring('Armillary outer',(x,y+.88*s,z),.37*s,.03*s,'brass','xy')
    ring('Armillary horizon',(x,y+.88*s,z),.32*s,.025*s,'brass','xz')

def export_asset(name):
    """Consolidate by material: bounded draw calls, retained detailed geometry."""
    global PARTS
    asset_objects=list(PARTS)
    groups={mat.name:[o for o in asset_objects if o.type=='MESH' and o.data.materials and o.data.materials[0]==mat] for mat in MATS.values()}
    bpy.ops.object.select_all(action='DESELECT')
    merged=[]
    for mat in MATS.values():
        objs=groups[mat.name]
        if not objs:continue
        for o in objs:o.select_set(True)
        bpy.context.view_layer.objects.active=objs[0]
        bpy.ops.object.join()
        obj=bpy.context.object;obj.name=name+'_'+mat.name
        merged.append(obj)
        bpy.ops.object.select_all(action='DESELECT')
    for o in merged:o.select_set(True)
    bpy.context.view_layer.objects.active=merged[0]
    props=bpy.ops.export_scene.gltf.get_rna_type().properties
    fmts=[i.identifier for i in props['export_format'].enum_items]
    if not fmts:
        import io_scene_gltf2
        fmts=[i[0] for i in io_scene_gltf2.get_format_items(SCENE,bpy.context)]
    fmt=next(v for v in fmts if v=='GLB')
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format=fmt,use_selection=True,use_active_scene=True,export_apply=True,export_yup=True,export_cameras=False,export_lights=False)
    verts=sum(len(o.data.vertices) for o in merged)
    tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in merged)
    points=[o.matrix_world@v.co for o in merged for v in o.data.vertices]
    lo=[min(p[i] for p in points) for i in range(3)]; hi=[max(p[i] for p in points) for i in range(3)]
    RECORDS.append({'asset':name+'.glb','vertices':verts,'triangles':tris,'materials':len(merged),'godot_bounds_min':[lo[0],lo[2],-hi[1]],'godot_bounds_max':[hi[0],hi[2],-lo[1]]})
    for o in merged:o.hide_set(True);o.hide_render=True;o.select_set(False)
    PARTS=[]

def boat():
    # Cross sections follow the hand-built hull, narrowing into a high bow.
    zs=[-7,-6.5,-5.5,-4,-2,0,2,4,5.7,6.6]
    widths=[.04,.75,1.45,2.02,2.35,2.5,2.45,2.3,2.03,1.75]
    def width(z):
        for i in range(len(zs)-1):
            if z<=zs[i+1]:
                t=(z-zs[i])/(zs[i+1]-zs[i]);return widths[i]*(1-t)+widths[i+1]*t
        return widths[-1]
    n=38
    for side in [-1,1]:
        for row in range(6):
            vs=[]
            for j in range(n+1):
                z=-7+j*13.6/n
                rise=.52*(abs(z)/7)**3
                for h in [row/6+.005,(row+1)/6-.005]:
                    y=-1.22+h*2.42+rise
                    x=side*width(z)*(.24+.76*math.sin(h*math.pi/2))
                    vs.append((x,y,z))
            fs=[(j*2,j*2+1,j*2+3,j*2+2) for j in range(n)]
            plank=mesh('Curved individual hull strake',vs,fs,'wood')
            mapped_uv(plank,[(h,j/n) for j in range(n+1) for h in (0,1)],(.033+row*.066,.525,.055,.45))
        for yy,rr,mt in [(1.20,.15,'teal'),(.78,.08,'teal'),(-.75,.065,'darkwood')]:
            tube('Sweeping gunwale',[(side*width(-7+j*13.6/n),yy+.52*(abs(-7+j*13.6/n)/7)**3,-7+j*13.6/n) for j in range(n+1)],rr,mt,8)
        for z in [-5.2,-3,-.8,1.6,4,6]:
            x=side*width(z)
            tube('Gunwale ribs',[(x*.87,-.05,z),(x,1.32,z)],.082,'darkwood',6)
            for y in [.44,.87]:sphere('Hull rivet',(x*1.005,y,z),(.055,.055,.055),'brass',4,6)
    mesh('Transom',[(-1.75,-.62,6.6),(1.75,-.62,6.6),(1.75,1.64,6.6),(-1.75,1.64,6.6)],[(0,1,2,3)],'wood')
    keel=[]
    for j in range(n+1):
        z=-7+j*13.6/n;y=-1.22+.52*(abs(z)/7)**3;w=width(z)*.24
        keel.extend([(-w,y,z),(w,y,z)])
    mesh('Closed curved keel',keel,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(n)],'darkwood')
    # Deck is made of narrow, visibly separated planks with a continuous playable plane.
    for k in range(23):
        a=-1+k*2/23+.003;b=-1+(k+1)*2/23-.003
        vs=[]
        for j in range(n+1):
            z=-6.77+j*13.24/n;w=width(z)*.97
            vs.extend([(a*w,1.10,z),(b*w,1.10,z)])
        plank=mesh('Deck plank',vs,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(n)],'wood')
        mapped_uv(plank,[(h,j/n) for j in range(n+1) for h in (0,1)],(.035+(k%6)*.07,.525,.050,.45))
    tube('Carved bow stem',[(0,-1,-6.8),(0,1.5,-7),(0,2.15,-7.8),(0,2.30,-8.05)],[.20,.19,.14,.08],'wood',10)
    lantern((0,1.75,-8.05),1.15)
    # Small open stern cabin with trim, portholes and canvas shelter.
    box('Stern cabin',(0,1.93,4.75),(2.9,1.65,2.15),'wood',.06)
    for x in [-1.5,1.5]:
        tube('Cabin roof side',[(x,2.84,3.54),(x,2.84,5.94)],.12,'teal')
        ring('Cabin brass porthole',(x,2.12,4.95),.29,.055,'brass','yz')
        sphere('Cabin dark window',(x*1.002,2.12,4.95),(.012,.235,.235),'navy')
        tube('Cabin porthole cross',[(x*1.01,1.87,4.95),(x*1.01,2.37,4.95)],.023,'brass')
    for x in [-1.4,1.4]:
        for z in [3.65,5.85]:cylinder('Quarterdeck shelter post',(x,3.18,z),.075,.76,'wood',8)
    mesh('Aft cream canopy',[(-1.55,3.48,3.5),(0,3.32,3.5),(1.55,3.48,3.5),(-1.55,3.48,6),(0,3.32,6),(1.55,3.48,6)],[(0,1,4,3),(1,2,5,4)],'sail')
    # A helm visible above the cabin; usable helm marker is provided by game scene.
    cylinder('Helm pedestal',(0,3.18,3.75),.16,.60,'wood',10)
    ring('Helm wheel',(0,3.56,3.50),.55,.065,'wood','xy')
    for j in range(8):
        a=math.tau*j/8;tube('Helm spoke',[(0,3.56,3.50),(.68*math.cos(a),3.56+.68*math.sin(a),3.50)],.035,'wood',8)
    sphere('Helm hub',(0,3.56,3.48),(.12,.12,.08),'brass')
    # Primary mast and yard. Large sail remains a separate export for deformation.
    tube('Main mast',[(0,1.1,.1),(0,8.4,.1),(0,10.1,.2)],[.23,.14,.06],'wood',12)
    tube('Upper yard',[(-3.3,8.9,0),(3.3,8.9,0)],[.105,.105],'wood',10)
    tube('Lower yard',[(-3.05,3.25,-.25),(3.05,3.25,-.25)],[.085,.085],'wood',10)
    for y in [1.25,2,4,6.8,8.9]:
        for off in [0,.07,.14]:ring('Mast rope wrapping',(0,y+off,.1),.23-(y/10)*.08,.025,'rope','xz',16)
    for side in [-1,1]:
        rope('Main standing rigging',(side*2.33,1.36,1.5),(side*.04,8.8,.1),.1,.035)
        rope('Yard sheet',(side*3.22,8.9,0),(side*2.0,1.3,-4.8),.1,.028)
        rope('Bow stay',(0,9.2,.1),(0,1.95,-7.7),.14,.035)
    # Climbable-looking rope ladder, high contrast at sailing distance.
    for side in [-1,1]:rope('Ratline side',(side*.52,1.4,.7),(side*.24,8.45,.35),0,.021)
    for j in range(15):
        y=1.65+j*.43;w=.52-(y-1.4)/7.05*.28;z=.7-(y-1.4)/7.05*.35
        tube('Ratline rung',[(-w,y,z),(w,y,z)],.020,'rope',5)
    mesh('Mast pennant',[(0,9.9,.17),(1.9,9.82,.36),(1.48,9.42,.08),(2.0,9.12,-.1),(0,9.45,.17)],[(0,1,2,3,4)],'teal')
    for x,z in [(-1.78,-2.75),(1.78,-2.75),(-1.83,2.7)]:focus((x,1.14,z),.85)
    barrel((1.67,1.13,1.7),.90);barrel((-1.25,1.13,4),.80)
    box('Spell worktable',(1.72,1.65,.2),(1.13,.14,1.35),'wood',.04)
    for x in [1.27,2.17]:
        for z in [-.3,.7]:box('Table leg',(x,1.38,z),(.10,.56,.10),'wood')
    box('Open book dark cover',(1.70,1.76,.15),(.76,.08,.55),'darkwood',.02)
    box('Open book pages',(1.70,1.81,.15),(.68,.035,.49),'sail',.01)
    for z in [2.83,6.15]:lantern((1.44,2.65,z),.78)
    export_asset('boat')
    # Cloth grid in the horizontal yard plane, bellowing toward the bow (-Z).
    vs=[]; fs=[];nx=24;ny=24
    for iy in range(ny+1):
        t=iy/ny;y=3.26+t*5.58;hw=3.04+.10*math.sin(t*math.pi)
        for ix in range(nx+1):
            u=ix/nx;xx=(u*2-1)*hw
            zz=-.22-1.20*math.sin(math.pi*u)*math.sin(math.pi*t)
            vs.append((xx,y+.12*math.sin(math.pi*u)*(1-t),zz))
    for iy in range(ny):
        for ix in range(nx):
            a=iy*(nx+1)+ix;fs.append((a,a+1,a+nx+2,a+nx+1))
    cloth=mesh('Wind receiving sail',vs,fs,'sail',True)
    uv=cloth.data.uv_layers.active
    for p in cloth.data.polygons:
        for li in p.loop_indices:
            v=cloth.data.loops[li].vertex_index;u=(v%(nx+1))/nx;t=(v//(nx+1))/ny
            uv.data[li].uv=(.53+u*.44,.53+t*.44)
    # Spiral crest geometry follows the exact billowed sail surface.
    crest=[]
    for j in range(101):
        t=j/100;ang=t*math.pi*4.2;r=.08+t*1.25
        x=r*math.cos(ang);y=5.85+r*math.sin(ang)
        dx=1.25*math.cos(ang)-r*math.sin(ang)*math.pi*4.2
        dy=1.25*math.sin(ang)+r*math.cos(ang)*math.pi*4.2
        length=math.hypot(dx,dy);w=.024+.074*t
        for side in [-1,1]:
            xx=x+side*(-dy/length)*w;yy=y+side*(dx/length)*w
            h=(yy-3.26)/5.58;u=(xx/(3.04+.10*math.sin(h*math.pi))+1)/2
            h=(yy-3.26-.12*math.sin(u*math.pi))/(5.58-.12*math.sin(u*math.pi))
            zz=-.22-1.20*math.sin(math.pi*u)*math.sin(math.pi*h)-.035
            crest.append((xx,yy,zz))
    mesh('Painted spiral sail crest',crest,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(100)],'blue')
    for x in [-3.03,3.03]:tube('Canvas edge seam',[(x,3.3,-.22),(x,8.82,-.22)],.025,'rope',6)
    export_asset('boat_sail')

def staff(c=(0,0,0),scale=1):
    x,y,z=c;s=scale
    pts=[(x+.025*math.sin(j*1.8)*s,y+j*.17*s,z+.025*math.cos(j*1.3)*s) for j in range(10)]
    tube('Twisted driftwood staff',pts,[.047*s-.018*s*j/9 for j in range(10)],'wood',7)
    tube('Crystal cradle left',[(x,y+1.35*s,z),(x-.15*s,y+1.52*s,z),(x-.16*s,y+1.78*s,z),(x-.04*s,y+1.9*s,z)],[.05*s,.047*s,.034*s,.015*s],'wood',7)
    tube('Crystal cradle right',[(x,y+1.36*s,z),(x+.13*s,y+1.58*s,z),(x+.1*s,y+1.79*s,z)],[.05*s,.033*s,.015*s],'wood',7)
    crystal((x,y+1.62*s,z),.48*s)
    for j in range(6):ring('Staff rope binding',(x,y+(1.31+j*.032)*s,z),.066*s,.013*s,'rope','xz',12)
    sphere('Staff seashell charm',(x+.08*s,y+1.25*s,z-.04*s),(.065*s,.09*s,.023*s),'cream',5,6)

def wizard(merchant=False,variant='wizard',pose='idle'):
    # Silhouette and costume follow the approved sailor turnaround.
    wide=1.24 if merchant else 1.0
    skin='skin';hair='white' if merchant or pose=='helm' else 'darkwood';coat='navy' if merchant else 'cloth_green' if variant=='wizard_green' else 'cloth_rust' if variant=='wizard_rust' else 'cloth_navy' if pose=='helm' else 'cloth'
    for side in [-1,1]:
        x=side*.15*wide
        sphere('Hand sewn boot',(x,.13,-.06),(.14,.15,.24),'darkwood',6,10)
        cylinder('Boot cuff',(x,.29,0),.122,.1,'wood',10)
        tube('Trouser leg',[(x,.29,0),(x,.52,.015),(x,.84,.035)],[.10,.14,.135],'navy',10)
        ring('Boot ankle strap',(x,.21,0),.137,.022,'brass','xz',12)
    lathe('Cream linen shirt',[(.78,.24*wide),(1.04,.22*wide),(1.28,.245*wide),(1.36,.14*wide)],(0,0,0),'sail',12)
    # Open coat panels, shirt and belt read from the front rather than a solid robe.
    for side in [-1,1]:
        vs=[(side*.055,1.33,-.18),(side*.29*wide,1.32,-.12),(side*.35*wide,.68,-.13),(side*.06,.70,-.21),
            (side*.29*wide,1.32,.10),(side*.35*wide,.67,.13),(side*.03,.70,.23),(side*.03,1.28,.20)]
        mesh('Flared coat panel',vs,[(0,1,2,3),(1,4,5,2),(4,7,6,5)],coat)
        tube('Cream coat piping',[(side*.055,1.33,-.182),(side*.05,.98,-.23),(side*.06,.70,-.215),(side*.35*wide,.68,-.14)],.014,'cream',5)
        shoulder=(side*.27*wide,1.26,.005);elbow=(side*.37*wide,1.03,-.005);wrist=(side*.40*wide,.82,-.07)
        tube('Coat sleeve',[shoulder,elbow],[.14,.115],coat,10)
        tube('Rolled cream cuff',[(side*.37*wide,1.06,-.005),(side*.385*wide,.96,-.02)],[.12,.123],'sail',10)
        tube('Forearm',[(side*.38*wide,.96,-.02),wrist],[.075,.056],skin,10)
        sphere('Hand',(side*.41*wide,.78,-.075),(.071,.10,.056),skin,6,8)
        sphere('Thumb',(side*.37*wide,.79,-.115),(.027,.057,.028),skin,5,6)
        for j in range(3):
            tube('Fingers',[(side*(.385+.019*j)*wide,.78,-.095),(side*(.388+.019*j)*wide,.708,-.10)],[.015,.012],skin,5)
    ring('Rope belt',(0,.95,0),.265*wide,.026,'rope','xz',20)
    for i in range(2):ring('Belt knot',(.065,.94,-.268*wide),.055+i*.014,.018,'rope','xy',12)
    tube('Belt rope tails',[(.06,.91,-.28),(.11,.78,-.30),(.07,.70,-.29)],.018,'rope')
    # Collar triangles and brass closures.
    for side in [-1,1]:
        mesh('Pointed shirt collar',[(side*.08,1.4,-.12),(side*.23,1.3,-.19),(side*.08,1.25,-.215)],[(0,1,2)],'sail')
        for y in [1.16,1.05,.85]:sphere('Coat brass button',(side*.11,y,-.224),(.019,.019,.011),'brass',4,6)
    cylinder('Neck',(0,1.405,0),.083,.17,skin,10)
    sphere('Head',(0,1.575,-.015),(.19,.225,.16),skin,10,16)
    for side in [-1,1]:
        sphere('Ear',(side*.187,1.58,.005),(.042,.062,.041),skin,6,8)
        sphere('Eye white',(side*.071,1.615,-.16),(.037,.025,.014),'white',6,10)
        sphere('Dark pupil',(side*.071,1.614,-.175),(.018,.020,.009),'black',6,8)
        sphere('Eye gleam',(side*.066,1.625,-.187),(.006,.007,.004),'white',4,6)
        tube('Eyebrow',[(side*.035,1.675,-.165),(side*.072,1.687,-.17),(side*.109,1.675,-.157)],.010,hair,5)
    sphere('Nose',(0,1.57,-.176),(.033,.048,.039),skin,6,8)
    tube('Smile',[(-.046,1.495,-.151),(0,1.48,-.169),(.046,1.495,-.151)],.008,'darkwood',5)
    # Individual curl clusters establish a soft, welcoming face silhouette.
    for j in range(13):
        a=j*math.tau/13
        sphere('Hair curl',(math.cos(a)*.17,1.66+.035*math.sin(a*3),.02+math.sin(a)*.14),(.070,.085,.066),hair,5,8)
    for side in [-1,1]:
        for y in [1.58,1.49]:sphere('Side curl',(side*.185,y,.045),(.07,.065,.075),hair,5,8)
    # Wind-bent hat, asymmetric rim, gold fabric band.
    vs=[];N=24
    for radius in [.16,.36 if merchant else .44]:
        for j in range(N):
            a=j*math.tau/N
            vs.append((math.cos(a)*radius,1.765+.025*math.sin(2*a)+.03*math.cos(a),math.sin(a)*radius*.88+.02))
    hatmat=coat if variant in ('wizard_green','wizard_rust') or merchant else 'navy'
    mesh('Sweeping wizard hat brim',vs,[(j,(j+1)%N,N+(j+1)%N,N+j) for j in range(N)],hatmat)
    tube('Bent pointed wizard hat',[(0,1.77,.02),(.015,1.91,.035),(-.02,2.08,.05),(-.12,2.22,.04),(-.25,2.17,.045),(-.29,2.08,.06)],[.21,.16,.10,.057,.025,.003],hatmat,14)
    lathe('Golden hatband',[(1.815,.199),(1.87,.174)],(0,0,.02),'brass',14)
    if merchant:
        # Merchant apron, round glasses, silver hair and keys.
        box('Golden apron',(0,1.055,-.239),(.49,.58,.035),'wood',.025)
        box('Apron lower pocket',(0,.87,-.27),(.35,.16,.024),'wood',.01)
        for side in [-1,1]:ring('Round spectacles',(side*.082,1.605,-.185),.065,.009,'brass','xy',18)
        tube('Spectacle bridge',[(-.022,1.61,-.19),(.022,1.61,-.19)],.008,'brass',5)
        for j in range(3):
            x=.26+j*.027;tube('Harbour keys',[(x,.95,-.22),(x,.81-j*.018,-.24)],.014,'brass',5)
            ring('Key loop',(x,.96,-.22),.027,.009,'brass','xy',10)
        export_asset('shopkeeper')
    else:
        box('Spellbook worn leather cover',(.32,.86,.09),(.105,.30,.23),'darkwood',.022)
        box('Spellbook pages',(.321,.86,.077),(.11,.255,.18),'sail',.01)
        ring('Belt compass',(-.20,.84,-.22),.065,.013,'brass','xy',16)
        cylinder('Shoulder satchel button',(.32,1.03,.09),.03,.03,'brass',8)
        # Readable compass embroidery and wave piping on the coat's back.
        ring('Back embroidered compass',(0,1.18,.224),.108,.009,'cream','xy',16)
        for j in range(8):
            a=j*math.tau/8;r=.15 if j%2==0 else .125
            tube('Back compass ray',[(0,1.18,.225),(r*math.cos(a),1.18+r*math.sin(a),.225)],.006,'cream',5)
        if pose!='idle':
            arm_names=('Coat sleeve','Rolled cream cuff','Forearm','Hand','Thumb','Fingers')
            for o in PARTS:
                if o.name.split('.')[0] not in arm_names:continue
                cx=sum(v.co.x for v in o.data.vertices)/len(o.data.vertices)
                if pose=='cast' and cx>0:continue
                pivot=Vector(((-.27 if cx<0 else .27)*wide,1.26,0))
                for v in o.data.vertices:
                    p=Vector((v.co.x,v.co.z,-v.co.y))-pivot
                    if pose=='cast':
                        a=math.radians(-140);p=Vector((p.x*math.cos(a)-p.y*math.sin(a),p.x*math.sin(a)+p.y*math.cos(a),p.z))
                    elif pose=='helm':
                        a=math.radians(62);p=Vector((p.x,p.y*math.cos(a)-p.z*math.sin(a),p.y*math.sin(a)+p.z*math.cos(a)))
                    v.co=g(p+pivot)
        if pose!='helm':staff((-.45,.97 if pose=='cast' else .07,-.16),.92)
        export_asset(variant)

def lighthouse():
    # Separate trapezoid stones make the silhouette read as hand-built masonry.
    for row in range(20):
        y=row*.53;r=2.15-y*.067;N=16
        for j in range(N):
            a=(j+(row%2)*.5)*math.tau/N+.012;b=a+math.tau/N-.026
            vs=[]
            for yy,rr in [(y,r),(y+.51,r-.035)]:
                for aa in [a,b]:vs.extend([(math.cos(aa)*rr,yy,math.sin(aa)*rr),(math.cos(aa)*(rr-.30),yy,math.sin(aa)*(rr-.30))])
            mesh('Hand-cut lighthouse masonry',vs,[(0,2,6,4),(1,5,7,3),(0,4,5,1),(2,3,7,6),(4,6,7,5)],'stone')
    for yy in [.15,3.4,7.3,10.6]:cylinder('Stone cornice',(0,yy,0),2.19-yy*.063,.19,'stone',24)
    # Front arched door and stone voussoirs.
    box('Lighthouse door',(0,1.20,-2.11),(1.13,2.4,.08),'wood',.06)
    sphere('Door arched upper',(0,2.32,-2.02),(.57,.52,.08),'wood',8,12)
    for j in range(9):
        a=j*math.pi/8
        box('Door arch block',(.70*math.cos(a),2.29+.70*math.sin(a),-2.14),(.28,.28,.32),'stone',.035)
    for x in [-.7,.7]:box('Door stone jamb',(x,1.18,-2.14),(.28,2.25,.32),'stone',.025)
    ring('Door handle',(.29,1.14,-2.19),.08,.02,'brass','xy',12)
    for y,z,r in [(4.75,-1.83,.27),(7.85,-1.6,.27)]:
        box('Deep lighthouse window',(0,y,z),(r*2,1.05,.05),'navy',.10)
        box('Window lintel',(0,y+.58,z-.015),(.72,.15,.19),'stone',.025)
        box('Window sill',(0,y-.59,z-.08),(.72,.14,.31),'stone',.025)
    cylinder('Lantern gallery platform',(0,10.65,0),2.02,.26,'wood',24)
    for j in range(16):
        a=j*math.tau/16;x=1.92*math.cos(a);z=1.92*math.sin(a)
        cylinder('Gallery railing baluster',(x,11.13,z),.049,.79,'darkwood',6)
    for yy in [10.93,11.53]:ring('Gallery circular rail',(0,yy,0),1.93,.065,'wood','xz',32)
    cylinder('Lantern chamber bottom',(0,10.91,0),1.41,.26,'stone',20)
    cylinder('Luminous lighthouse lens',(0,11.85,0),.49,1.30,'lamp',12)
    for j in range(8):
        a=j*math.tau/8
        cylinder('Lantern window frame',(1.25*math.cos(a),11.84,1.25*math.sin(a)),.072,1.85,'teal',8)
    for yy in [11.04,12.67]:ring('Lantern metal lintel',(0,yy,0),1.29,.092,'teal','xz',24)
    cylinder('Copper lighthouse roof',(0,13.25,0),1.75,1.20,'red',16,r2=.07)
    cylinder('Copper roof lip',(0,12.7,0),1.79,.13,'red',16)
    tube('Roof finial',[(0,13.8,0),(0,14.35,0)],[.085,.012],'brass',8)
    sphere('Finial ball',(0,14.12,0),(.105,.105,.105),'brass',6,10)
    lantern((.96,2.05,-2.25),1.1)
    export_asset('lighthouse')

def bottle(c,color='crystal',s=1):
    lathe('Potion bottle',[(0,.11*s),(.07*s,.14*s),(.31*s,.12*s),(.39*s,.049*s),(.50*s,.043*s)],c,color,10)
    cylinder('Bottle cork',(c[0],c[1]+.51*s,c[2]),.052*s,.055*s,'wood',8)

def shop():
    # Chunky coastal shop, coral tile roof, exposed timbers and open counter.
    box('Shop masonry',(0,2.25,0),(7.2,4.5,5.8),'stone',.09)
    for y in [.22,.9,1.6,2.3,3,3.7,4.4]:
        for x in [-3.64,3.64]:box('Shop corner quoins',(x,y,-2.90),(.44,.48,.42),'stone',.04)
    for x in [-3.7,3.7]:
        box('Corner timber',(x,2.25,-2.97),(.21,4.5,.20),'wood',.03)
        box('Side wall timber',(x,2.25,2.91),(.20,4.5,.20),'wood',.03)
    box('Front timber beam',(0,3.6,-3.03),(7.5,.25,.22),'wood',.02)
    mesh('Front gable',[(-3.6,4.5,-2.91),(3.6,4.5,-2.91),(0,6.52,-2.91)],[(0,1,2)],'stone')
    mesh('Rear gable',[(-3.6,4.5,2.91),(3.6,4.5,2.91),(0,6.52,2.91)],[(0,1,2)],'stone')
    for side in [-1,1]:
        tube('Gable framing',[(side*3.7,4.5,-3.01),(0,6.6,-3.01)],.12,'wood',6)
        mesh('Roof underlay',[(0,6.58,-3.33),(side*4.05,4.45,-3.33),(side*4.05,4.45,3.33),(0,6.58,3.33)],[(0,1,2,3)],'darkwood')
        # Raised terracotta tiles follow a shallow roof curvature.
        for row in range(9):
            xa=.05+row*.445;xb=xa+.47
            ya=6.58-xa*.51+.07*math.sin(xa);yb=6.58-xb*.51+.07*math.sin(xb)
            for j in range(13):
                z=-3.33+j*.51;vs=[]
                for xx,yy in [(xa,ya),(xb,yb)]:
                    for k in range(5):
                        t=k/4;vs.append((side*xx,yy+.075*math.sin(t*math.pi)+(.038 if xx==xb else 0),z+t*.50))
                mesh('Individual terracotta roof tile',vs,[(k,k+1,k+6,k+5) for k in range(4)],['red','red_light','red','red_dark','red'][((j*3+row*7)%5)])
    for j in range(14):tube('Roof ridge cap',[(0,6.61,-3.30+j*.50),(0,6.61,-2.82+j*.50)],[.18,.18],'red',10)
    box('Stone chimney',(2.25,6.25,1.4),(.81,3.1,.87),'stone',.035)
    box('Chimney crown',(2.25,7.85,1.4),(1.08,.24,1.13),'stone',.05)
    box('Dark chimney mouth',(2.25,7.99,1.4),(.62,.035,.64),'black')
    # Recessed shopfront, shelves visible from plaza.
    box('Shopfront recess',(.30,2.2,-2.95),(4.50,2.65,.04),'darkwood',.03)
    for yy in [1.00,1.83,2.66]:box('Display shelf',(.30,yy,-3.19),(4.50,.13,.65),'wood',.025)
    for j in range(9):
        for row in range(2):bottle((-1.45+j*.45,1.12+row*.83,-3.24),['crystal','blue','red','leaf'][j%4],.8+.1*(j%3))
    box('Counter front',(.3,.73,-3.33),(4.75,1.13,.14),'wood',.025)
    box('Counter top',(.3,1.37,-3.40),(4.93,.18,.95),'wood',.035)
    for x in [-2.18,2.78]:box('Counter sidepost',(x,2.20,-3.28),(.18,2.95,.18),'wood',.02)
    # Canvas striped awning, frame and dangling sign.
    for j in range(10):
        xa=-2.43+j*.55;xb=xa+.54
        mesh('Striped shop awning',[(xa,3.67,-3.04),(xb,3.67,-3.04),(xb,3.31,-4.56),(xa,3.31,-4.56),(xa,3.03,-4.56),(xb,3.03,-4.56)],[(0,1,2,3),(3,2,5,4)],'teal' if j%2==0 else 'sail')
    for x in [-2.43,3.07]:
        cylinder('Awning timber post',(x,1.62,-4.5),.085,3.24,'wood',8)
        tube('Awning arm',[(x,3.72,-3.01),(x,3.29,-4.63)],.07,'wood',8)
    box('Shop door',(-2.94,1.38,-3.04),(.92,2.70,.10),'wood',.06)
    ring('Shop door pull',(-2.67,1.4,-3.12),.066,.016,'brass','xy',12)
    sphere('Gable round window',(0,5.3,-2.965),(.46,.46,.055),'navy',10,16)
    ring('Gable window frame',(0,5.3,-3.02),.47,.07,'wood','xy',20)
    tube('Window vertical mullion',[(0,4.86,-3.06),(0,5.74,-3.06)],.034,'wood',6)
    tube('Window horizontal mullion',[(-.44,5.3,-3.06),(.44,5.3,-3.06)],.034,'wood',6)
    lantern((-3.43,2.61,-3.35),1.25)
    box('Hanging harbour shop sign',(3.83,3.34,-3.35),(1.15,1.24,.13),'teal',.07)
    ring('Golden shop compass crest',(3.83,3.34,-3.43),.35,.025,'brass','xy')
    for j in range(4):
        a=j*math.pi/2;tube('Sign compass point',[(3.83,3.34,-3.43),(3.83+.45*math.cos(a),3.34+.45*math.sin(a),-3.43)],.023,'brass')
    barrel((-3.90,0,-2.0),1.15)
    box('Shipping crate',(3.83,.46,-1.95),(.94,.92,.94),'wood',.035)
    for x in [3.45,4.21]:box('Crate brace',(x,.46,-2.44),(.10,.90,.05),'darkwood')
    export_asset('shop')

def dock():
    for j in range(25):box('Pier deck plank',(0,.24,-4+j*.33),(4.2,.22,.30),'wood',.024)
    for x in [-1.72,1.72]:
        box('Pier bearer',(x,.04,0),(.27,.31,8.3),'darkwood')
        for z in [-3.65,0,3.65]:
            cylinder('Pier piling',(x,-.66,z),.15,3.00,'wood',8)
            cylinder('Pier piling cap',(x,.93,z),.20,.14,'stone',8)
            for y in [.52,.59,.66]:ring('Pier rope binding',(x,y,z),.164,.030,'rope','xz',12)
        for za,zb in [(-3.65,0),(0,3.65)]:rope('Pier safety rope',(x,.73,za),(x,.73,zb),.22,.035)
    cylinder('Harbour lantern post',(-1.72,2.05,-3.65),.11,2.6,'wood',8)
    tube('Pier lantern bracket',[(-1.72,3.21,-3.65),(-.90,3.21,-3.65)],.075,'wood',8)
    lantern((-.92,2.73,-3.65),1.12)
    export_asset('dock')

def crab():
    sphere('Kettleback body',(0,.49,0),(.67,.32,.54),'blue',8,14)
    # Dome shell with a flared plate edge.
    lathe('Kettleback ceramic shell',[(.56,.69),(.65,.73),(.83,.64),(1.01,.37),(1.06,.06)],(0,0,0),'carapace',16)
    for x in [-.25,.25]:
        tube('Kettleback chimney vent',[(x,.93,.13),(x*1.15,1.22,.19)],[.135,.115],'carapace',10)
        cylinder('Vent dark opening',(x*1.15,1.229,.19),.084,.016,'darkwood',10)
        ring('Vent rim',(x*1.15,1.23,.19),.107,.028,'cream','xz',12)
    for side in [-1,1]:
        for j in range(4):
            z=-.33+j*.23
            root=(side*.52,.56,z);elbow=(side*(.84+.08*math.sin(j)),.61,z+.05);foot=(side*1.03,.035,z+.16)
            sphere('Crab shoulder joint',root,(.135,.135,.135),'blue',5,8)
            tube('Armoured crab leg',[root,elbow],[.113,.083],'carapace',7)
            tube('Crab pointed foot',[elbow,foot],[.083,.012],'blue',7)
        tube('Eye stalk',[(side*.25,.65,-.42),(side*.30,.91,-.62)],[.037,.033],'teal',7)
        sphere('Kettleback dark eye',(side*.30,.94,-.635),(.08,.094,.066),'black',7,10)
        sphere('Kettleback eye glint',(side*.285,.969,-.69),(.022,.027,.012),'white',5,6)
        tube('Crab claw arm',[(side*.54,.46,-.30),(side*.75,.39,-.70)],[.12,.10],'blue',8)
        sphere('Crab claw shell',(side*.75,.38,-.87),(.24,.21,.30),'carapace',6,10)
        tube('Crab claw outer pincer',[(side*.90,.37,-.92),(side*.91,.27,-1.12),(side*.78,.21,-1.17)],[.115,.076,.008],'blue',7)
        tube('Crab claw inner pincer',[(side*.61,.38,-.94),(side*.64,.25,-1.10),(side*.75,.21,-1.17)],[.09,.058,.008],'blue',7)
    export_asset('crab')

def glider():
    sphere('Threadwing thorax',(0,.02,0),(.18,.18,.40),'teal',8,10)
    sphere('Threadwing head',(0,.03,-.43),(.20,.16,.18),'teal',7,10)
    for side in [-1,1]:
        sphere('Threadwing large eye',(side*.15,.075,-.51),(.065,.09,.066),'black',7,10)
        sphere('Threadwing eye gleam',(side*.16,.10,-.558),(.018,.020,.011),'white',5,6)
        tube('Threadwing antenna',[(side*.07,.14,-.47),(side*.16,.44,-.57),(side*.23,.58,-.65)],[.012,.009,.007],'teal',5)
        sphere('Antenna pale tip',(side*.23,.58,-.65),(.020,.045,.022),'cream',5,6)
        for rear in [False,True]:
            root=(side*.13,.04,.03 if rear else -.19)
            tip=(side*(1.37 if rear else 1.7),.24 if rear else .63,.56 if rear else -.57)
            trailing=(side*(.86 if rear else 1.45),-.18 if rear else .06,.85 if rear else .02)
            bend=(side*.61,.12,.51 if rear else -.17)
            mid=tuple((root[i]+tip[i]+trailing[i])/3 for i in range(3))
            mesh('Cream sail-like wing membrane',[root,tip,trailing,bend,mid],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],'sail')
            tube('Teal wing leading spar',[root,tuple((root[i]+tip[i])*.5 for i in range(3)),tip],[.040,.027,.005],'blue',7)
            for frac in [.33,.66]:
                edge=tuple(tip[i]*(1-frac)+trailing[i]*frac for i in range(3));tube('Wing membrane vein',[root,edge],[.015,.004],'cream',5)
        tube('Threadwing leg',[(side*.11,-.1,.1),(side*.23,-.34,.22),(side*.26,-.58,.1)],[.035,.026,.015],'teal',6)
        tube('Hooked threadwing foot',[(side*.26,-.58,.1),(side*.29,-.64,.0),(side*.23,-.63,-.06)],[.028,.021,.008],'darkwood',6)
        tube('Twin tail streamers',[(side*.06,-.04,.34),(side*.09,-.12,.77),(side*.29,-.27,1.56)],[.08,.046,.008],'teal',7)
        mesh('Cream streamer tip',[(side*.21,-.21,1.27),(side*.38,-.34,1.74),(side*.28,-.28,1.52)],[(0,1,2)],'sail')
    export_asset('glider')

def props():
    staff();export_asset('staff')
    barrel((0,0,0));export_asset('barrel')
    focus((0,0,0),1.5);export_asset('hearthstone')
    # Character-height original coastal tree, asymmetric clustered crown.
    tube('Weathered coastal tree trunk',[(0,0,0),(.12,1.3,.04),(-.08,2.65,.1),(.22,3.8,0)],[.30,.24,.14,.045],'wood',9)
    for i,(x,y,z) in enumerate([(-1.05,3.1,0),(1.1,3.3,.2),(-.3,3.8,-.8),(.15,4.3,.2),(.3,3.65,1.0)]):
        tube('Gnarled tree branch',[(0,1.8,0),(x*.5,y-.7,z*.5),(x,y,z)],[.15,.11,.035],'wood',7)
        sphere('Broad painted foliage clump',(x,y,z),(1.0,.82,.90),'leaf_light' if i%2 else 'leaf',5,8)
        sphere('Foliage accent',(x+.37,y+.32,z-.3),(.71,.57,.6),'leaf_light',5,8)
    export_asset('tree')
    # Fragmented arch POI built from the same ivory masonry as starter harbour.
    for side in [-1,1]:
        for row in range(5):box('Ruined arch pier',(side*1.42,row*.62+.31,0),(.73,.59,.83),'stone',.055)
    for j in range(9):
        a=j*math.pi/8;r=1.43;c=(r*math.cos(a),2.87+r*math.sin(a),0)
        o=box('Arch voussoir',c,(.70,.57,.83),'stone',.045)
        # Leave irregular edges at the ruin silhouette; carved block normals are faceted.
    export_asset('ruin_arch')
    # Floating death chest with metal corners and curved lid.
    box('Salvage chest body',(0,.29,0),(1.15,.57,.75),'wood',.045)
    lathe_obj=None
    vs=[]
    for x in [-.59,.59]:
        for j in range(9):
            a=j*math.pi/8;vs.append((x,.58+.26*math.sin(a),.39*math.cos(a)))
    mesh('Curved salvage chest lid',vs,[(j,j+1,j+10,j+9) for j in range(8)]+[tuple(range(8,-1,-1)),tuple(range(9,18))],'wood')
    for x in [-.43,.43]:
        box('Chest iron strap',(x,.29,-.385),(.07,.58,.04),'brass')
        tube('Curved lid iron strap',[(x,.588+.265*math.sin(j*math.pi/12),.395*math.cos(j*math.pi/12)) for j in range(13)],.028,'brass',5)
    box('Chest latch',(0,.50,-.423),(.14,.24,.045),'brass',.016)
    export_asset('loot_chest')

def boat_voyage():
    """Production silhouette matched to the approved voyage target, seen astern.

    Open rounded quarterdeck, broad teal-straked hull and diagonal triangular
    lateen sail. No cabin box blocks the crew from the actual gameplay camera.
    """
    zs=[-7,-6.4,-5.3,-3.5,-1,1.5,3.7,5.2,6.2,6.8,7.02]
    ws=[.025,.82,1.62,2.48,3.04,3.35,3.32,2.96,2.24,1.20,.025]
    def width(z):
        for i in range(len(zs)-1):
            if z<=zs[i+1]:
                t=(z-zs[i])/(zs[i+1]-zs[i]);return ws[i]*(1-t)+ws[i+1]*t
        return ws[-1]
    n=64
    def rise(z):return .32*(abs(z)/7.0)**3
    for side in [-1,1]:
        for row in range(8):
            vs=[]
            for j in range(n+1):
                z=-7+j*14.02/n
                for h in [row/8+.005,(row+1)/8-.005]:
                    y=-1.50+h*2.98+rise(z)
                    x=side*width(z)*(.20+.80*math.sin(h*math.pi/2))
                    vs.append((x,y,z))
            mat='teal' if row in (6,7) else 'wood'
            plank=mesh('Rounded layered hull plank',vs,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(n)],mat)
            rect=(.54+(row%5)*.077,.035,.058,.42) if mat=='teal' else (.033+(row%6)*.067,.525,.057,.45)
            mapped_uv(plank,[(h,j/n) for j in range(n+1) for h in (0,1)],rect)
        for yy,rr,mt in [(1.50,.105,'teal'),(.72,.055,'brass'),(-1.22,.05,'darkwood')]:
            taper=.20+.80*math.sin(min(1,(yy+1.50)/2.98)*math.pi/2)
            tube('Curved continuous gunwale',[(side*width(-7+j*14.02/n)*taper,yy+rise(-7+j*14.02/n),-7+j*14.02/n) for j in range(n+1)],rr,mt,8)
        for z in [-5.25,-3.35,-1.0,1.55,3.85,5.55]:
            x=side*width(z)
            tube('Thick outer hull binding',[(x*.66,-.35+rise(z),z),(x*.946,.74+rise(z),z),(x,1.53+rise(z),z)],[.080,.089,.088],'darkwood',6)
            for y in [.89,1.27]:sphere('Square-headed hull fastener',(x*1.01,y+rise(z),z),(.035,.045,.045),'brass',5,6)
        # Cream shell fenders are a distinctive recurring magical seafaring motif.
        for z in [-3.8,-1.7,.8,3.4,5.05]:
            x=side*width(z)
            rope('Tied shell fender rope',(x,1.68+rise(z),z),(x*1.06,.83+rise(z),z),.035,.030)
            sphere('Cream shell fender',(x*1.067,.76+rise(z),z),(.14,.25,.17),'sail',7,9)
            for r in [-.08,0,.08]:tube('Shell fender ridge',[(x*1.103,.60+rise(z),z+r*.4),(x*1.11,.78+rise(z),z+r),(x*1.094,.98+rise(z),z+r*.45)],.008,'cream',5)
    keel=[]
    for j in range(n+1):
        z=-7+j*14.02/n;y=-1.50+rise(z);w=width(z)*.20;keel.extend([(-w,y,z),(w,y,z)])
    mesh('Closed rounded bilge',keel,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(n)],'darkwood')
    for k in range(29):
        a=-1+k*2/29+.002;b=-1+(k+1)*2/29-.002;vs=[]
        for j in range(n+1):
            z=-6.86+j*13.72/n;w=width(z)*.975;vs.extend([(a*w,1.10,z),(b*w,1.10,z)])
        plank=mesh('Long quarterdeck plank',vs,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(n)],'wood')
        mapped_uv(plank,[(h,j/n) for j in range(n+1) for h in (0,1)],(.035+(k%6)*.07,.525,.05,.45))
    # Curved stern bench and low taut canvas windbreak, never a cabin facade.
    for x in [-2.2,-1.65,-1.1,-.55,0,.55,1.1,1.65,2.2]:
        z=6.22-.14*x*x
        box('Open stern curved bench',(x,1.40,z),(.56,.19,.53),'wood',.025)
        if abs(x)>1.5 or x==0:box('Stern bench leg',(x,1.21,z),(.12,.22,.35),'wood')
    panel_points=[(-2.7,5.04),(-2.14,5.68),(-1.3,6.17),(0,6.50),(1.3,6.17),(2.14,5.68),(2.7,5.04)]
    for x,z in panel_points:
        cylinder('Stern windbreak stanchion',(x,1.75,z),.075,1.4,'wood',8)
        cylinder('Stanchion brass cap',(x,2.47,z),.095,.08,'brass',8)
        ring('Stern canvas rope lashing',(x,2.20,z),.10,.024,'rope','xz',12)
    for i in range(len(panel_points)-1):
        x1,z1=panel_points[i];x2,z2=panel_points[i+1]
        cx=(x1+x2)*.5;cz=(z1+z2)*.5
        mesh('Low stern canvas screen',[(x1,2.21,z1),(cx,2.15,cz),(x2,2.21,z2),(x1,1.65,z1),(cx,1.60,cz+.05),(x2,1.65,z2)],[(0,1,4,3),(1,2,5,4)],'sail')
        rope('Windbreak top rope',(x1,2.25,z1),(x2,2.25,z2),.03,.029)
    # Waist-height helmsman's wheel, with no inaccessible roof underneath.
    cylinder('Helm pedestal',(0,1.56,3.65),.14,.90,'wood',10)
    ring('Large working helm',(0,2.13,3.49),.60,.065,'wood','xy',32)
    ring('Helm brass inner rim',(0,2.13,3.48),.53,.022,'brass','xy',24)
    for j in range(10):
        a=j*math.tau/10
        tube('Helm spoke',[(0,2.13,3.49),(.74*math.cos(a),2.13+.74*math.sin(a),3.49)],.029,'wood',7)
        sphere('Helm handle',(.74*math.cos(a),2.13+.74*math.sin(a),3.49),(.055,.055,.055),'wood',5,8)
    sphere('Helm central boss',(0,2.13,3.46),(.125,.125,.10),'brass',7,10)
    # Strong mast, diagonal boom, standing ropes and ratlines.
    tube('Swept main mast',[(0,1.1,.1),(0,8.8,.1),(.14,10.45,.12)],[.245,.15,.065],'wood',12)
    for y in [1.20,1.47,3.2,7.9,9.70]:
        for off in [0,.058,.116]:ring('Mast lashings',(0,y+off,.1),.25-y*.009,.025,'rope','xz',18)
    tube('Diagonal lateen foot boom',[(0,3.18,.11),(4.35,2.76,-3.87)],[.09,.065],'wood',10)
    tube('Bow stem',[(0,-.72,-6.83),(0,1.58,-6.97),(0,2.04,-7.73)],[.22,.18,.07],'wood',10)
    for x,z in [(-2.77,2.3),(2.8,2.3),(-2.38,-3.2)]:rope('Standing mast shroud',(x,1.65,z),(0,9.7,.1),.1,.031)
    rope('Forestay',(0,10.05,.1),(0,1.90,-7.65),.06,.033)
    rope('Clew sheet',(4.33,2.82,-3.85),(2.42,1.52,-3.4),.11,.037)
    for x in [-.50,.50]:rope('Rope ladder sides',(x,1.18,.73),(x*.48,9.2,.32),0,.024)
    for j in range(18):
        t=j/18;y=1.52+j*.41;w=.50-t*.26;z=.73-t*.41
        tube('Ratline horizontal', [(-w,y,z),(w,y,z)],.021,'rope',5)
    # Broad curled blue pennant with enough geometry to read against the clouds.
    vs=[]
    for j in range(19):
        t=j/18;x=.13+t*3.8;zz=.15+.55*math.sin(t*math.pi*3.2);yy=10.13-.38*t+.27*math.sin(t*math.pi*3)
        h=.56*(1-.72*t)
        vs.extend([(x,yy,zz),(x,yy-h,zz)])
    mesh('Long blue mast pennant',vs,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(18)],'cloth_navy')
    # Spell stations, small practical equipment and hanging warm lanterns.
    focus((-2.75,1.53,3.57),1.0);focus((2.86,1.48,2.5),.94);focus((-1.70,1.34,-4.95),.76)
    barrel((-2.50,1.10,1.18),.85);barrel((1.83,1.10,4.85),.80)
    box('Low map table',(-1.98,1.75,-.8),(1.16,.15,1.18),'wood',.045)
    for x in [-2.43,-1.52]:
        for z in [-1.25,-.34]:box('Map table leg',(x,1.41,z),(.11,.62,.11),'wood')
    box('Leather spell folio',(-1.98,1.86,-.8),(.83,.065,.64),'darkwood',.03)
    for x in [-2.17,-1.80]:box('Open spellbook page',(x,1.906,-.8),(.35,.025,.55),'sail',.008)
    lantern((-2.65,2.10,5.2),1.13);lantern((2.65,2.10,5.2),1.13);lantern((0,1.54,-7.67),1.00)
    # Visible port ladder gives swimmers a physically legible boarding location.
    for z in [1.37,2.03]:tube('Port boarding ladder rail',[(-3.48,-.95,z),(-3.48,1.50,z),(-3.26,1.65,z)],[.06,.06,.045],'wood',8)
    for j in range(8):tube('Port boarding rung',[(-3.49,-.78+j*.31,1.37),(-3.49,-.78+j*.31,2.03)],.045,'wood',8)
    export_asset('boat')
    # Curved triangle stretches from the mast to the starboard/bow clew.
    # Tensor patch has a collapsing top row; slight folds break the perfect plane.
    def sail_point(u,t,offset=0):
        span=(1-t)**.68
        x=4.35*u*span
        y=3.18+6.53*t-.40*u*(1-t)+.22*math.sin(math.pi*u)*(1-t)
        z=.11-3.98*u*span+.84*math.sin(math.pi*u)*math.sin(math.pi*t*.86)
        # Offset along the diagonal sail's horizontal normal.
        return (x+offset*.675,y,z+offset*.739)
    nx=32;ny=32;vs=[]
    for iy in range(ny+1):
        for ix in range(nx+1):vs.append(sail_point(ix/nx,iy/ny))
    fs=[]
    for iy in range(ny):
        for ix in range(nx):
            a=iy*(nx+1)+ix;fs.append((a,a+1,a+nx+2,a+nx+1))
    cloth=mesh('Billowed triangular lateen sail',vs,fs,'sail',True)
    mapped_uv(cloth,[(ix/nx,iy/ny) for iy in range(ny+1) for ix in range(nx+1)],(.525,.525,.45,.45))
    # Huge crest on BOTH faces, essential because the review camera is astern.
    # Each ribbon is parameterized on the cloth, so it cannot intersect/disappear.
    for face in [-1,1]:
        crest=[]
        for j in range(121):
            f=j/120;ang=f*math.pi*3.6;r=.025+f*.285
            u=.52+r*math.cos(ang);t=.43+r*.72*math.sin(ang)
            dx=.285*math.cos(ang)-r*math.sin(ang)*math.pi*3.6
            dy=(.285*math.sin(ang)+r*math.cos(ang)*math.pi*3.6)*.72
            length=math.hypot(dx,dy);w=.008+.033*f
            for side in [-1,1]:crest.append(sail_point(u+side*(-dy/length)*w,t+side*(dx/length)*w,face*.035))
        mesh('Bold painted spiral on canvas',crest,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(120)],'blue')
        # Broad swooping tail extends the spiral into an unmistakable wave glyph.
        tail=[]
        for j in range(33):
            f=j/32;u=.616*(1-f)+.22*f+.14*math.sin(math.pi*f);t=.218*(1-f)+.095*f-.06*math.sin(math.pi*f);w=.041*(1-f)+.001
            tail.extend([sail_point(u,t-w,face*.037),sail_point(u,t+w,face*.037)])
        mesh('Spiral wave tail',tail,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(32)],'blue')
    for edge in [0,1]:tube('Canvas edge bolt rope',[sail_point(edge,j/32) for j in range(33)],.026,'rope',6)
    tube('Canvas lower seam',[sail_point(j/32,0) for j in range(33)],.026,'rope',6)
    export_asset('boat_sail')

def wizard_variants():
    wizard(False,'wizard_cast','cast')
    wizard(False,'wizard_helm','helm')
    wizard(False,'wizard_green','idle')
    wizard(False,'wizard_rust','idle')

def render_reviews():
    world=bpy.data.worlds.new('Spellwake studio sky');world.use_nodes=True
    bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND')
    bg.inputs['Color'].default_value=(.13,.26,.34,1);bg.inputs['Strength'].default_value=.65
    SCENE.world=world
    SCENE.render.resolution_x=1200;SCENE.render.resolution_y=1000;SCENE.render.resolution_percentage=100
    file_formats=[i.identifier for i in SCENE.render.image_settings.bl_rna.properties['file_format'].enum_items]
    SCENE.render.image_settings.file_format=next(v for v in file_formats if v=='PNG')
    camdata=bpy.data.cameras.new('Asset review camera');cam=bpy.data.objects.new('Asset review camera',camdata);COL.objects.link(cam);SCENE.camera=cam
    def lamp(name,pos,power,size,color):
        data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
        o=bpy.data.objects.new(name,data);COL.objects.link(o);o.location=g(pos)
        o.rotation_euler=(Vector(g((0,2,0)))-o.location).to_track_quat('-Z','Y').to_euler()
    lamp('Large warm key',(-9,16,-12),2600,8,(1,.88,.68))
    lamp('Cool fill',(10,10,-3),1800,8,(.57,.78,1))
    lamp('Rim light',(0,12,11),2200,6,(1,.95,.74))
    sunlight=bpy.data.lights.new('Soft sunlight','SUN');sunlight.energy=2.0;sunlight.angle=.13
    sun=bpy.data.objects.new('Soft sunlight',sunlight);COL.objects.link(sun);sun.rotation_euler=(.42,-.55,-.42)
    for label,prefixes,pos,target,scale in [('boat-review',('boat_',), (16,11,20),(0,4.4,0),None),('wizard-review',('wizard_SW_',),(3.4,2.4,-6.8),(0,1.10,0),None),('harbour-review',('shop_',),(13,9,-16),(0,3,0),None),('creature-review',('crab_',),(2.6,1.9,-3.7),(0,.58,0),None)]:
        for o in SCENE.objects:
            if o.type=='MESH':o.hide_render=not any(o.name.startswith(p) for p in prefixes)
        cam.location=g(pos);cam.rotation_euler=(Vector(g(target))-cam.location).to_track_quat('-Z','Y').to_euler();camdata.lens=48
        SCENE.render.filepath=str(OUT/(label+'.png'))
        bpy.ops.render.render(write_still=True)

def main():
    materials()
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    requested=[a for a in args if not a.startswith('--')]
    builders={'boat':boat_voyage,'wizard':lambda:wizard(False),'wizard_variants':wizard_variants,'shopkeeper':lambda:wizard(True),'lighthouse':lighthouse,'shop':shop,'dock':dock,'crab':crab,'glider':glider,'props':props}
    for name,build in builders.items():
        if not requested or name in requested:
            print('BUILD_ASSET '+name,flush=True);build()
    (OUT/'asset-manifest.json').write_text(json.dumps({'units':'metres','forward':'-Z','up':'+Y','blender':bpy.app.version_string,'assets':RECORDS},indent=2),encoding='utf8')
    source_dir=OUT/'source';source_dir.mkdir(exist_ok=True)
    (source_dir/'.gdignore').write_text('')
    bpy.ops.wm.save_as_mainfile(filepath=str(source_dir/'spellwake-source.blend'))
    if '--qa' in args:render_reviews()
    print('ASSETS_COMPLETE '+json.dumps(RECORDS),flush=True)

if __name__=='__main__':main()
