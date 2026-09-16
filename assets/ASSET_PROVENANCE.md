# Original Spellwake model assets

The 19 GLBs in `assets/models` were modeled in Blender for this project from the approved `preproduction/art` boards. They are original geometry, not downloaded asset-library content. The retained generator is `tools/build_assets.py`; editable Blender source is `assets/models/source/spellwake-source.blend`.

## Sources and workflow

- Shape references: `01-wizard.png`, `02-shopkeeper.png`, `03-boat.png`, `04-starter-island.png`, `05-buildings.png`, `13-kettleback.png`, and `19-threadwing.png` from this project's approved concept art.
- Surface texture: `assets/textures/style-atlas.png`, generated for this project with the image-generation tool, with timber, canvas, ivory stone and weathered blue-painted timber quadrants. Texture is embedded in each GLB. UVs use continuous plank grain; the wizard coat and creature shell use smaller painted patches of the atlas.
- External asset downloads were not authorized and were not used. `FAL_KEY` and `FAL_API_KEY` were absent in the session, so Fal image-to-3D was unavailable. The local RTX 3060 Laptop has 6 GB VRAM; no local diffusion or unverified image-to-3D workflow was run.
- Blender MCP's addon-status and scene-info requests both returned a connection error. Actual installed Blender was located at `D:/Games/steamapps/common/Blender/blender.exe`. All production was done in an isolated background Blender process and a new scene; no existing user scene was edited. The completed build reports Blender 5.2.2 LTS.
- No third-party model licenses or paid API calls apply to these original assets. Blender itself is separately licensed by its authors; using Blender does not place its GPL license on the exported art.

## Runtime interface

All units are metres, with Godot Y up and forward -Z. There are no baked collisions or skeleton animations: the game supplies simplified collision, simulation and interaction markers. Geometry is merged by material to bound draw calls.

| File | Origin / use |
| --- | --- |
| `boat.glb` | Waterline at Y=0; deck Y=1.10. Broad rounded hull is about14 m long by6.7 m wide. Bow extends to Z=-7.90; mast Y=10.46. Open stern, waist-height helm centered(0,2.13,3.49), low canvas windbreak, rigging, map table, lamps, shell fenders and brass foci. Port boarding ladder is X=-3.48,Z=1.37–2.03,Y=-0.95–1.65. |
| `boat_sail.glb` | Same origin as boat; separate billowed triangular sail with a blue spiral on both faces. Parent at zero offset. Canvas runs from mast(0,3.18–9.71,0.11) to clew(4.35,2.78,-3.87). Suggested approximate sail collider center(2.15,6,-1.9), Y rotation0.724, size(5.8,6.6,0.55). |
| `wizard.glb` | Feet Y=0, facing -Z. Includes belt spellbook and held staff; hat reaches Y=2.27. |
| `wizard_cast.glb`, `wizard_helm.glb`, `wizard_green.glb`, `wizard_rust.glb` | Showcase/crew variants: raised staff pose, both hands extended toward helm, green and rust cloth palettes. Same feet origin. Casting staff tip reaches Y=2.73. Cloth is generated canvas multiplied by a palette tint, preserving its texture. |
| `shopkeeper.glb` | Feet Y=0, facing -Z; silver curls, glasses, apron, keys. |
| `staff.glb` | Butt of staff at Y=0; tip Y=1.91. Separate asset for first-person view or item display. |
| `lighthouse.glb` | Ground Y=0; height14.35 m; radius roughly2.18 m. Door faces -Z. |
| `shop.glb` | Ground Y=0; approximately8.8 m wide,8 m tall. Shopfront faces -Z; awning extends to Z=-4.65. |
| `dock.glb` | Deck top Y=0.35; planks span X+-2.1,Z+-4.15. Pilings extend to Y=-2.16. |
| `crab.glb` | Kettleback crab; ground Y=0, front -Z, height1.25 m. |
| `glider.glb` | Threadwing skater; centre near origin, forward -Z; wingspan3.4 m. |
| `tree.glb` | Coastal tree; ground Y=0, height5.19 m. |
| `hearthstone.glb` | Brass armillary and aether crystal; ground Y=0, height1.91 m. |
| `barrel.glb` | Ground Y=0, height0.95 m. |
| `ruin_arch.glb` | Ground Y=0, height4.59 m, arch opening along Z. |
| `loot_chest.glb` | Base Y=0, height0.88 m; center at X/Z=0. |

## Rebuild and verification

```powershell
& 'D:\Games\steamapps\common\Blender\blender.exe' --background --python tools/build_assets.py -- --qa
```

Optional asset names after `--` limit a build (for example `boat` or `wizard`). A full build regenerates all19 models and `asset-manifest.json`; `--qa` also renders four studio review images. Render output and logs live beside the GLBs. The `source` directory has `.gdignore` so Godot does not invoke Blender to import the retained source document.

All19 GLBs passed binary header/length, JSON, mesh, POSITION/NORMAL/TEXCOORD_0, embedded buffer and default-scene contamination checks. Detailed results: `assets/models/glb-validation.json`. `asset-manifest.json` records mesh counts, triangle counts and bounds.

Four actual Blender renders were inspected: boat, wizard, shop and crab. The revision loop corrected isolated-scene export, continuous timber UVs, character shirt/eye proportions, the roof tile silhouette, biological shell sampling, and the painted sail spiral. These images are asset reviews, not screenshots of the game. These first-pass static models remain deliberately modest in polygon count; advanced skeletal animation and production LODs are later asset work.

After the first live Godot comparison, the boat was remodeled against the actual stern camera: the obstructing cabin was removed, the hull broadened and rounded, the sail became triangular with its emblem on both faces, and four posed/colored wizards were exported. Creature runtime animation uses small shader vertex deformations for crab steps and wing flaps; it does not claim to be a finished skeletal animation set.
