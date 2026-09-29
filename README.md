# Wizards on a Boat

Godot prototype and visual development for a first-person multiplayer game about wizards sharing a boat. The concept art and core design decisions are approved. The supplied model collection is integrated into the harbour, ship, dungeon structures and creature ecology. See [confirmed decisions](preproduction/decisions.md).

## Supplied 3D models

The 23 original GLBs in `models/` are preserved. The game uses prepared exports in `assets/models/supplied/`, with consistent scale and orientation, smaller textures, named building-kit pieces and creature rigs. The supplied ship hull uses the existing mast, rigging, sail and sailing controls. Existing wizard, shopkeeper and lighthouse assets remain in use because this collection does not contain replacements.

- [Model intake report](assets/models/supplied/README.md): identified subjects, edits, reproduction commands and kit pieces excluded from world placement.
- [Asset manifest](assets/models/supplied/manifest.json): source hashes, reference identities, bounds, texture sizes and animation status.
- [Creature rig details](assets/models/supplied/RIGGING.md): skeletons, included clips, rebuild commands and animation limitations.
- [Integration validation](tests/supplied-model-validation.md): gameplay, animation, spawn and physics checks, with commands and remaining limits.
- In-game views: [ship deck](output/model-intake/runtime-helm-playable.png), [harbour shop](output/model-intake/runtime-harbour-shop.png), [sky creatures](output/model-intake/runtime-threadwing.png) and [Tidebell underwater](output/model-intake/runtime-tidebell-underwater.png).

Creature spawning uses the existing biome, time-of-day, loot and persistence rules. Animation clips provide basic idle and locomotion motion; they are not a finished combat animation library.

## Showcase and model references

- [Concept art book](output/pdf/Wizards-on-a-Boat-Concept-Art-Book.pdf): 62 pages containing the original style board, all 26 approved concept boards, and 51 complete-subject model references.
- [Single-view reference gallery](preproduction/model-references/index.html): open locally in a browser to browse individual PNGs.
- [Reference image pack](output/art/Wizards-on-a-Boat-Model-Reference-Pack.zip): all 51 PNGs, a portable gallery, exact image prompts and the existing-model coverage map.
- [Reference inventory](preproduction/model-references/README.md): complete objects for Tripo; component segmentation happens after generation.

## Open the project

This repository uses Git LFS for artwork, models, native add-on binaries and finished deliverables. Install Git LFS before cloning, or run `git lfs install` followed by `git lfs pull` in an existing clone.

Open `project.godot` in Godot 4.7.2. The Windows launchers use a local engine at `.tools/godot/Godot_v4.7.2-stable_win64.exe`; engine downloads and local tool environments are not part of the repository. Godot regenerates its `.godot` import cache when the project opens.

## Exploring and developer tools

New worlds use a seed-driven archipelago. Hearthharbour is the fixed starter island; other islands generate from the world seed and their map sector, including their position, size, elevation, biome, terrain, paths and points of interest. Land continues beyond the original harbour map. Nearby terrain and creatures stream in as crews travel, with simpler island silhouettes on the horizon.

Enter a **world name** and **world seed** in the main menu, or choose **Randomize seed**. Matching seeds and generator versions recreate the same geography in separate save slots; progression remains separate. The saved-world list fills the correct name and seed to continue a world. Pause or open developer tools to inspect and copy the active seed. A different seed requires a new world name, so an existing save is never silently overwritten. Older saves retain their original nine-island core and gain generated islands farther out; create a new save to use the fully procedural layout around the starter island.

Menus center in the current viewport, resize with the window, and scroll when their content is taller than the available space. Open the spellbook with **B**, satchel with **I**, crews with **C**, and pause menu with **Esc**.

Island paths connect landings to points of interest. Enter a surface dungeon at its ruin with **E**, explore its seeded rooms and branching corridors, study the interior reliquary for a glyph and coins, and use the marked exit to return to the island. Rewards and defeated guardians persist in that world's save. Large islands have larger interiors; the starter harbour remains protected. See the [dungeon research notes](preproduction/research/dungeon-generation.md).

The host can press **F3** or choose **Developer tools** in the pause menu. Search destinations to teleport to islands, points of interest, dungeon landmarks, players, boats, creatures and loot. Enable flight, then use **WASD** and the mouse to travel, **Space/Ctrl** to rise or descend, and **Shift** to accelerate; the menu also has a speed slider. The spawn list creates ordinary creatures, items and loot chests. Creature habitats need suitable ground, air or water; bosses retain their designated encounter rules. Developer spawns are part of the current world and will be saved with it. Connected clients cannot use these host controls.

## Performance

Grounded creatures use collision movement suited to their terrain-following controller, distant ocean meshes use less geometry, and spells reuse prepared visual resources. Near-boat water detail and the 60 Hz physics rate are retained. The [rendered performance report](tests/performance-profile.md) records before/after frame times, sailing and spell checks, autosave isolation, and startup limitations. The [world/render appendix](tests/world-performance-validation.md) covers water geometry and wave parity.

Ocean swells vary with the world seed: six crossing waves strengthen or soften within three broad moving groups. Procedural crest foam replaces the repeated bitmap, and per-pixel wave shading avoids blurred bands on distant mesh tiles. Boats sample the same wave equations; distant geometry gradually drops short waves. See [ocean visual validation](tests/ocean-visual-validation.md) for shader checks and comparison captures, and [procedural world validation](tests/procedural-validation.md) for streaming, saves and multiplayer.

The project uses Godot's built-in Jolt physics. This removed the multi-second terrain collision stalls found during procedural exploration while retaining creature, player and ship collision. Brief first-load hitches remain; the validation report records the measured limits.

## Design and research

- [Review the illustrated collection](preproduction/index.html): open locally in a browser, filter by category, inspect full-size sheets, and save per-board decisions/notes. Use Export review to save a JSON copy; browser notes are not automatically sent to the assistant.
- [Design plan](preproduction/design-plan.md): requirements, visual direction, world/creature roster, spell/economy design, technical candidates, and staged build gates.
- [Art index](preproduction/ART-INDEX.md): direct image links and concise descriptions.
- [Research](preproduction/research/): primary-source findings and proposed adaptations.
- [Exact image prompts](preproduction/prompts/README.md): built-in image-generation prompt archive and style reference.
- [Review validation](preproduction/review-validation.md): what has been checked and the browser-testing limitation.

The supplied style board is treated as visual reference material. Generated concept sheets are proposals, not screenshots of an implemented Godot game or final modeling blueprints.
