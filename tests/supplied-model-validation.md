# Supplied model integration validation

Validated on 2026-09-29 with Godot 4.7.2 stable on Windows. The rendered pass used Vulkan Forward+ on an NVIDIA GeForce RTX 3060 Laptop GPU at 1280×853. FPS was not measured.

Run from the repository root with `C:\Users\nieuw\Documents\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe`:

| Command arguments | Result |
| --- | --- |
| `--headless --editor --path . --quit` | Final rig/asset reimport exited 0. |
| `--headless --path . --script tests/supplied_models_test.gd` | 10 species, 0 failures. All ten imports contain a mesh, `Skeleton3D`, and `AnimationPlayer`; all ten species spawn as live actors across day/night. Idle and movement clips are `LOOP_LINEAR` and stayed active after advancing 2.25 clip lengths. Placed module names and core prop paths resolved. A physics ray hits the new stern cabin blocker; the port helm lane ray and full wizard capsule remain clear. |
| `--headless --path . --script tests/rules_test.gd` | 121 assertions, 0 failures. |
| `--headless --path . --script tests/world_test.gd` | 0 failures. |
| `--headless --path . --script tests/creature_manager_test.gd` | 0 failures. |
| `--headless --path . --script tests/gameplay_test.gd` | 21 assertions, 0 failures, including boarding, helm control, sail impact, moving deck, shop interaction, and waterfall exits. |
| `--path . --script tests/supplied_visual.gd` | Rendered main scene and wrote the images below; exited 0. |

The rig imports have the shape `Creature_<spawn_id>/<asset_id>/<asset_id>_rig/Skeleton3D` with a sibling `Creature_<spawn_id>/<asset_id>/AnimationPlayer`. For example, Threadwing uses `.../glider/glider_rig/Skeleton3D` and `.../glider/AnimationPlayer`. The imported clips are `idle` plus `walk`, `swim`, or `fly` as appropriate.

Rendered captures from the full main scene are under `tmp/model-intake/`: `runtime-harbour-ship.png`, `runtime-helm-playable.png`, `runtime-hull-waterline.png`, `runtime-harbour-shop.png`, `runtime-rootwatch-kit.png`, `runtime-tide-kit.png`, `runtime-threadwing.png`, `runtime-cumulus.png`, `runtime-tidebell-underwater.png`, and `runtime-crab.png`. The helm capture uses the same boat node without title-screen preview crew. The shop capture includes the NPC approach; the Tidebell capture uses the actual spawned aquatic actor and world water/terrain. Parent review accepted Tide Vault, sky-spawn separation, Rootwatch, helm, shop, and underwater placement after corrections.

Selected accepted captures are also preserved in `output/model-intake/`: the playable helm, harbour shop, sky creatures and underwater Tidebell.

The smoke and visual scripts construct fresh `WorldState` instances in memory; they do not load or write player saves. The visual script writes PNG evidence only in ignored `tmp/model-intake/`. The generated archipelago still emits an existing `instance_reset_physics_interpolation()` deprecation warning. Creature combat uses body-centered prototype hitboxes and the existing simple shared movement/interaction logic. A live 18-player multiplayer load test and FPS benchmark were not performed.
