# Aquatic cast

Original authored Blender geometry based on approved sheets 12, 14 and 15. All assets face Godot **-Z**, use metres, and have their origin at the body centre (Tidebell: mantle waterline). Generated `style-atlas.png` is embedded with cropped UVs and explicit PBR colour factors. No paid service, downloaded mesh or live Blender scene was used.

| Model | Distinguishing anatomy | Runtime mesh surfaces |
|---|---|---|
| `ribbonwake.glb` | Four separate petal fins, ivory filter fan, curled ribbon tail | 11 |
| `lanternjaw.glb` | Long seal body, two flippers, tail, expandable luminous amber throat with pleats | 12 |
| `tidebell.glb` | Ivory spiral bell, turquoise bands, gold pleated mantle, exactly six heavy arms and sucker rows | 13 |

Each GLB is a single mesh, with a single embedded atlas image. Source anatomical parts remain separate in `source/aquatic-cast.blend`. The source directory has `.gdignore`, avoiding automatic Blender imports and QA texture imports. `source/*-three_quarter.png`, `*-side.png`, and `*-top.png` are actual isolated Blender renders inspected during QA. `manifest.json` records geometry counts and bounds.

Rebuild with `D:/Games/steamapps/common/Blender/blender.exe --background --python tools/build_aquatic.py`. The builder repairs a Blender 5.2 exporter omission of constant MixRGB factors by writing standard glTF baseColorFactor metadata. It does not change bitmap pixels. It also collapses duplicate texture references.

## Integration

Add the three `res://assets/models/aquatic/<species>.glb` paths to the creature model dictionary. Existing catalogue keys already match their names and provide domain, biome, hours and loot. Ribbonwake is daytime Sunlit Shoals fauna; Lanternjaw is nocturnal Kelp Channels/Lantern Trench fauna; Tidebell is the Lantern Trench `tide_vault` boss.

Tidebell spans approximately 13m wide by 14.2m long. Its mantle origin has a shell rising 7.05m and arms extending 4.80m below. Keep at least five metres of seabed clearance. A root depth around 1.5m shows its shell above water for the long-distance silhouette; underwater encounters can put it deeper. Use a broad body collision (about 4.4m radius), rather than the normal creature capsule. Detection and melee reach also need boss-specific dimensions. Creature motion shaders must preserve StandardMaterial3D albedo texture/factor and emission; vertex colour is not required.

Ribbonwake supports lateral fin flutter based on absolute local X. Lanternjaw can sway its tail using positive Godot Z behind the body. Tidebell can sway arms using negative local Y below its mantle while keeping the shell still. These assets supply geometry/materials; ecology, spawning and combat remain in the manager.
