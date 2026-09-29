# Supplied model intake

The 23 original GLBs in `models/` are preserved byte for byte. These exports
were identified by rendered views from four angles and compared with
`preproduction/model-references/prompts.json` and its approved reference images.
The source filename alone is not treated as a subject identification.

## Source identities

| Original basename (all end in `+3d+model.glb`) | Export / identified subject |
| --- | --- |
| `stylized+crab` | `crab` — Kettleback Crab |
| `blue+manta+ray` | `ribbonwake` — Ribbonwake Glider |
| `blue+patterned+fish` | `lanternjaw` — Lanternjaw Skulker |
| `blue+phoenix` | `stormglass` — Stormglass Roc |
| `fantasy+sea+creature` | `tidebell` — Tidebell Colossus |
| `flying+fantasy+creature` | `glider` — Threadwing Skater |
| `giant+turtle` | `orchard` — Orchard Reliquary |
| `rock+plated+reptile` | `basalt` — Basalt Knuckler |
| `stegosaurus` | `brinecap` — Brinecap Browser |
| `turtle+creature` | `cumulus` — Cumulus Grazer |
| `lantern` | `lantern` — harbour lantern |
| `medieval+door` | `tide_gate` — Tide Vault entrance |
| `orb+pedestal` | `hearth_pad` — Hearthharbour return anchor |
| `stone+arch` | `ruin_arch` — ancient coastal arch |
| `stone+cottage` | `cottage` — fisher-wizard cottage / matching harbour shop design |
| `treasure+chest` | `loot_chest` — floating loot chest |
| `wooden+barrel` | `barrel` |
| `wooden+crate` | `crate` |
| `wooden+dock` | `dock` — short dock module |
| `ship` | `boat_hull` — Spellwake Sloop hull, supplied without mast or sail |
| `ancient+ruins` | `tide_kit` — multi-object ruins kit |
| `modular+environment+elements` | `coastal_kit` — multi-object coastal kit |
| `stone+ruin+archway` | `root_kit` — multi-object root/ruin kit |

The last three files contain spread-out asset boards in 3D. They are not single
arches. Each library retains its layout while exposing centered, named child
meshes. Use the child modules, rather than placing the complete kit in the world.
`manifest.json` records each child node's local bounds and source provenance.
Children share one embedded texture per kit. Reset a selected child's position
when placing it independently. `review_fragments` is preserved for inspection
and excluded from world placement.

## Normalization and preparation

- Units are metres, with +Y up and -Z forward. Mesh transforms are baked.
- Ground objects have their base at Y=0. Flying/swimming creatures are centered
  vertically, except the seabed-standing Tidebell, whose lowest arm is at Y=0.
  Aquatic placement must account for each complete bounding box. Dock Y=0 is
  the deck surface; legs extend below the origin.
- Original UVs and painted albedo are retained. Supplied 4096 textures are
  reduced to 1024 for ordinary props/creatures and 2048 for the hull, cottage,
  and shared kit atlases. Painted surfaces use roughness 0.82 and metallic 0.
- Source triangle counts are already modest (roughly 10,000 per file).
  Silhouettes were preserved rather than applying indiscriminate decimation.
- The hull is fitted to a 6.2 m beam, 13.234 m length and the existing deck at
  Y=1.18. Its vertical profile is adjusted separately to fit the playable boat.
- `boat_rig.glb` is a subset of the existing `assets/models/boat.glb`: mast,
  boom, shrouds, ratlines, pennant and helm. The forestay endpoint is fitted to
  the supplied bow. Combine hull and rig with the existing `boat_sail.glb`.
  No new boat design or replacement texture was generated.

The supplied originals contain no skeletons or animations. Creature rigging is
a separate derived-asset pass; consult the final rig report and each manifest
record for the actual clips. These imported creatures must keep their painted
materials; the old mesh-coordinate deformation shader is not appropriate.

## Reproduction and evidence

Run from the repository root in a separate background Blender process:

```powershell
& 'D:/Games/steamapps/common/Blender/blender.exe' --background --factory-startup --threads 4 --python tools/import_supplied_models.py
```

The script never opens or changes the user's live Blender scene. It writes only
derived exports and scratch files. Optional IDs after `--` rebuild selected
assets, for example `-- boat_hull boat_rig`. Rebuilding creature IDs resets them
to normalized static inputs, so rerun the rigging pass afterwards.

Inspection evidence is under `tmp/model-intake/`: `sources_sheet_1.jpg` through
`sources_sheet_4.jpg`, per-source four-angle renders, normalized renders, kit
module sheets, source inventory and SHA256 hashes. All 23 originals passed a
post-export SHA256 check. `manifest.json` contains current export bounds,
triangle counts, sizes, source hashes and reference identities.

No supplied wizard, shopkeeper, lighthouse or separate sail exists in this
intake; their existing game assets remain necessary. Small reconstruction
imperfections and reduced detail on kit pieces are retained and documented;
the review does not claim production retopology or a new art approval.

## Kit curation

Separation uses whole physical components, linking duplicated glTF vertices at
UV/normal seams for selection without changing the UVs. This removed the first
pass's neighboring shards from the coastal column/rock and the small pillar
beside the open root arch. All original kit triangles remain represented in
the derived libraries; exclusions below apply to runtime placement only.

All ten Tide-kit modules are suitable as scenery. The coastal arch, two stone
pillars, rail, steps, bridge, moss and rock modules are suitable. The coastal
banner is held for review because a disconnected pole extends far beyond it.

The root wall relief (`root_arch`), open root arch (`root_growth`), low masonry
rail (`root_beam`), wall panel (`root_column`), steps (`root_steps`) and stone
bookshelf (`root_lintel`) are suitable scenery. These stable IDs describe the
spatial regions used during intake; the manifest's `subject` field supplies
the actual visual identity where the region name is imprecise.

The following root modules are retained for review and excluded from runtime:

- `root_branch`: disconnected leaves float above the branch.
- `root_tree`: root stump with an adjacent independent pedestal.
- `root_wall`: arch and detached column remain together.
- `root_floor`: two disconnected flat decorated panels.
- `root_panel`: a low-detail flat panel with no clear gameplay placement.
- `root_small_column`: partial, irregular root/pillar reconstruction.
- `root_door`: partial root stump with a cut end; it is not a door.
- `review_fragments`: unclassified residual fragments, where present.

`models/.gdignore` prevents Godot importing the untouched 4K originals; only
the prepared derivatives are used at runtime. Source hashes remain unchanged.
