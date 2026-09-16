# Original environmental kit

These eight original models were authored in an isolated Blender 5.2.2 background process by `tools/world/build_nature.py`. The script and packed source scene are retained under `tools/world/` (excluded from automatic Godot source import). Existing user Blender objects were not modified.

* Wind-pruned tree and mangrove with layered, irregular foliage masses.
* Three faceted coastal cliff/crag variants.
* Kelp fan, amber branch coral and shoal seagrass.

Their shared generated nature atlas is `assets/textures/nature-atlas.png`; GLBs carry UVs, textured PBR materials and vertex colors. Runtime MultiMeshes share the atlas, with collision for trunks/coastal rocks and reserved path/POI/waterfall clearance. Source `.blend` and GLBs are original project assets, not third-party downloads.
