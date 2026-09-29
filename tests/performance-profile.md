# Rendered performance profile

Run `.\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/performance_profile.gd` from the repository root. The default `rendered_gameplay_v1` scenario builds and hosts a fresh seed 7319 world, disables saving, then spends six measured seconds at the harbour and nine seconds each viewing the hosted boat, crossing the sea, and circling Rootwatch. The camera moves in all but the warmup phase. It renders at the configured 1280 × 854 window size through Forward+ on the NVIDIA GeForce RTX 3060 Laptop GPU. The session uses a random in-memory identity, so it neither reads nor writes a normal identity or world save.

`-- --profile-tag=after --profile-output=res://output/performance/after_v1.json` preserves baseline captures and writes a comparable follow-up. `--profile-extended` appends another 27 seconds of the same camera route after the original four phases. `--profile-sailing` adds a piloted boat passage and wind projectiles that strike Rootwatch; it is a separate acceptance scenario. `--profile-save` enables 15-second autosaves only after redirecting the fresh host to ignored `res://tmp/performance/sandbox-world.json`; it cannot load or overwrite a normal world save. The script records timer resets as save events. The optional `--profile-tag` changes screenshot names. Pass these flags after Godot's `--` separator.

## Original no-save baseline, 2026-09-29

Fresh scene construction took 22,500 ms, then hosting took 718 ms. The first rendered frame incurred additional cold-start work; it is included in the warmup duration and kept separate from steady gap statistics. The world had 33 mobs, 1,501 nodes, and 430 resources. Renderer-reported video memory was about 652 MB. A later process sample showed about 850 MB working set and 1.06 GB private memory.

| Phase | Wall-clock frame gap median | p95 | p99 | Worst | Gaps >100 ms | Godot physics median | Godot process median |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Warmup harbour | 151.6 ms | 243.5 ms | 259.5 ms | 259.5 ms | 34/38 | 50.1 ms | 5.2 ms |
| Harbour boat | 164.8 ms | 215.3 ms | 222.4 ms | 222.4 ms | 54/54 | 29.4 ms | 4.5 ms |
| Sea crossing | 32.6 ms | 199.0 ms | 213.4 ms | 221.8 ms | 40/122 | 19.5 ms | 3.5 ms |
| Rootwatch creatures | 149.7 ms | 171.0 ms | 179.9 ms | 179.9 ms | 61/61 | 24.5 ms | 4.0 ms |

These are measured `Time.get_ticks_usec()` gaps between rendered `SceneTree.process_frame` callbacks, not simulation `delta` or the FPS monitor. Godot process and physics monitors update less often than each rendered frame, so their values can repeat; they are diagnostic, not a breakdown that must sum to the wall-clock gap. Draw calls were about 141–243 median across the phases, and visible primitives about 1.7–2.0 million median.

The isolated autosave run used the same scenario and recorded 202.1 ms harbour, 206.6 ms crossing, and 173.0 ms Rootwatch median gaps. Its first rendered frame added 10.3 seconds of cold work. Process monitor spikes of 335–364 ms near camera transitions also appeared, at 237–323 ms, in the no-save run, so those spikes cannot be attributed to saving from these data alone. The isolated save file was written under `tmp/performance/`.

The initial baseline evidence is `output/performance/baseline.json`, `output/performance/isolated_autosave.json`, and the corresponding PNG captures in that folder. `baseline_v2.json` is exploratory piloted-sailing coverage; it is not a controlled comparison with the original scenario. A creature-simulation-only change was measured in `after_cpu_phase1.json`: the harbour physics monitor median fell from 29.4 to 21.6 ms, but the wall-clock gap varied so much between untouched runs that an FPS improvement cannot be assigned confidently to that one change.

Temporary gated CPU timers identified a separate steady bottleneck. In four five-second rendered windows, `creature_manager.simulate` consumed about 4.3–5.2 seconds over roughly 300 physics ticks, or 14–17 ms per tick. Nineteen grounded mobs call `CharacterBody3D.move_and_slide()` every tick. Their 5,700–5,800 calls consumed about 3.2–4.0 seconds per window, approximately 88–90% of `_move_grounded` time. Route clearance and ground-height sampling were together below 0.2 seconds per window; snapshot publication, simulation broadcasting, and HUD work were much smaller. Cold startup has separate, much larger one-time spikes. The disposable timers were removed before final validation.

## Comparison status

The production `final_v1.json` run preserved the original first four camera phases and appended 27 seconds of steady repeats. It rendered the visible, non-minimized 1280 × 854 game window on the same RTX 3060 Laptop GPU. Both live window samples showed the game was not foreground. The laptop was on AC power with the Balanced power plan, and no other Godot or Blender GUI process was running. One live process sample was about 852 MB working set and 1.74 GB private memory. The renderer reported 589 MiB video memory versus 621 MiB in the initial baseline.

| Phase | Final median | Final p95 | Final p99 | Final worst | Gaps >33 ms | Median primitives before → after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Harbour boat | 3.43 ms | 13.29 ms | 15.41 ms | 20.15 ms | 0/1,476 | 2,019,368 → 1,547,582 |
| Sea crossing | 3.89 ms | 13.07 ms | 15.82 ms | 19.38 ms | 0/1,476 | 1,672,011 → 1,224,114 |
| Rootwatch creatures | 3.95 ms | 13.18 ms | 15.06 ms | 22.40 ms | 0/1,478 | 1,705,804 → 1,229,770 |

The 27 added steady seconds had zero gaps above 33 ms across 4,357 further frames. Fresh scene construction was 12.30 seconds versus 22.50 seconds initially; the first rendered frame added 4.09 seconds in the final run. These startup costs remain substantial. Because the initial no-save runs varied strongly before any production edit, the table demonstrates this final observed result but does not assign all of its gain to a specific change. Godot's process monitor repeated high values across many frames even while measured wall gaps remained below 33 ms, so the wall-clock gaps are the primary frame evidence.

The separate `final_acceptance.json` run sailed the hosted boat 43.58 metres, spawned six wind projectiles, and wrote two saves under the isolated test path. The two detected autosave frames were 6.27 and 5.73 ms. It exposed one 412.49 ms first-spell/impact frame gap; subsequent spells were smooth. A second instrumented acceptance run (`spell_diagnostic.json`) measured each projectile spawn at roughly 9–11 ms CPU and impact/publication at 0.25–0.40 ms, with zero frame gaps above 33 ms across its six casts. The first-use hitch did not repeat after the graphics driver/shader cache was warm, so shader or pipeline compilation is a plausible cause but not directly proven.

The game now shares exact orb, ring, and material resources and renders tiny wind/ember instances during its startup frame to prepare the rendering pipeline. `prewarm_acceptance.json` then sailed 43.69 metres, recorded two isolated autosave frames at 6.61 and 5.58 ms, and spawned six live wind shots at Rootwatch with zero gaps above 33 ms (worst 17.19 ms, p99 14.46 ms). Additional assertions passed: the prewarm completed, a split cast made three projectiles sharing mesh resources, each kept three rotating rings, and the ember material retained its orange tint. This was run after earlier processes had warmed the driver's cache; a truly cold graphics-cache first spell was not reproduced after the prewarm change.

After the disposable timing code was removed, the headless checks passed: creature manager 0 failures, rules 121 assertions/0 failures, world 0 failures, and gameplay 21 assertions/0 failures. The terrain plugin still prints its preexisting `instance_reset_physics_interpolation()` deprecation warning during world build.

The normal `--quickstart` path was also exercised by `tests/performance_quickstart_smoke.gd` with a random in-memory identity and saving disabled. Deferred prewarm completed, hosting entered the game with one local wizard and one boat, no warmup mesh nodes remained under the camera, and the rendered screenshot showed the expected harbour view. The process exited successfully. `output/performance/.gdignore` keeps benchmark evidence out of Godot imports.
