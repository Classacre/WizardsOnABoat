# World tools validation

The HUD now centers the main menu and every modal in the usable viewport, keeps modal headings and Close controls visible while content scrolls, and lays out at the real window size (`project.godot` uses disabled canvas stretch). The developer menu exposes searchable destinations and spawn choices, fly controls, and explicit host/client status. Client controls are disabled or hidden; host actions use `dev_action(action_name, data)`.

`tests/ui_layout_test.gd` passed headless with `UI_LAYOUT_TEST_FAILURES=0`. It checks panel fit and centering within 1 px at 320×240, 640×360, 1280×854, and 2560×720; live resizing while a panel is open; scrolling; search filtering; host/client gating; and spawn, teleport, and pause-menu signal payloads. Run:

```powershell
.\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/ui_layout_test.gd
```

`tests/dungeon_enet_test.gd` passed as two full-main headless ENet peers on isolated UDP 24731: `DUNGEON_ENET_HOST checks=10 failures=0` and `DUNGEON_ENET_CLIENT checks=5 failures=0`, both exit code 0. It verifies remote entry is denied from outside, physical interior exists when the client arrives after an authorized entry, premature reward is denied, the reward grants three coins and persists, exit returns the remote wizard to the island, and client developer controls have no effect. Each peer used a random in-memory identity and `Session.save_enabled=false`; no player/world save was read or written. Start the host first; once it prints the listening-port PASS, start the client:

```powershell
.\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/dungeon_enet_test.gd -- --dungeon-host --dungeon-port=24731
.\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/dungeon_enet_test.gd -- --dungeon-port=24731
```

During the two-peer run, ENet warned that an unreliable simulation packet was about 11.8 KB, above its 1392-byte MTU. The functional two-peer transition passed, but packet loss under multiplayer load and high-peer-count performance remain unverified. The protocol was not changed in this validation cycle.

Rendered review captures include [main menu](../output/world-tools/main-menu.png), [spellbook](../output/world-tools/menu-book.png), [small-window spellbook](../output/world-tools/menu-book-small-window.png), and [developer menu](../output/world-tools/menu-developer.png). The final captures were visually inspected at their actual resolution, including the 640×360 spellbook, developer controls, and stone interiors in [Rootwatch](../output/world-tools/dungeon-rootwatch.png) and [Tide Vault](../output/world-tools/dungeon-tide_vault.png).

## Full-scene traversal and persistence

The rendered `tests/world_tools_integration.gd` run passed **79 assertions with 0 failures** in 59.8 seconds on 29 September 2026; [machine-readable result](../output/world-tools/integration.json). It uses a random in-memory identity with automatic saves disabled. Its persistence fixture is isolated to `tmp/world-tools/world.json`.

The test opens every gameplay menu, resizes the actual window, invokes F3, flies the real wizard, restores collision, teleports, rejects client developer actions, and spawns persistent creatures and loot. It enters all five surface dungeons (Rootwatch, Cinder Crown, Glasswake, Needle Cay, Tide Vault), physically walks the corridor route to each reward and back to its exit, checks dry collision floors, rejects remote and repeated rewards, and verifies guardian deaths and reward claims survive disk reload. It checks semantic persisted values; JSON number tags are not expected to preserve integer versus float representation.

```powershell
.\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/world_tools_integration.gd
```

`tests/world_test.gd` passed with `WORLD_TEST_FAILURES=0`. Besides terrain and waterfall checks, it checks every required POI route, visible path meshes, slope limits, accepted local obstruction detours, removal, rollback when an obstruction would sever access, deterministic dungeon layouts, connected open tiles, extra graph links, and an upward-facing physical dungeon floor. World generation took 8.6 seconds in that headless run. Dungeon geometry is built only on first use; these are compact single-floor interiors, not multi-floor staircase dungeons.

Final overhead captures of [Hearthharbour](../output/world-tools/paths-hearthharbour.png) and [Rootwatch](../output/world-tools/paths-rootwatch.png) were also inspected. A final visual-only adjustment uses shared, mitered ribbon corners and denser terrain sampling to reduce path seams. Routes and collision geometry are unchanged; the final full-scene capture compiled and ran successfully. The frame-time follow-up below preceded this small ribbon tessellation adjustment.

Regression checks also passed: `tests/rules_test.gd` (121 assertions), `tests/gameplay_test.gd` (21 assertions, including physically walking the starter route, sailing, death, respawn and all sky-island waterfalls), and `tests/creature_manager_test.gd` (0 failures). `git diff --check` passed. The gameplay test now uses a temporary in-memory identity as well as disabling saves.

## Frame-time follow-up

The existing rendered camera benchmark was rerun on the RTX 3060 Laptop GPU at 1280×854, saving [performance.json](../output/world-tools/performance.json). Scene construction was 12.0 seconds; hosting took 0.42 seconds. The harbour, sea-crossing and Rootwatch phases had p95 frame gaps of 13.43, 13.07 and 13.39 ms respectively. There were four gaps above 33 ms across 4,350 measured frames in those phases; the worst was 59.57 ms. The initial warmup also had a 113 ms gap. This supports smooth typical frame delivery but does not establish hitch-free startup or first visits. It is the surface-world camera benchmark, not an 18-player or dungeon stress test. Existing Godot monitor values can remain stale across frames, so elapsed wall-clock frame gaps are the primary evidence.
