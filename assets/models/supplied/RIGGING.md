# Supplied creature rigs

All ten supplied creatures have a real skinned skeleton and two looping clips.
Their original mesh topology, UVs and painted textures are retained; the
normalization pass reduces the texture atlas to 1024 pixels. The rigs are built
from inspected anatomical landmarks, with up to four normalized bone weights
per vertex and a light topology smoothing pass at joint boundaries.

These are basic animation rigs for the current game. They do not include
inverse kinematics, foot locking, facial animation, attack/death clips or a
humanoid retargeting contract. The original generated surfaces have not been
retopologized for extreme poses. Use the included restrained movement range
as the starting point for additional animation work.

| Asset | Skin joints | Locomotion clip | Moving anatomy |
| --- | ---: | --- | --- |
| `ribbonwake.glb` | 15 | `swim` | Four fins and a four-segment tail |
| `glider.glb` | 18 | `fly` | Four wings, tail, head and hanging legs |
| `stormglass.glb` | 17 | `fly` | Three-bone wings, tail, neck/head and legs |
| `lanternjaw.glb` | 10 | `swim` | Body/tail chain, head and paired fins |
| `tidebell.glb` | 26 | `swim` | Eight three-bone tentacles below the rigid shell |
| `orchard.glb` | 14 | `walk` | Four legs, head/neck and tail; planted shell retained |
| `basalt.glb` | 18 | `walk` | All six legs, head and articulated tail |
| `brinecap.glb` | 13 | `walk` | Four legs, head and tail |
| `cumulus.glb` | 16 | `fly` | Four flippers, head and four-segment tail |
| `crab.glb` | 20 | `walk` | Six legs, two claw arms and eye stalks |

Joint totals include one nondeforming hierarchy root. Every other joint has
weighted vertices. Each file also contains `idle`. Idle lasts 3 seconds;
walking lasts 1.6 seconds, swimming 2 seconds and flying 1.2 seconds. All clips
start at zero and have matching mesh positions at the loop endpoints. The
runtime should loop clips and control position, heading and movement speed;
the clips contain no root travel.

## Rebuild and verify

Run these commands from the repository root in an isolated Blender process:

```powershell
& 'D:/Games/steamapps/common/Blender/blender.exe' --background --factory-startup --threads 3 --python tools/rig_supplied_creatures.py
& 'D:/Games/steamapps/common/Blender/blender.exe' --background --factory-startup --threads 3 --python tools/verify_supplied_rigs.py
```

Optional IDs after `--` select particular creatures for the first command.
The rigging script reads the untouched `models/` sources and reuses the
normalization specification, so it can rebuild the derived rigged GLBs even
after their original static intermediates have been replaced. It updates
only the selected creature entries in `manifest.json`.

The second command reimports the delivered GLBs and verifies skin attributes,
normalized weights, nonempty deformation joints, finite animated coordinates,
actual mesh motion and matching loop endpoints for both clips. Its checked
counts, durations and deformation measurements are in `rig-report.json`.
Per-source triangle counts remain 9,766–11,150; rigging introduces no triangles.

Rest, quarter-cycle, half-cycle and three-quarter-cycle images are written to
`tmp/model-intake/rigs/`. These poses were visually reviewed for every creature.
The sheets `deformation_wings.jpg`, `deformation_water.jpg` and
`deformation_land.jpg` show the corresponding poses together. The numeric
edge-length measurements in the report help identify small weight-transition
hotspots when extending the animations; they are not a claim that arbitrary
new poses will be artifact-free.

Godot imports the skin as a `Skeleton3D` and the named clips through an
`AnimationPlayer`; the runtime integration discovers the player recursively.
The GLBs retain their painted materials and do not use the legacy procedural
creature deformation shader.

Godot 4.7.2 reimport and `tests/supplied_models_test.gd` passed for all ten
species with zero failures. Within an instantiated asset, the paths are
`<asset_id>_rig/Skeleton3D` and `AnimationPlayer`. Actor initialization sets
both clips to `Animation.LOOP_LINEAR`; the runtime check advances every clip
by 2.25 durations and verifies that playback continues with a wrapped timeline.
The runtime validation record is `tests/supplied-model-validation.md`.
