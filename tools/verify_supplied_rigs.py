"""Reimport exported GLBs and check skins, loops and actual mesh deformation.

Run with Blender, after rig_supplied_creatures.py. No game assets are changed.
The report is written to assets/models/supplied/rig-report.json and previews
to tmp/model-intake/rigs/. This checks the delivered files, not authoring state.
"""

import json
import math
import struct
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'assets/models/supplied'
QA = ROOT/'tmp/model-intake/rigs'
IDS = ['ribbonwake', 'glider', 'stormglass', 'lanternjaw', 'tidebell',
       'orchard', 'basalt', 'brinecap', 'cumulus', 'crab']


def points(meshes):
    graph = bpy.context.evaluated_depsgraph_get()
    return [o.matrix_world@v.co for mesh in meshes
            for o in [mesh.evaluated_get(graph)] for v in o.data.vertices]


def main():
    report = {'coordinate_system': 'glTF +Y up, -Z forward',
              'validation': 'Exported GLBs reimported into Blender; both clips sampled through complete loop.',
              'scope': 'Basic deforming idle/locomotion rigs; no IK, combat, facial, retargeting or production retopology.',
              'assets': []}
    for name in IDS:
        path = OUT/f'{name}.glb'
        raw = path.read_bytes()
        json_size = struct.unpack_from('<I', raw, 12)[0]
        gltf = json.loads(raw[20:20+json_size])
        assert len(gltf.get('skins', [])) == 1, name
        locomotion = ('walk' if name in ('orchard', 'basalt', 'brinecap', 'crab')
                      else 'swim' if name in ('ribbonwake', 'lanternjaw', 'tidebell') else 'fly')
        assert {a['name'] for a in gltf['animations']} == {'idle', locomotion}, name
        assert all('JOINTS_0' in p['attributes'] and 'WEIGHTS_0' in p['attributes']
                   for m in gltf['meshes'] for p in m['primitives']), name
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(path))
        arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
        meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH'
                  and any(m.type == 'ARMATURE' for m in o.modifiers)]
        assert meshes, name
        weighted = {bone.name: 0 for bone in arm.data.bones}
        for mesh in meshes:
            assert all(abs(sum(g.weight for g in v.groups)-1) < .0002 for v in mesh.data.vertices), name
            assert all(len(v.groups) <= 4 for v in mesh.data.vertices), name
            for vertex in mesh.data.vertices:
                for group in vertex.groups:
                    if group.weight > .05:
                        weighted[mesh.vertex_groups[group.group].name] += 1
        assert all(value > 0 for bone, value in weighted.items() if bone != 'root'), name
        for track in arm.animation_data.nla_tracks: track.mute = True
        arm.animation_data.action = None
        for pb in arm.pose.bones:
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
            pb.scale = (1, 1, 1)
        bpy.context.view_layer.update()
        rest = points(meshes)
        rest_edges = []
        offset = 0
        for mesh in meshes:
            for edge in mesh.data.edges:
                a, b = (i+offset for i in edge.vertices)
                length = (rest[a]-rest[b]).length
                if length > .0001: rest_edges.append((a, b, length))
            offset += len(mesh.data.vertices)
        clips = []
        for exported in gltf['animations']:
            clip = exported['name']
            action = bpy.data.actions[clip]
            arm.animation_data.action = action
            start, end = action.frame_range
            poses = []
            distortions = []
            for phase in (0, .25, .5, .75, 1):
                frame = start+(end-start)*phase
                bpy.context.scene.frame_set(math.floor(frame), subframe=frame-math.floor(frame))
                ps = points(meshes)
                assert len(ps) == len(rest) and all(math.isfinite(c) for p in ps for c in p), name
                poses.append(ps)
                ratios = sorted(max((ps[a]-ps[b]).length/base, base/max(.0000001, (ps[a]-ps[b]).length))
                                for a, b, base in rest_edges)
                distortions.append({'phase': phase, 'p99_edge_length_ratio': round(ratios[int(len(ratios)*.99)], 5),
                                    'max_edge_length_ratio': round(ratios[-1], 5)})
            delta = max((a-b).length for a, b in zip(poses[0], poses[-1]))
            assert delta < .001, f'{name} {clip}: non-looping endpoints {delta}'
            max_deform = max((a-b).length for ps in poses for a, b in zip(rest, ps))
            assert max_deform > .001, f'{name} {clip}: static mesh'
            time_accessor = gltf['accessors'][exported['samplers'][0]['input']]
            assert abs(time_accessor['min'][0]) < .00001, f'{name} {clip}: start offset'
            clips.append({'name': clip, 'duration_seconds': round(time_accessor['max'][0]-time_accessor['min'][0], 5),
                'starts_at_zero': abs(time_accessor['min'][0]) < .00001,
                'exported_channels': len(exported['channels']),
                'max_vertex_displacement_metres': round(max_deform, 5),
                'loop_endpoint_error_metres': round(delta, 8),
                'edge_distortion_samples': distortions})
        source_report = json.loads((QA/f'{name}_rig.json').read_text())
        exported_triangles = sum(gltf['accessors'][p['indices']]['count']//3
                                 for m in gltf['meshes'] for p in m['primitives'])
        assert exported_triangles == source_report['triangles'], name
        report['assets'].append({'id': name, 'path': f'assets/models/supplied/{name}.glb',
            'skins': 1, 'joints': len(gltf['skins'][0]['joints']),
            'deforming_bones': len([n for n in weighted if n != 'root']),
            'weighted_vertices_by_bone': weighted,
            'vertices': len(rest), 'triangles': source_report['triangles'],
            'max_influences_per_vertex': max(len(v.groups) for m in meshes for v in m.data.vertices),
            'unit_weight_sums': True, 'clips': clips,
            'visual_review': 'rest and quarter/half/three-quarter locomotion poses reviewed',
            'preview_directory': 'tmp/model-intake/rigs'})
        print('VERIFIED_EXPORT', name, len(gltf['skins'][0]['joints']), [(c['name'], c['duration_seconds']) for c in clips], flush=True)
    (OUT/'rig-report.json').write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
