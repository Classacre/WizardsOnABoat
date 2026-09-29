# Ocean visual correction

29 September 2026 · Godot 4.7.2 · Windows · 1280 × 854.

## Diagnosis and changes

The game was loading the intended shader. The baseline rendered check found all 83 ocean tiles sharing `res://shaders/ocean.gdshader`, with zero material mismatches. The directional blur came from blending rotated copies of a repeating foam bitmap and interpolating wave shading across coarse ocean triangles. The bitmap also had no generated mipmaps. Clearing the shader cache would not fix those causes.

The ocean now evaluates analytic wave normals and crest compression per pixel. Six independently phased, seeded Gerstner components and three moving envelopes break up the previously dominant crest rows. Procedural foam contours, gaps and flecks replace the bitmap entirely. Smooth distance filtering removes short-wave geometry that distant mesh grids cannot resolve; shading retains finer detail until it becomes too small on screen. The tile count and geometry budget are unchanged. Nearby CPU buoyancy and rendering retain the same wave equations.

Foam still follows swells, so some aligned crests are intentional. This is a lightweight analytic ocean, not a spectral simulation. Filtering currently assumes the project's typical viewport/FOV; extreme resolutions have not been visually reviewed.

## Rendered evidence

Fixed seed 948321, matching cameras and simulation times:

| View | Before | Final |
| --- | --- | --- |
| Near water | [Baseline](../output/water-review/before/ocean-near.png) | [Updated](../output/water-review/after3/ocean-near.png) |
| Sea level | [Baseline](../output/water-review/before/ocean-sea-level.png) | [Updated](../output/water-review/after3/ocean-sea-level.png) |
| Above water | [Baseline](../output/water-review/before/ocean-overview.png) | [Updated](../output/water-review/after3/ocean-overview.png) |

The final [render report](../output/water-review/after3/render-check.json) records shader code hash `2329274853`, six components, 83 tiles and zero material mismatches. Additional captures exercise distant world coordinates and another simulation time. Review caught triangle-aligned seams during an intermediate revision; the final captures no longer show those seams or the doubled directional texture.

The final isolated ocean run measured 479 animated frame gaps on **AMD Radeon(TM) Graphics**: median **16.58 ms**, p95 **18.56 ms**, maximum **20.33 ms**. PNG encoding is outside that measurement. The baseline ran on the **RTX 3060 Laptop GPU**, so these timings cannot establish a performance improvement or regression against it. They are not full-game or multiplayer benchmarks.

## Functional and scene checks

- `ocean_wave_test.gd`: zero failures, covering seed/time determinism, seed variation, CPU/shader equations, horizontal inversion and analytical normals.
- `world_test.gd`: zero failures after the wave update.
- `gameplay_test.gd`: final rerun, 21 assertions and zero failures, including boarding, helm control, wind propulsion, deck carry, death/respawn and waterfall exits.
- `ocean_scene_visual.gd`: uses the real menu scene and supplied boat assets to capture [harbour](../output/water-review/scene/harbour.png) and [hull/wake](../output/water-review/scene/hull-and-wake.png) with the final shader. Does not host or open a player world. The capture supplies a 7 m/s wake for inspection; it is not a sailing performance test.

The existing Terrain3D interpolation deprecation warning remains unrelated to this correction.

## Reproduce

```powershell
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/ocean_visual.gd -- --water-output=res://output/water-review/recheck
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/ocean_scene_visual.gd
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/ocean_wave_test.gd
& '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/gameplay_test.gd
```
