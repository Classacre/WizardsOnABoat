# Procedural world and ocean validation

29 September 2026 · Godot 4.7.2 · Jolt Physics · Windows · RTX 3060 Laptop GPU.

## Implemented behavior

New save slots use generator version 2. Hearthharbour retains its authored layout and fixed terrain seed; other islands derive from the world seed, generator version and 480 m sector coordinates. Sector manifests choose occupancy, position, radius, height, ground or sky biome, shoreline variation and POI orientation. Terrain noise, graded paths and dungeon layouts then derive from the seed. Traversal order does not change an island. Sky islands keep their waterfall access.

Detailed islands stream around player and ship positions, with a target cap of 24 procedural islands; occupied dungeon sources consume this budget before surface candidates. Up to 80 simple horizon silhouettes extend visibility to 2.2 km. Their bounds include shader displacement so low viewing angles retain the island silhouettes. Terrain construction is split across frames. Ground collision uses a heightfield matching the 3 m visual grid; navigation regions do not attempt to connect across open sea. Repeated POI models and their immutable collision shapes are shared. Creatures materialize near active players/ships with a 96-actor cap; persistent mob records, rolled loot and deaths remain in the world state after their actors unload.

Generation is bounded to sector coordinates -200 through 200, rather than infinite. Physical traversal has been exercised over several kilometres, not at every extreme of that domain. Procedural dungeon interiors use an elevated, compact coordinate grid to avoid the precision failure found when interiors were first placed 200 km away. Height queries distinguish exterior terrain from elevated dungeon floors. Reconnecting inside a dungeon builds its source island and floor before positioning the player, including when the interior overlaps the starter island in X/Z.

Saved worlds store both seed and generator version. Old saves without version metadata load as version 1, preserving their original nine-island core while adding generated outer sectors. The main menu accepts signed 32-bit seeds, can randomize one, and lists saved worlds with their seed/version. Reusing a save name with a different seed returns an error before modifying progression. Pause and developer menus expose the active seed. Matching seed/version reproduces geography, not another world's inventory or progression.

The ocean now combines six seed-varied Gerstner components with different phases, directions and wavelengths, modulated by three broad moving wave groups. Rendering and CPU buoyancy use matching equations and analytic slopes close to the camera; distant geometry drops short waves that its coarse grid cannot resolve. Analytic per-pixel normals and procedural foam replace the rotated bitmap layers that produced blurred directional bands. See the subsequent [ocean visual validation](ocean-visual-validation.md) for current captures and measurements; the flight timings below predate this visual fix. This is a lightweight wave model, not a full spectral ocean simulation. Nearby procedural shores receive approximate shader shoreline patches; physical terrain queries remain exact to the sampled terrain.

## Functional checks

| Test | Result and coverage |
| --- | --- |
| `seed_slots_test.gd` | 21 checks, 0 failures: seed parsing, selection, save mismatch protection, versioned reload and future-version rejection. |
| `procedural_world_test.gd` | 0 failures: same-seed manifests, different-seed diversity, fixed starter, staged generation, distant collision/path support, dungeon connectivity, unload/revisit, bounded terrain maps and interior reconstruction. |
| `world_test.gd` | 0 failures: version-1 terrain, paths, dynamic detours, dungeons and waterfalls remain valid. |
| `ocean_wave_test.gd` | 0 failures: seed/time reproducibility, different-seed variation, CPU/shader uniform equation agreement, horizontal inversion, numerical-normal comparison and nearest-shore selection. |
| `creature_manager_test.gd` | 0 failures: streamed actor limits, unload/persistence, habitat/time rules and compact snapshot metadata retention. |
| `ui_layout_test.gd` | 0 failures: menu layout across viewport sizes, scrolling and host/client controls. |
| `rules_test.gd` | 121 assertions, 0 failures. |
| `gameplay_test.gd` | 21 assertions, 0 failures: physical starter walking, boarding, sailing, wind propulsion, death/respawn and all three legacy waterfall exits. |
| `procedural_expedition_test.gd` (headless) | 23 checks, 0 failures: seed 948321/v2, physical island and dungeon traversal beyond 3 km, reward/exit and isolated save/reload. |
| `procedural_expedition_test.gd -- --capture-procedural` (rendered, final Jolt run) | 29 checks, 0 failures: the expedition above plus physical jumping/landing and four saved captures. |
| `dungeon_enet_test.gd -- --procedural-world` | Host 15/15 and client 12/12: independently matching distant terrain and collision, authorized entry/reward/exit, rejected remote actions and same-identity reconnect. |

Full-scene tests disable automatic saves and use temporary in-memory identities. Explicit persistence tests use isolated files and remove their own fixtures. No existing player world was overwritten.

The two-peer ENet run warned about a 2,020-byte unreliable simulation packet exceeding the 1,392-byte MTU. The functional checks passed; packet loss and performance with 18 players remain unverified.

After switching physics engines, the legacy and procedural world suites, creature runtime suite, 21-assertion gameplay suite, two-peer procedural ENet pair, and rendered expedition were rerun successfully under Jolt. The seed/UI/domain and wave-equation suites passed before the physics-engine change; their results do not depend on contact resolution. `git diff --check` also passed. The remaining engine warning is Terrain3D's deprecated `instance_reset_physics_interpolation()` call.

## Rendered flight and remaining limits

The final [flight report](../output/procedural/procedural_flight_profile.json) records a 35-second developer flight at 120 m/s, with the boat left in harbour as a second streaming anchor. It travelled **4,194 m**, encountered **42 distinct procedural islands**, and observed **21 far islands** after passing 3 km. Active procedural terrain peaked at **24 islands** and live creatures at **15**. Streaming and stale-node/height-map/navigation cleanup assertions passed.

At 1280×854, 4,935 measured frame gaps had a **15.91 ms p95**, **23.90 ms p99**, and **213.99 ms maximum**. There were 10 gaps above 33 ms, five above 50 ms and two above 100 ms. This is evidence against the earlier multi-second freezes, not a claim of hitch-free exploration. First visits still include occasional model/physics initialization stalls. Scene construction took 8.28 seconds and entering the differently seeded host world another 5.64 seconds. Other Godot instances were stopped during this measurement. Benchmark PNG encoding is excluded from frame-gap statistics; automatic saves were disabled.

The [earlier run with heightfields and GodotPhysics3D](../output/procedural/flight-after-heightfields.json) travelled only 2,830 m during its 35 seconds, with 21 frame gaps above 100 ms and a 1,314 ms maximum. Instrumentation isolated the expensive calls to creature `move_and_slide()` against world collision, rather than navigation queries, animation or wave sampling. A temporary [collision-isolation experiment](../output/procedural/flight-no-world-collision-ablation.json) confirmed the cause; that override was removed. **Full world and boat collision remains enabled** in the final Jolt implementation.

Jolt is built into this engine, so no additional physics plugin is required. The [official Godot guide](https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html) documents the setting and collision differences; [Terrain3D's collision guidance](https://terrain3d.readthedocs.io/en/stable/docs/collision.html) discusses expensive enemy/terrain collision and alternative physics. The measured local comparison, followed by the movement/network regressions, determined this project's choice.

Visually reviewed captures: [seed menu](../output/procedural/seed-main-menu.png), [generated island beyond 3 km](../output/procedural/far-shore.png), [dungeon reward](../output/procedural/dungeon-reward.png), [open water beyond 4 km](../output/procedural/flight_end.png), and [near-water wave detail](../output/procedural/ocean-near.png). Horizon silhouettes intentionally use less detail than nearby islands. The ocean remains a lightweight seeded wave model and is not a fully non-repeating spectral simulation.

## Reproduction

Run from the repository root, substituting a test filename as needed:

```powershell
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/procedural_world_test.gd
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/procedural_expedition_test.gd -- --capture-procedural
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/procedural_flight_profile.gd
```

Run the network host first, then the client in another terminal after the host is listening:

```powershell
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/dungeon_enet_test.gd -- --procedural-world --dungeon-host --dungeon-port=24739
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/dungeon_enet_test.gd -- --procedural-world --dungeon-port=24739
```

Do not run other Godot instances during the rendered flight benchmark. `SPELLWAKE_PROFILE_STREAM=1` enables slow construction-phase and POI timing logs. The benchmark excludes its own PNG-encoding pause from frame-gap statistics.
