"""Build deformation rigs for the supplied creature meshes, preserving their art.

Run with Blender 5.2+ in an isolated process::

    blender --background --factory-startup --threads 3 \
        --python tools/rig_supplied_creatures.py -- ribbonwake glider stormglass

Omit IDs for all ten. The original GLBs are the reproducible input; the same
normalization contract as import_supplied_models.py is used. No geometry is
generated or replaced. Anatomical landmarks below were placed after inspecting
orthographic renders of each supplied mesh (Blender X/right, Y/front, Z/up).
The modest looping clips are basic locomotion, not a combat animation set.
"""

import importlib.util
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models/supplied'
QA = ROOT / 'tmp/model-intake/rigs'
IDS = ['ribbonwake', 'glider', 'stormglass', 'lanternjaw', 'tidebell',
       'orchard', 'basalt', 'brinecap', 'cumulus', 'crab']
LOCOMOTION = {n: ('walk' if n in ('orchard', 'basalt', 'brinecap', 'crab')
                  else 'swim' if n in ('ribbonwake', 'lanternjaw', 'tidebell')
                  else 'fly') for n in IDS}


def smooth(a, b, value):
    t = max(0.0, min(1.0, (value-a)/(b-a)))
    return t*t*(3-2*t)


def distance_segment(p, a, b):
    delta = b-a
    t = max(0.0, min(1.0, (p-a).dot(delta)/delta.length_squared))
    return (p-(a+delta*t)).length


class Rig:
    def __init__(self, name, body):
        self.name = name
        self.bones = []
        self.chains = {}
        self.motion = {}
        self.add('root', (0, 0, 0), (0, 0, .25), None)
        self.add('body', body, Vector(body)+Vector((0, .4, 0)), 'root')

    def add(self, name, head, tail, parent):
        self.bones.append((name, Vector(head), Vector(tail), parent))

    def chain(self, name, points, parent='body', motion=None):
        names = []
        for i in range(len(points)-1):
            bone = f'{name}_{i+1:02d}'
            self.add(bone, points[i], points[i+1], parent)
            names.append(bone)
            parent = bone
        self.chains[name] = names
        if motion:
            self.motion[name] = motion
        return names

    def distance(self, chain, p):
        names = self.chains[chain]
        return min(distance_segment(p, a, b) for n, a, b, _ in self.bones if n in names)

    def weights(self, chain, p, softness=.10):
        names = self.chains[chain]
        values = [(n, 1/(distance_segment(p, a, b)**2+softness**2)**2)
                  for n, a, b, _ in self.bones if n in names]
        values = sorted(values, key=lambda pair: -pair[1])[:2]
        total = sum(v for _, v in values)
        return {n: v/total for n, v in values}

    def nearest(self, prefix, p):
        return min((n for n in self.chains if n.startswith(prefix)),
                   key=lambda n: self.distance(n, p))


def profile(name):
    if name == 'ribbonwake':
        r = Rig(name, (0, 1.45, .15))
        r.chain('head', [(0, 1.8, .2), (0, 2.7, .2)], motion=('head', .025))
        r.chain('tail', [(0, .8, .4), (0, -.25, .48), (-.05, -1.3, .54),
                         (.12, -2.45, .65), (.4, -2.1, .9)], motion=('tail', .09))
        for s, side in [(-1, 'L'), (1, 'R')]:
            r.chain(f'wing_upper_{side}', [(s*.65, 1.55, .3), (s*1.3, 1.25, .45),
                    (s*2.0, .65, .9)], motion=('wing', s*.27))
            r.chain(f'wing_lower_{side}', [(s*.60, 1.55, .02), (s*1.25, .92, -.42),
                    (s*2.02, .08, -.95)], motion=('wing', s*.20))
    elif name == 'glider':
        r = Rig(name, (.05, .40, .05))
        r.chain('head', [(0, .52, .1), (0, .8, .15)], motion=('head', .025))
        r.chain('tail', [(.05, .25, -.1), (.15, -.2, -.33), (.2, -.65, -.60),
                         (.2, -1.0, -.78)], motion=('tail', .065))
        for s, side in [(-1, 'L'), (1, 'R')]:
            r.chain(f'wing_upper_{side}', [(s*.12, .5, .13), (s*.8, .72, .4),
                    (s*1.65, 1.03, .78)], motion=('wing', s*.34))
            r.chain(f'wing_lower_{side}', [(s*.13, .41, .02), (s*.8, .38, -.08),
                    (s*1.5, .47, -.04)], motion=('wing', s*.28))
            r.chain(f'leg_{side}', [(s*.14, .35, -.1), (s*.2, .33, -.42),
                    (s*.25, .45, -.6)], motion=('dangle', .07))
    elif name == 'stormglass':
        r = Rig(name, (0, .85, -.02))
        r.chain('head', [(0, 1.0, .25), (0, 1.35, .75), (0, 1.5, 1.1)], motion=('head', .035))
        r.chain('tail', [(0, .6, -.35), (0, -.2, -.55), (0, -1.05, -.95),
                         (0, -1.75, -1.5)], motion=('tail', .045))
        for s, side in [(-1, 'L'), (1, 'R')]:
            r.chain(f'wing_{side}', [(s*.45, .95, .08), (s*1.35, 1.08, .53),
                    (s*2.25, 1.4, .91), (s*3.3, 1.5, 1.05)], motion=('wing', s*.36))
            r.chain(f'leg_{side}', [(s*.24, .85, -.55), (s*.33, 1.05, -1.02),
                    (s*.4, 1.45, -1.26)], motion=('dangle', .055))
    elif name == 'lanternjaw':
        r = Rig(name, (.1, .7, .02))
        r.chain('head', [(.1, 1.0, .0), (.15, 1.85, .12)], motion=('head', .015))
        r.chain('tail', [(.1, .4, .04), (-.02, -.35, .04), (-.3, -1.15, .2),
                         (-.7, -1.87, .22)], motion=('tail', .18))
        r.chain('fin_L', [(-.35, .8, -.08), (-.56, .46, -.38), (-.7, .2, -.54)], motion=('fin', -.16))
        r.chain('fin_R', [(.53, .77, -.15), (.70, .42, -.46), (.83, .14, -.7)], motion=('fin', .16))
    elif name == 'tidebell':
        r = Rig(name, (0, 0, 1.75))
        # The shell remains rigid. Each of eight separately visible arms gets
        # a three-joint chain; angle selection happens below the shell rim.
        for i in range(8):
            angle = math.radians(22.5+45*i)
            x, y = math.cos(angle), math.sin(angle)
            r.chain(f'tentacle_{i}', [(x*1.15, y*1.15, 1.75),
                (x*2.1, y*2.1, .85), (x*3.0, y*3.0, .5),
                (x*2.95, y*2.95, .12)], motion=('tentacle', .12))
    elif name in ('orchard', 'basalt', 'brinecap'):
        specs = {
            'orchard': {'body': (0, 0, 1.65), 'head': [(0, 1.1, 2.1), (0, 2.25, 2.25), (0, 3.0, 2.15)],
                'tail': [(0, -1.6, 1.25), (0, -2.35, .95), (0, -2.95, .83)],
                'legs': [('front', 1.0, 1.25, 1.5), ('back', -1.5, 1.3, 1.25)]},
            'basalt': {'body': (0, .6, 1.05), 'head': [(0, 1.55, 1.37), (0, 2.5, 1.53)],
                'tail': [(0, -.35, 1.08), (0, -1.1, .78), (0, -1.85, .44), (0, -2.62, .27)],
                'legs': [('front', 1.85, 1.2, 1.0), ('middle', .78, .82, .67), ('back', -.32, 1.0, .83)]},
            'brinecap': {'body': (0, 0, .98), 'head': [(0, .85, 1.13), (0, 1.8, 1.09)],
                'tail': [(0, -.8, .85), (0, -1.25, .57), (0, -1.85, .44)],
                'legs': [('front', .85, .48, .81), ('back', -.64, .49, .76)]}}
        spec = specs[name]
        r = Rig(name, spec['body'])
        r.chain('head', spec['head'], motion=('head', .025))
        r.chain('tail', spec['tail'], motion=('tail', .04))
        for index, (part, y, x, z) in enumerate(spec['legs']):
            for s, side in [(-1, 'L'), (1, 'R')]:
                r.chain(f'leg_{part}_{side}', [(s*x*.72, y, z), (s*x, y+.02, z*.48),
                    (s*x, y+.2, .10)], motion=('walk', (index+(s>0)) % 2))
    elif name == 'cumulus':
        r = Rig(name, (0, .2, .9))
        r.chain('head', [(0, .9, 1), (.06, 1.8, 1.18), (.05, 2.3, 1.2)], motion=('head', .025))
        r.chain('tail', [(-.05, -1.0, .4), (-.23, -1.8, -.5), (-.35, -1.75, -1.3),
                         (-.38, -.55, -1.95), (-.05, .15, -2.08)], motion=('tail', .065))
        for s, side in [(-1, 'L'), (1, 'R')]:
            r.chain(f'fin_front_{side}', [(s*.62, 1.1, .65), (s*1.04, 1.35, .2),
                    (s*1.2, 1.45, .08)], motion=('fin', s*.20))
            r.chain(f'fin_back_{side}', [(s*.68, -.8, .2), (s*.94, -1.4, -.65),
                    (s*1.04, -1.9, -1.1)], motion=('fin', s*.11))
    elif name == 'crab':
        r = Rig(name, (0, -.05, .5))
        for s, side in [(-1, 'L'), (1, 'R')]:
            for i, y in enumerate([.17, -.29, -.50]):
                r.chain(f'leg_{i}_{side}', [(s*.45, y*.7, .49), (s*.81, y, .56),
                    (s*1.03, y-.08, .08)], motion=('crab_walk', (i+(s>0)) % 2))
            r.chain(f'claw_{side}', [(s*.39, .26, .45), (s*.57, .49, .31),
                    (s*.40, .74, .20)], motion=('claw', s*.065))
            r.chain(f'eye_{side}', [(s*.18, .38, .66), (s*.20, .48, .90)], motion=('head', .025))
    else:
        raise ValueError(name)
    return r


def skin_weights(r, p):
    x, y, z = p
    a = abs(x)
    n = r.name
    side = 'R' if x >= 0 else 'L'
    chain, strength = None, 0.0
    if n in ('ribbonwake', 'glider', 'stormglass'):
        thresholds = {'ribbonwake': (.56, 1.03), 'glider': (.12, .29), 'stormglass': (.38, .85)}
        lower, upper = thresholds[n]
        wing_gate = 1.0
        if n == 'glider':
            wing_gate = smooth(.03, .25, y)*smooth(-.36, -.12, z)
        elif n == 'stormglass':
            wing_gate = smooth(-.1, .5, y)*smooth(-1.05, -.45, z)
        if wing_gate and a > lower:
            candidates = [c for c in r.chains if c.startswith('wing') and c.endswith(side)]
            chain = min(candidates, key=lambda c: r.distance(c, p))
            strength = smooth(lower, upper, a)*wing_gate
        if strength < .1:
            if n == 'ribbonwake':
                chain, strength = 'tail', 1-smooth(.5, 1.15, y)
                if y > 1.9: chain, strength = 'head', smooth(1.9, 2.35, y)*.6
            elif n == 'glider':
                if y < .25: chain, strength = 'tail', 1-smooth(-.05, .27, y)
                elif z < -.17: chain, strength = f'leg_{side}', 1-smooth(-.38, -.17, z)
                elif y > .57: chain, strength = 'head', smooth(.57, .7, y)
            else:
                if y < .55: chain, strength = 'tail', 1-smooth(.0, .6, y)
                elif z < -.65: chain, strength = f'leg_{side}', 1-smooth(-.9, -.6, z)
                elif z > .25: chain, strength = 'head', smooth(.25, .6, z)*(1-smooth(.4, .65, a))
    elif n == 'lanternjaw':
        center_x = .1
        if y < .65:
            chain, strength = 'tail', 1-smooth(.05, .65, y)
        if z < -.18 and y > -.05 and abs(x-center_x) > .32:
            chain, strength = f'fin_{side}', smooth(.32, .6, abs(x-center_x))*(1-smooth(-.38, -.15, z))
        if y > 1.15: chain, strength = 'head', smooth(1.15, 1.55, y)
    elif n == 'tidebell':
        # Angularly isolated arm chains avoid bleeding between crossing arms.
        if z < 1.72 and math.hypot(x, y) > 1.05:
            chain = r.nearest('tentacle_', p)
            strength = (1-smooth(1.25, 1.78, z))*smooth(1.05, 1.65, math.hypot(x, y))
    elif n in ('orchard', 'basalt', 'brinecap'):
        cut = {'orchard': (1.52, .72, 1.35, -1.7),
               'basalt': (1.02, .50, 1.62, -.60),
               'brinecap': (.80, .25, .95, -.93)}[n]
        height, width, head, tail = cut
        if z < height and a > width:
            candidates = [c for c in r.chains if c.startswith('leg_') and c.endswith(side)]
            chain = min(candidates, key=lambda c: r.distance(c, p))
            strength = (1-smooth(height*.62, height, z))*smooth(width, width*1.45, a)
        if strength < .12:
            if y > head and z > height*.6:
                chain, strength = 'head', smooth(head, head+.45, y)
            elif y < tail and z < height*1.2:
                chain, strength = 'tail', 1-smooth(tail-.45, tail+.15, y)
    elif n == 'cumulus':
        # Buoyant white lobes and the planted back stay on the body bone.
        if y > .95 and a < .62:
            chain, strength = 'head', smooth(.95, 1.5, y)
        elif y > 1.0 and a > .65 and z < .65:
            chain, strength = f'fin_front_{side}', smooth(.6, 1.0, a)*(1-smooth(.30, .68, z))
        elif y < -.8 and a > .55 and z < .25:
            chain, strength = f'fin_back_{side}', smooth(.55, .85, a)*(1-smooth(-.3, .25, z))
        elif z < .0 and a < .7:
            chain, strength = 'tail', 1-smooth(-.55, .05, z)
    elif n == 'crab':
        if z < .62 and a > .43 and y < .39:
            candidates = [c for c in r.chains if c.startswith('leg_') and c.endswith(side)]
            chain = min(candidates, key=lambda c: r.distance(c, p))
            strength = smooth(.43, .67, a)*(1-smooth(.56, .65, z))
        if y > .27 and z < .57:
            chain, strength = f'claw_{side}', smooth(.26, .43, y)
        if y > .37 and z > .67 and a < .30:
            chain, strength = f'eye_{side}', smooth(.67, .82, z)
    if not chain or strength < .001:
        return {'body': 1.0}
    weights = {bone: w*strength for bone, w in r.weights(chain, p).items()}
    weights['body'] = 1-strength
    weights = {bone: value for bone, value in weights.items() if value > .0001}
    total = sum(weights.values())
    return {bone: value/total for bone, value in weights.items()}


def load_source(name):
    spec = importlib.util.spec_from_file_location('normalize_supplied', ROOT/'tools/import_supplied_models.py')
    normalizer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(normalizer)
    stem, _, yaw, axis, target, origin = next(s for s in normalizer.SPECS if s[1] == name)
    normalizer.reset()
    objects = normalizer.load(ROOT/'models'/f'{stem}+3d+model.glb')
    for obj in objects: obj.data.transform(Matrix.Rotation(math.radians(yaw), 4, 'Z'))
    lo, hi = normalizer.bounds(objects)
    scale = target/(hi-lo)[axis]
    for obj in objects: obj.data.transform(Matrix.Diagonal((scale, scale, scale, 1)))
    lo, hi = normalizer.bounds(objects)
    shift = Vector((-(lo.x+hi.x)/2, -(lo.y+hi.y)/2,
                    -lo.z if origin == 'base' else -(lo.z+hi.z)/2))
    for obj in objects:
        obj.data.transform(Matrix.Translation(shift))
        obj.name = name+'_mesh'
        obj['source_file'] = f'{stem}+3d+model.glb'
        obj['reviewed_forward'] = '-Z'
    normalizer.textures(objects, name, 1024)
    return objects


def make_armature(r, meshes):
    arm = bpy.data.objects.new(r.name+'_rig', bpy.data.armatures.new(r.name+'_skeleton'))
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name, head, tail, parent in r.bones:
        bone = arm.data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent: bone.parent = arm.data.edit_bones[parent]
        bone.use_deform = name != 'root'
    bpy.ops.object.mode_set(mode='OBJECT')
    influenced = {name: 0 for name, *_ in r.bones}
    for mesh in meshes:
        groups = {name: mesh.vertex_groups.new(name=name) for name, *_ in r.bones if name != 'root'}
        weights = smooth_skin(mesh, r)
        for vertex in mesh.data.vertices:
            for bone, value in weights[vertex.index].items():
                groups[bone].add([vertex.index], value, 'REPLACE')
                if value > .05: influenced[bone] += 1
        mod = mesh.modifiers.new('Anatomical skin deformation', 'ARMATURE')
        mod.object = arm
        mesh.parent = arm
    arm['rig_notes'] = 'Deforming skin, anatomical landmarks, basic looping idle and locomotion.'
    return arm, influenced


def smooth_skin(mesh, r):
    # Three light graph-smoothing passes soften branch boundaries without
    # altering the supplied topology. UV seam duplicates share one weight
    # result, so moving joints cannot open cracks along texture seams.
    keys, groups, mapping = {}, [], []
    for vertex in mesh.data.vertices:
        key = tuple(round(c, 5) for c in vertex.co)
        if key not in keys:
            keys[key] = len(groups)
            groups.append(skin_weights(r, vertex.co))
        mapping.append(keys[key])
    neighbors = [set() for _ in groups]
    for edge in mesh.data.edges:
        a, b = [mapping[i] for i in edge.vertices]
        if a != b:
            neighbors[a].add(b)
            neighbors[b].add(a)
    for _ in range(3):
        updated = []
        for i, own in enumerate(groups):
            near = neighbors[i]
            if not near:
                updated.append(own)
                continue
            result = {bone: value*.65 for bone, value in own.items()}
            for j in near:
                for bone, value in groups[j].items():
                    result[bone] = result.get(bone, 0)+value*.35/len(near)
            kept = sorted(result.items(), key=lambda pair: -pair[1])[:4]
            kept = [(bone, value) for bone, value in kept if value > .0001]
            total = sum(value for _, value in kept)
            updated.append({bone: value/total for bone, value in kept})
        groups = updated
    return [groups[i] for i in mapping]


def rotation(arm, name, world_axis, angle):
    bone = arm.pose.bones[name]
    axis = bone.bone.matrix_local.to_quaternion().inverted() @ Vector(world_axis)
    bone.rotation_mode = 'QUATERNION'
    bone.rotation_quaternion = Quaternion(axis, angle)


def animate(r, arm):
    scene = bpy.context.scene
    scene.render.fps = 30
    arm.animation_data_create()
    actions = {}
    for clip in ('idle', LOCOMOTION[r.name]):
        idle = clip == 'idle'
        duration = 90 if idle else 48 if clip == 'walk' else 60 if clip == 'swim' else 36
        scene.frame_start, scene.frame_end = 0, duration
        arm.animation_data.action = None
        action = bpy.data.actions.new(clip)
        arm.animation_data.action = action
        for frame in range(0, duration+1, 2):
            phase = frame/duration*math.tau
            for pb in arm.pose.bones:
                pb.location = (0, 0, 0)
                pb.rotation_mode = 'QUATERNION'
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.scale = (1, 1, 1)
            rotation(arm, 'body', (1, 0, 0), math.sin(phase)*(.006 if idle else .012))
            for chain, (kind, amount) in r.motion.items():
                bones = r.chains[chain]
                for j, bone in enumerate(bones):
                    amplitude = amount*(.22 if idle else 1)
                    offset = j*.45
                    axis = (0, 0, 1)
                    if kind == 'wing':
                        axis = (0, 1, 0)
                        offset += .35 if 'lower' in chain else 0
                        amplitude *= 1 if j == 0 else .32
                    elif kind == 'tail':
                        amplitude *= 1+j*.15
                    elif kind == 'fin':
                        axis = (0, 1, 0)
                        amplitude *= 1 if j == 0 else .35
                    elif kind == 'dangle':
                        axis = (1, 0, 0)
                    elif kind in ('walk', 'crab_walk'):
                        amplitude = (.008 if idle else .16 if r.name == 'orchard' else .21)
                        offset = amount*math.pi
                        axis = (1, 0, 0) if kind == 'walk' else (0, 1, 0)
                        if kind == 'crab_walk' and chain.endswith('L'): amplitude *= -1
                        if j: amplitude *= -.65
                    elif kind == 'tentacle':
                        offset += int(chain.split('_')[-1])*math.pi/2
                        head = next(a for n, a, _, _ in r.bones if n == bone)
                        axis = (-head.y, head.x, 0)
                    elif kind == 'head':
                        axis = (0, 0, 1)
                        amplitude *= .5 if j else 1
                    elif kind == 'claw':
                        axis = (0, 0, 1)
                    rotation(arm, bone, axis, math.sin(phase-offset)*amplitude)
            for pb in arm.pose.bones:
                if pb.name == 'root': continue
                pb.keyframe_insert(data_path='rotation_quaternion', frame=frame, group=pb.name)
        # glTF's named NLA-track export produces stable clip names in Godot.
        track = arm.animation_data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, 0, action)
        strip.action_frame_start, strip.action_frame_end = 0, duration
        track.mute = True
        actions[clip] = (action, duration)
    arm.animation_data.action = None
    scene.frame_set(0)
    return actions


def evaluated_points(meshes):
    graph = bpy.context.evaluated_depsgraph_get()
    return [o.matrix_world@v.co for mesh in meshes
            for o in [mesh.evaluated_get(graph)] for v in o.data.vertices]


def verify_and_render(r, arm, meshes, actions):
    scene = bpy.context.scene
    action, duration = actions[LOCOMOTION[r.name]]
    arm.animation_data.action = action
    scene.frame_set(0)
    for pb in arm.pose.bones: pb.rotation_quaternion = (1, 0, 0, 0)
    bpy.context.view_layer.update()
    rest = evaluated_points(meshes)
    lo = Vector(tuple(min(p[i] for p in rest) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in rest) for i in range(3)))
    center = (lo+hi)/2
    extent = max(hi-lo)
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x = 600
    scene.render.resolution_y = 600
    scene.render.resolution_percentage = 100
    scene.display.shading.color_type = 'TEXTURE'
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.background_type = 'WORLD'
    scene.world = bpy.data.worlds.new('RigVerificationWorld')
    scene.world.color = (.14, .17, .20)
    scene.view_settings.view_transform = 'Standard'
    cam = bpy.data.objects.new('RigVerificationCamera', bpy.data.cameras.new('RigVerificationCamera'))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = extent*1.35
    cam.location = center+Vector((.50, 1, .35)).normalized()*extent*4
    cam.rotation_euler = (center-cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = str(QA/f'{r.name}_rest.png')
    bpy.ops.render.render(write_still=True)
    measurements = []
    for fraction in (.25, .50, .75):
        scene.frame_set(int(duration*fraction))
        pose = evaluated_points(meshes)
        distances = [(a-b).length for a, b in zip(rest, pose)]
        measurements.append({'phase': fraction, 'max_vertex_displacement': max(distances),
                             'moved_vertices': sum(d > .002 for d in distances)})
        scene.render.filepath = str(QA/f'{r.name}_pose_{int(fraction*100)}.png')
        bpy.ops.render.render(write_still=True)
    if max(m['max_vertex_displacement'] for m in measurements) < .01:
        raise RuntimeError(f'{r.name}: no meaningful mesh deformation')
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
    bpy.data.objects.remove(cam, do_unlink=True)
    return measurements


def main():
    args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else IDS
    selected = args or IDS
    unknown = set(selected)-set(IDS)
    if unknown: raise ValueError(f'Unknown creature IDs: {unknown}')
    QA.mkdir(parents=True, exist_ok=True)
    records = []
    for name in selected:
        meshes = load_source(name)
        r = profile(name)
        arm, influenced = make_armature(r, meshes)
        actions = animate(r, arm)
        measurements = verify_and_render(r, arm, meshes, actions)
        bpy.ops.object.select_all(action='DESELECT')
        for obj in [arm]+meshes: obj.select_set(True)
        bpy.context.view_layer.objects.active = arm
        for track in arm.animation_data.nla_tracks: track.mute = False
        bpy.ops.export_scene.gltf(filepath=str(OUT/f'{name}.glb'), export_format='GLB',
            use_selection=True, export_yup=True, export_apply=False,
            export_animations=True, export_animation_mode='NLA_TRACKS',
            export_force_sampling=True, export_frame_range=False,
            export_skins=True, export_all_influences=False,
            export_cameras=False, export_lights=False, export_extras=True,
            export_image_format='JPEG', export_jpeg_quality=88)
        record = {'id': name, 'bones': len(r.bones), 'animations': list(actions),
            'weighted_vertices_by_bone': influenced, 'deformation_checks': measurements,
            'triangles': sum(sum(len(p.vertices)-2 for p in m.data.polygons) for m in meshes),
            'vertices': sum(len(m.data.vertices) for m in meshes),
            'bytes': (OUT/f'{name}.glb').stat().st_size}
        (QA/f'{name}_rig.json').write_text(json.dumps(record, indent=2)+'\n')
        records.append(record)
        print('RIGGED', name, len(r.bones), list(actions), flush=True)
    manifest_path = OUT/'manifest.json'
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        by_id = {r['id']: r for r in records}
        for asset in manifest['assets']:
            if asset['id'] not in by_id: continue
            record = by_id[asset['id']]
            asset.update({k: record[k] for k in ('animations', 'triangles', 'vertices', 'bytes')})
            asset['rigged'] = True
            asset['bones'] = record['bones']
            asset['notes'] = 'Skinned anatomical rig with basic idle and locomotion loops; source mesh and atlas preserved.'
        manifest_path.write_text(json.dumps(manifest, indent=2)+'\n')


if __name__ == '__main__':
    main()
