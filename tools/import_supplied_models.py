"""Normalize supplied GLBs without modifying their originals.

Run in isolated Blender: blender --background --factory-startup --threads 4
  --python tools/import_supplied_models.py
Coordinates in the configuration use Blender Z-up after glTF import. All
exports use Godot metres, +Y up and -Z forward. Source identities and headings
were checked from four-angle renders, rather than inferred from filenames.
"""
import bpy, bmesh, hashlib, json, math, sys
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models/supplied'
TMP = ROOT / 'tmp/model-intake'
OUT.mkdir(parents=True, exist_ok=True)
(TMP/'textures').mkdir(parents=True, exist_ok=True)

# source, reference identity, source-to-forward rotation, scale axis and target,
# vertical origin. A rotation about Blender Z sends the inspected front to +Y.
SPECS = [
 ('stylized+crab','crab',90,0,2.1,'base'),
 ('blue+manta+ray','ribbonwake',180,0,4.2,'center'),
 ('blue+patterned+fish','lanternjaw',90,1,3.8,'center'),
 ('blue+phoenix','stormglass',90,0,6.8,'center'),
 ('fantasy+sea+creature','tidebell',180,0,7.0,'base'),
 ('flying+fantasy+creature','glider',90,0,3.4,'center'),
 ('giant+turtle','orchard',90,2,5.6,'base'),
 ('rock+plated+reptile','basalt',180,1,5.4,'base'),
 ('stegosaurus','brinecap',90,1,3.8,'base'),
 ('turtle+creature','cumulus',135,2,4.5,'center'),
 ('lantern','lantern',90,2,.8,'base'),
 ('medieval+door','tide_gate',90,2,5.2,'base'),
 ('orb+pedestal','hearth_pad',0,0,4.6,'base'),
 ('stone+arch','ruin_arch',90,2,4.6,'base'),
 ('stone+cottage','cottage',180,0,8.8,'base'),
 ('treasure+chest','loot_chest',90,2,.88,'base'),
 ('wooden+barrel','barrel',0,2,.95,'base'),
 ('wooden+crate','crate',90,2,1.0,'base'),
 ('wooden+dock','dock',0,0,4.2,'deck'),
 ('ship','boat_hull',90,0,6.2,'boat_deck'),
]

# A kit is exported as one shared-texture library, with centered local geometry
# per named child and its original layout preserved through node translations.
# Region coordinates were checked against top/oblique rendered inspections.
KITS = {
 'tide_kit': ('ancient+ruins',17.0,[
   ('tide_steps',(-.21,.07,.34,.51)),
   ('tide_banner_gate',(-.245,-.14,.055,.31)),
   ('tide_wall',(-.27,-.14,-.13,.055)),
   ('tide_arch',(-.39,-.27,-.35,-.12)),
   ('tide_rubble',(.15,.33,-.14,.02)),
   ('tide_railing',(.28,.38,.02,.19)),
   ('tide_pillar',(.13,.20,-.31,-.24)),
   ('tide_block',(.06,.12,-.38,-.28)),
   ('tide_floor',(-.13,.02,-.51,-.33)),
   ('tide_tile',(.18,.25,-.24,-.15)),
 ]),
 'coastal_kit': ('modular+environment+elements',34.0,[
   ('coastal_arch',(-.12,.12,-.51,-.39)),
   ('coastal_pillar',(-.01,.09,-.39,-.30)),
   ('coastal_railing',(-.12,.04,-.30,-.20)),
   ('coastal_steps',(-.12,.05,-.20,-.078)),
   ('coastal_banner',(-.012,.10,-.09,.095)),
   ('coastal_column',(-.11,-.012,-.09,.01)),
   ('coastal_bridge',(-.04,.12,.09,.245)),
   ('coastal_rock',(-.04,.12,.245,.40)),
   ('coastal_moss',(-.04,.12,.40,.51)),
 ]),
 'root_kit': ('stone+ruin+archway',32.0,[
   ('root_steps',(.195,.30,.18,.35)),
   ('root_small_column',(.12,.18,.105,.16)),
   ('root_tree',(.18,.405,.16,.405)),
   ('root_branch',(.30,.50,.405,.51)),
   ('root_growth',(.045,.19,-.07,.16)),
   ('root_arch',(.015,.10,-.20,-.07)),
   ('root_door',(.19,.28,.015,.115)),
   ('root_beam',(-.025,.02,.255,.45)),
   ('root_column',(-.045,.07,.18,.24)),
   ('root_panel',(-.25,-.15,.13,.24)),
   ('root_lintel',(-.095,.025,-.29,-.20)),
   ('root_wall',(-.105,-.02,-.45,-.29)),
   ('root_floor',(-.49,-.13,-.51,-.29)),
 ])
}

MODULE_REVIEW = {
 'tide_banner_gate':('Teal portcullis','world_prop',''),
 'tide_railing':('Small raised wooden platform','world_prop',''),
 'tide_tile':('Capped stone pedestal','world_prop',''),
 'coastal_banner':('Compass banner','review_only','Overlong disconnected pole reconstruction.'),
 'root_arch':('Root-covered masonry wall relief','world_prop',''),
 'root_growth':('Open root arch','world_prop',''),
 'root_column':('Stone wall panel','world_prop',''),
 'root_beam':('Low masonry rail','world_prop',''),
 'root_lintel':('Recessed stone bookshelf','world_prop',''),
 'root_branch':('Branch and leaf reconstruction','review_only','Leaves float above the disconnected branch.'),
 'root_tree':('Root stump and small pedestal','review_only','Contains an adjacent independent pedestal; retained for later separation.'),
 'root_wall':('Stone arch and detached column','review_only','Contains two separate architectural subjects.'),
 'root_floor':('Two flat decorative panels','review_only','Two disconnected planar panels; not a coherent prop.'),
 'root_panel':('Flat decorated stone panel','review_only','Low-detail planar reconstruction; no clear gameplay placement.'),
 'root_small_column':('Root-covered small pillar','review_only','Partial irregular root/pillar reconstruction.'),
 'root_door':('Root stump fragment','review_only','Not a door; partial root geometry with a cut end.'),
 'review_fragments':('Unclassified source fragments','review_only','Preserved fragments not assigned to a reviewed prop.'),
}

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def load(path):
    bpy.ops.import_scene.gltf(filepath=str(path))
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    for obj in objects:
        obj.data.transform(obj.matrix_world)
        obj.matrix_world=Matrix.Identity(4)
    return objects

def bounds(objects):
    coords=[obj.matrix_world@v.co for obj in objects for v in obj.data.vertices]
    return (Vector(tuple(min(p[i] for p in coords) for i in range(3))),
            Vector(tuple(max(p[i] for p in coords) for i in range(3))))

def textures(objects, name, size):
    done={}
    for obj in objects:
        for mat in obj.data.materials:
            if mat is None or not mat.use_nodes: continue
            for node in mat.node_tree.nodes:
                if node.type=='BSDF_PRINCIPLED':
                    node.inputs['Roughness'].default_value=.82
                    node.inputs['Metallic'].default_value=0
                if node.type=='TEX_IMAGE' and node.image:
                    old_name=node.image.name
                    if old_name not in done:
                        img=node.image
                        if max(img.size)>size: img.scale(size,size)
                        target=TMP/'textures'/f'{name}.jpg'
                        img.filepath_raw=str(target)
                        img.file_format='JPEG';img.save()
                        # glTF imports cache original packed bytes. Loading the
                        # resized file freshly prevents exporting that 4K cache.
                        done[old_name]=bpy.data.images.load(str(target),check_existing=False)
                    node.image=done[old_name]
            mat.name=name+'_painted'

def export(objects, name, source, metadata):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'{name}.glb'),export_format='GLB',
        use_selection=True,export_apply=True,export_yup=True,
        export_cameras=False,export_lights=False,export_image_format='JPEG',
        export_jpeg_quality=88,export_extras=True)
    lo,hi=bounds(objects)
    row={'id':name,'source':str(source.relative_to(ROOT)).replace('\\','/'),
         'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
         'path':f'assets/models/supplied/{name}.glb',
         'bounds_min':[round(lo[0],5),round(lo[2],5),round(-hi[1],5)],
         'bounds_max':[round(hi[0],5),round(hi[2],5),round(-lo[1],5)],
         'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),
         'vertices':sum(len(o.data.vertices) for o in objects),
         'bytes':(OUT/f'{name}.glb').stat().st_size,
         'rigged':False,'animations':[],**metadata}
    print('EXPORTED',name,row['bounds_min'],row['bounds_max'],flush=True)
    return row

def deck_height(objects, boat=False):
    # Select the largest area bin of upward-facing central deck triangles.
    bins={}
    lo,hi=bounds(objects);dims=hi-lo
    for obj in objects:
        obj.data.update()
        for p in obj.data.polygons:
            c=p.center
            central=abs(c.x)<dims.x*.26 and abs(c.y)<dims.y*.30
            if p.normal.z>.85 and central and dims.z*.30<c.z<dims.z*.72:
                key=round(c.z/dims.z,2)
                bins[key]=bins.get(key,0)+p.area
    if not bins: raise RuntimeError('No deck surface found')
    return max(bins,key=bins.get)*dims.z

def normalize(spec):
    stem,name,yaw,axis,target,origin=spec
    source=ROOT/'models'/f'{stem}+3d+model.glb'
    reset();objects=load(source)
    rot=Matrix.Rotation(math.radians(yaw),4,'Z')
    for obj in objects:obj.data.transform(rot)
    lo,hi=bounds(objects);scale=target/(hi-lo)[axis]
    for obj in objects: obj.data.transform(Matrix.Diagonal((scale,scale,scale,1)))
    if origin=='boat_deck':
        # Preserve beam/length while fitting the supplied deep hull below the
        # established walkable deck. Exact source deck sampled at z=.232.
        vertical=8.0/scale
        for obj in objects: obj.data.transform(Matrix.Diagonal((1,1,vertical,1)))
        lo,hi=bounds(objects);zshift=1.18-.232*8.0
    elif origin=='deck': zshift=-deck_height(objects)
    else:
        lo,hi=bounds(objects)
        zshift=-lo.z if origin=='base' else -(lo.z+hi.z)/2
    lo,hi=bounds(objects)
    shift=Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,zshift))
    for obj in objects:
        obj.data.transform(Matrix.Translation(shift));obj.name=name
        obj['source_file']=source.name;obj['reviewed_forward']='-Z';obj['origin_contract']=origin
    size=2048 if name in ('boat_hull','cottage') else 1024
    textures(objects,name,size)
    return export(objects,name,source,{'reference_id':'boat' if name=='boat_hull' else name,
        'source_rotation_degrees':yaw,'origin':origin,'texture_size':size,
        'notes':'Hull only; combine boat_rig and existing boat_sail.' if name=='boat_hull' else ''})

def connected_components(mesh):
    # Index disjoint surfaces without modifying their topology or UVs.
    adjacency=[[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a,b=edge.vertices;adjacency[a].append(b);adjacency[b].append(a)
    # glTF duplicates vertices at UV/normal seams. Link coincident points in the
    # graph so a rope or mast remains one physical component, keeping original
    # vertices and UVs completely unchanged in the exported subset.
    by_position={}
    for vertex in mesh.vertices:
        key=tuple(round(c,5) for c in vertex.co)
        if key in by_position:
            other=by_position[key]
            adjacency[vertex.index].append(other);adjacency[other].append(vertex.index)
        else:by_position[key]=vertex.index
    seen=set();groups=[]
    for v in mesh.vertices:
        if v.index in seen:continue
        todo=[v.index];seen.add(v.index);group=[]
        while todo:
            i=todo.pop();group.append(i)
            for n in adjacency[i]:
                if n not in seen:seen.add(n);todo.append(n)
        groups.append(group)
    return groups

def retained_rig():
    reset();source=ROOT/'assets/models/boat.glb';objects=load(source);kept=[]
    for obj in objects:
        keep=set()
        for comp in connected_components(obj.data):
            ps=[obj.data.vertices[i].co for i in comp]
            lo=Vector(tuple(min(p[j] for p in ps) for j in range(3)))
            hi=Vector(tuple(max(p[j] for p in ps) for j in range(3)))
            # Existing Blender coords: x=Godot x, y=-Godot z, z=height.
            tall=hi.z>4.2
            boom=lo.z>2.6 and hi.z<3.4 and hi.x-lo.x>4 and hi.y-lo.y>3
            lashing=abs((lo.x+hi.x)/2)<.04 and abs((lo.y+hi.y)/2+.1)<.04 and lo.z>1
            ratline=lo.z>1.4 and hi.z-lo.z<.10 and lo.x<-.2 and hi.x>.2 and -.8<lo.y<-.2
            helm=lo.x>-.9 and hi.x<.9 and lo.y>-3.85 and hi.y<-3.2 and lo.z>1.05
            if tall or boom or lashing or ratline or helm:keep.update(comp)
        if not keep:bpy.data.objects.remove(obj,do_unlink=True);continue
        bm=bmesh.new();bm.from_mesh(obj.data);bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index not in keep],context='VERTS')
        bm.to_mesh(obj.data);bm.free();obj.name='retained_'+obj.name;kept.append(obj)
    # The imported bow is shorter than the old hull. Keep the long forestay
    # attached to its bow instead of ending in mid-air beyond the new stem.
    for obj in kept:
        for v in obj.data.vertices:
            if v.co.y>5.0:
                t=(v.co.y-5.0)/(7.65-5.0)
                v.co.y=5.0+(v.co.y-5.0)*(6.18-5.0)/(7.65-5.0)
                v.co.z+=.48*t
    return export(kept,'boat_rig',source,{'origin':'existing boat origin','texture_size':1254,
        'notes':'Extracted existing mast, lateen boom, pennant, shrouds, ratlines and helm; original geometry/materials retained.'})

def kit_library(name, spec):
    stem,scale,regions=spec
    reset();source=ROOT/'models'/f'{stem}+3d+model.glb'
    original=load(source)[0]
    textures([original],name,2048)
    groups={n:[] for n,r in regions};groups['review_fragments']=[]
    vertex_groups={}
    for comp in connected_components(original.data):
        coords=[original.data.vertices[i].co for i in comp]
        x=(min(v.x for v in coords)+max(v.x for v in coords))/2
        y=(min(v.y for v in coords)+max(v.y for v in coords))/2
        match=next((n for n,(x0,x1,y0,y1) in regions if x0<=x<=x1 and y0<=y<=y1),'review_fragments')
        for i in comp:vertex_groups[i]=match
    for face in original.data.polygons:
        groups[vertex_groups[face.vertices[0]]].append(face.index)
    objects=[];modules=[]
    for module,face_ids in groups.items():
        if not face_ids:continue
        obj=original.copy();obj.data=original.data.copy();bpy.context.scene.collection.objects.link(obj)
        bm=bmesh.new();bm.from_mesh(obj.data);bm.faces.ensure_lookup_table()
        keep=set(face_ids)
        bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in keep],context='FACES')
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
        bm.to_mesh(obj.data);bm.free()
        obj.data.transform(Matrix.Rotation(math.pi/2,4,'Z') @ Matrix.Scale(scale,4))
        lo,hi=bounds([obj]);center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
        obj.data.transform(Matrix.Translation(-center));obj.location=center
        obj.name=module;obj['source_file']=source.name;obj['module_id']=module
        local_lo=lo-center;local_hi=hi-center
        subject,placement,reason=MODULE_REVIEW.get(module,(module.replace('_',' '),'world_prop',''))
        modules.append({'node':module,'bounds_min':[round(local_lo.x,4),0,round(-local_hi.y,4)],
            'bounds_max':[round(local_hi.x,4),round(local_hi.z,4),round(-local_lo.y,4)],
            'triangles':sum(len(p.vertices)-2 for p in obj.data.polygons),
            'placement':placement,'subject':subject,'review_reason':reason})
        objects.append(obj)
    bpy.data.objects.remove(original,do_unlink=True)
    return export(objects,name,source,{'reference_id':None,'origin':'library layout; child mesh base-centered',
        'texture_size':2048,'modules':modules,
        'notes':'Multi-object source board separated into reusable named child meshes. Reset child position when instantiating a module; all children share one atlas. Unclassified fragments retained for review.'})

def main():
    requested=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    rows=[]
    for spec in SPECS:
        if not requested or spec[1] in requested:rows.append(normalize(spec))
    if not requested or 'boat_rig' in requested:rows.append(retained_rig())
    for name,spec in KITS.items():
        if not requested or name in requested:rows.append(kit_library(name,spec))
    manifest=OUT/'manifest.json'
    prior=json.loads(manifest.read_text()).get('assets',[]) if requested and manifest.exists() else []
    ids={row['id'] for row in rows};rows=[r for r in prior if r['id'] not in ids]+rows
    manifest.write_text(json.dumps({'units':'metres','forward':'-Z','up':'+Y','assets':rows},indent=2)+'\n')

if __name__=='__main__':main()
