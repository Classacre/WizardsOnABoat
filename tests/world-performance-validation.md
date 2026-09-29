# World/render performance validation

The 2026-09-29 rendered benchmark used Godot 4.7.2 Forward+ at 1280×854 on an RTX 3060 Laptop GPU, with 33 live creature actors and saves disabled. Source data and screenshots are in `output/performance/`. The comparison is `baseline.json` against `final_v1.json`; the separate `final_acceptance.json` covers interactive sailing and actions.

| Scene | Median primitives, baseline → final | Median draw calls, baseline → final | Final steady frame gap, median / p95 |
| --- | ---: | ---: | ---: |
| Harbour boat | 2,019,368 → 1,547,582 (−23.4%) | 243 → 242 | 3.43 / 13.29 ms |
| Sea crossing | 1,672,011 → 1,224,114 (−26.8%) | 164 → 159 | 3.89 / 13.07 ms |
| Rootwatch creatures | 1,705,804 → 1,229,770 (−27.9%) | 141 → 140 | 3.95 / 13.18 ms |

The final run had no frame gaps over 33 ms in those three steady 9-second scene windows (4,430 frames). Reported renderer video memory fell from 621.4 to 589.0 MiB. The profiler inspected harbour, open sea and Rootwatch images and found no new tile seam or foam discontinuity. The old jagged foam appearance remains visible in both runs. Earlier visible-window timings varied substantially between runs, so the frame-rate change cannot be attributed to one edit alone. The first warmup frame in the final run still took about 4.09 seconds; cold-start shader/resource work remains a separate limitation.

The ocean keeps its central 128 m tile at 0.25 m spacing and the same total extent. Outer LOD rings use half as many subdivisions per axis, reducing generated quads from 1,179,648 to 491,520 (58.3%). Seam welding was adjusted to match the 4:1 central/first-ring spacing. Gerstner vertex normals now come from analytic tangents instead of two additional four-wave finite-difference samples. CPU sampling and shader phases use the same precomputed direction, wave number and angular speed. A static numerical comparison over 10,000 random positions and times found zero displacement difference at Python float precision; analytic normals differed from the previous 0.12 m finite-difference approximation by at most 2.26°. Sky updates skip identical fog/palette assignments and hidden procedural clouds during fully painted daytime. Resolution, MSAA, shadows, wave amplitudes, wakes and foam settings were kept.
