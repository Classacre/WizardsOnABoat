# Wizards on a Boat — preproduction plan

**Status: all 26 concept-art boards approved; core design decisions confirmed; ready for the user's instruction to begin.** The pre-build clarification has no remaining blocking questions. Tuning values and detailed implementation choices remain adjustable. No game has been implemented, no performance has been benchmarked, and no listed add-on pairing has been tested in this project. Godot installation and game creation remain deferred until the user says to begin. Confirmed decisions are recorded in [decisions.md](decisions.md).

The supplied [Great Sea style board](references/great-sea-style-board.png) anchors the visual direction. Its embedded text is reference material; the user's message establishes the requirements. The Dream Loop is presently at its visual-target stage. Image generation must not be mistaken for a running Godot screenshot or a completed game system.

Research details and verified source links live in [creature design](research/creature-design.md), [world technology](research/world-technology.md), [magic and multiplayer](research/magic-and-multiplayer.md), and the [asset pipeline](research/asset-pipeline.md). This plan consolidates their recommendations without repeating the full research. The [art manifest](manifest.js) and matching prompts establish the current names used here; all remain provisional until review.

## The intended experience

A small crew of wizards sails a vivid, changeable ocean, spots an intriguing island, follows its terrain to a ruin, earns new magical knowledge, and invents better ways to travel and survive. Magic acts on the world: a wind projectile fills the sail, a pulling spell recovers cargo, and a well-timed impulse disrupts a creature's attack. The crew returns with unusual materials, stories and newly discovered ways to compose spells.

The confirmed game is a first-person shared-ocean adventure for up to 18 simultaneous players and at most six ships, initially player-hosted with a future separately running server option. Other players see the wizard character. Each crew has at most four members and one ship; rival crews can hijack ships but cannot pilot several ships simultaneously. Combat, including friendly fire, is enabled between everyone outside protected starter islands, which prevent combat and theft. Two-client development tests are an incremental verification step; the architecture must support the confirmed 18-player/six-ship target from the outset.

## Requirements that stay fixed

- Build the eventual 3D multiplayer game in Godot. Installation in this project directory is authorized for the game phase, after the art review.
- Generate islands of different sizes, sea/land/sky-island biomes, points of interest, and routes that respond to the generated terrain and destinations. Relevant world changes must update local traversal information.
- Research and adapt suitable existing ocean and terrain implementations. Use Runevision's work and Oskar Stålberg-related methods as informed references, with appropriate limits.
- Let players compose spells from learnable components and modifiers, inspired by Ars Nouveau's grammar. Spells physically affect boats, creatures and suitable world objects; wind cast into a sail must accelerate the boat.
- Give mobs individual loot inventories, per-item chances, species-exclusive materials, rarity variants, and biome/time-dependent spawning.
- Spawn players on a starter island with a spellbook and a shop NPC. The shop buys and sells ordinary goods, potions, destination compasses, single-spell staffs with random equipment modifiers, and a hearthstone returning to its shop's island.
- Never sell learnable spell components or spell modifiers in the shop. Players discover them in dungeons and through designated bosses.
- Produce a broad art pack in the supplied visual style, including multiple-angle creature sheets. The user reviews that pack before authorizing game creation.
- Custom Blender work and locally installed ComfyUI workflows are permitted options. Any later AI-to-3D workflow must be selected against the laptop's actual memory budget; permission to use a tool is not evidence that a particular model will fit.

## Visual language

The reference combines cobalt and turquoise water, broken ivory foam, broad sunlight, clustered clouds, warm stone, small red/ochre roofs and faceted rocks. The world should feel windswept, bright and curious, with danger conveyed through scale and action.

**Forms:** large readable masses; slightly exaggerated wizard hats, hands, staffs and creature appendages; clean silhouettes at sailing distance. Buildings can lean and weather gently, while doors, stairs and floors remain functional. Creature anatomy should have one memorable mechanism that explains what it does.

**Materials:** painted color grouping over faceted 3D geometry, restrained texture noise and simple surface wear. Use warm ivory highlights and deep blue shadows. Cloth and water need motion, but visual cloth deformation need not become expensive physical cloth simulation.

**Color:** the ocean owns the strongest blues. Land uses ochre, moss and warm stone to separate it from water. Sea, land and sky creatures each carry a restrained accent that reads against their habitat. Rarity changes shape accents or markings as well as color. Spell warnings use motion and sound in addition to hue.

**Lighting and tone:** noon establishes the baseline; dusk and storms retain readable forms. Avoid burying the setting in grey fog or photoreal surface detail. Bosses can be imposing without gore. A player's first impression should be an inviting sea worth exploring.

**Review quality:** concept sheets show consistent front/side/rear or top angles, an action pose, useful anatomy detail and scale. Generated views are review angles, not modeling-perfect orthographics; limb counts, joints, markings and back views require reconciliation before 3D production.

## The first voyage and progression

1. **Arrive with the book.** The starter island has a safe spawn, visible dock, shop, hearthstone arrival point, tutorial ruin and short connecting paths.
2. **Earn the first magic.** Walk into an accessible tutorial ruin using a physical route and a simple lever or movable object. A guaranteed first cache provides the initial Delivery and Effect. The ruin cannot require its own reward to enter or complete.
3. **Compose and try it.** Make Bolt → Gust in the book, read a plain-language preview, and test it on a training sail or mechanism. This preserves the user's discovery rule without leaving a new player unable to act.
4. **Prepare the crew.** Buy ordinary supplies, an eligible compass, potions or a blank staff. Teach exactly one known spell to a staff; its equipment affixes alter compatible properties of that spell.
5. **Sail and explore.** Navigate toward an island landmark, choose a landing place, follow a valid route and enter a dungeon. Observe creatures before deciding how to approach them.
6. **Return with lasting progress.** Materials fund another voyage; dungeon discoveries and designated bosses expand spell knowledge. The hearthstone returns an individual to its bound shop island under visible travel rules. It does not silently transport the boat or the entire crew.

Each world persists each player's data and progression separately, using a stable player identity within that world. Reconnecting restores that world's progress; it does not import progress from another world. Death preserves learned spells and the spellbook, but drops all other equipped gear and carried loot. On open water, dropped belongings are collected into a floating chest that anyone can take and open outside protected starter areas. Players respawn on their surviving crew ship; otherwise they return to the starter island and receive a basic replacement ship, still subject to world/crew ship limits. Dropped belongings remain recoverable or stealable. When the final crew member disconnects, save and remove the ship and cargo after a delay; recent combat prevents immediate disappearance. First qualifying dungeon/boss completions should provide a guaranteed useful discovery to each eligible participant; that reward policy and repeat/duplicate handling remain proposals. No buyback, dismantling, staff purchase or currency exchange should circumvent the restriction on buying spell knowledge.

## World and biome plan

A bounded seeded archipelago is the first target; the brief does not require an infinite world. Generate enough distant landmarks to invite travel, while loading detailed terrain, navigation and creatures around up to six active crews. Substantial underwater exploration is required: each biome needs its own submerged flora and fauna, readable seabed landmarks and exploration opportunities. Swimming/diving uses limited breath; Air Bubble is a future spell. Every sky island must have a continuous waterfall that players can swim up from an accessible lower approach to a safe top exit. Validate that this default route works before Air Bubble or flying-boat upgrades exist. Future flatter sails allow skilled wind-spell use to make boats hover; this is advanced optional traversal.

| Domain | Proposed biome | Visual and gameplay role |
|---|---|---|
| Sea | Sunlit Shoals | Clear turquoise shelves, pale sandy reefs and ivory surf; safe first sailing and Ribbonwake groups indicating reef channels. |
| Sea | Kelp Channels | Broad olive kelp fans, green-blue water, winding boat corridors and wrecks; Lanternjaw ambush territory near dusk. |
| Sea | Lantern Trench | Steep depth changes, dusk-blue water and sparse amber biological lights; deep-current encounters and Tidebell territory near The Tide Vault. |
| Sea | Storm Reach | Taller white-topped cobalt waves, distant rainclouds and isolated basalt spires; weather-reading and demanding sailing. |
| Land/coast | Saltgrass Coast | Grass-capped warm-grey cliffs, cream beaches and clear ascending paths; Hearthharbour, friendly architecture and Brinecap grazing. |
| Land | Mangrove Orchard | Thick roots, broad green canopies, orange fruit, turquoise pools and raised walkways; The Root Archive and Orchard Reliquary. |
| Land | Basalt Heath | Dark angular stone columns, ochre scrub and geothermal cracks; switchbacks, Knucklers and coastal Kettlebacks. |
| Land | Glass Dunes | Pale-gold sand, turquoise mineral fins, hardy plants and worn arch ruins; exposed routes and distinctive mineral gathering. |
| Sky | Cloud Meadow | Sunlit grassy caps, bent trees, hanging roots and wind markers; Threadwing navigation cues and sheltered grazing shelves. |
| Sky | Stormglass Reef | Pale stone, angular turquoise crystals, visible wind curls and safe lee landings; Stormglass Roc territory. |
| Sky | Astral Orchard | Old wind-pruned fruit trees, ochre observatory arches and small teal stone accents; Cumulus Grazers and The Storm Observatory. |

Time, weather, altitude/depth and local habitat determine spawn eligibility before rarity is rolled. Distant ecology can be represented cheaply; the plan does not require simulating every animal continuously. A rare creature should not vanish mid-encounter just because its spawning time window ends.

### Generation order and path guarantees

Use a versioned world manifest and stable IDs, with independent random streams for terrain, paths, structures, spawns, loot and shop stock. The intended dependency order is:

**Regional plan → island form → POI graph → slope-aware paths → modular structures → collision/navigation → ecology/dressing → validation.**

Reserve the starter island, safe harbor approach, tutorial ruin and recall point before random decoration. Select landing spots, landmarks and dungeon entrances as a connected journey. Prefer gentler routes using slope-aware costs; enforce maximum grade, width, clearance and entrance alignment. Use switchbacks, terraces and supported bridges where required. A route smoothed for appearance must remain inside a verified traversable corridor.

Runevision's layered dependencies and natural-path work are architectural references, not a ready-made Godot package. Stålberg-related irregular grids and local adjacency rules are promising for compact harbors, ruin clusters and dungeon dressing. They should fill spaces within a guaranteed progression/connectivity plan. Constrained generation needs bounded retries and known-good fallback layouts.

“Dynamic pathing” covers both paths generated for each island and local navigation updates after meaningful world changes. Moving small debris may need avoidance only; blocking a door or removing a designated breakable bridge changes connectivity. Physics affects creatures, ships, movable objects and designated breakable structures. Free-form digging, island reshaping and unrestricted building destruction are excluded from the agreed scope.

## Boats, buildings and dungeons

**The first boat**, provisionally the Spellwake Sloop, is a compact wizard sloop with a readable silhouette, one principal sail, a helm/rudder, walkable deck, boarding points, modest cargo space and clear casting sightlines. Its deck must accommodate four crew members. Sail, hull, mast, rigging and rudder need distinct visual responses. The boat sheet explains deck layout and mechanism placement. Ship physics remains authoritative on the server; cloth, rope detail, spray and glitter may be cosmetic. Enforce world ship capacity and one active crew ship through server-owned crew/ship records, including hijacking, replacement and reconnection.

The sail is an important target surface. An aligned Gust produces a short wind pulse that contributes force at the sail's position, with bounded torque and diminishing gains when several players cast together. A generic speed boost would not demonstrate the requested physical interaction. Buoyancy and visible waves must agree at the boat's contact points.

**The starter building kit** for Hearthharbour includes Mara's shop, lighthouse, dock, chart/notice area, storage shed, stairs, retaining walls and hearthstone pad. Mara is the provisional harbour-keeper character. Shared walls, roofs, doors, quays and stairs need consistent dimensions and connection points. Landmarks may be unique while ordinary structures use compatible modules. Random assembly must preserve door access and harbor/ship clearance.

| Dungeon family | Required rooms and identity | Intended play |
|---|---|---|
| The Tide Vault | Partially flooded coastal shrine, low-tide entrance, dry starter annex, raised connectors, tidewheel/pressure chambers and protected page reliquary. | Tide timing, wind and current manipulation; a deeper encounter region hosts Tidebell. Starter annex has stairs and a physical lever, with no magic gate before first glyphs. |
| The Root Archive | Ancient library in Mangrove Orchard, root-framed corridors, elevated paths, root bridge, seed mechanisms, courtyard arena and side-chamber reliquary. | Redirect pods, move obstructions and operate root/irrigation mechanisms; Orchard Reliquary protects the main court. |
| The Storm Observatory | Astral Orchard landing platform, windward stairs, sheltered star-chart chamber, vane puzzle hall and exposed wind bridge. | Read updrafts and storm warnings; requires an arrival method already available to the crew. This is later vertical expansion. |

Every dungeon sheet should reveal entrance, connector, arena and reward space. Rooms require traversal margins, encounter footprints and a valid route out. Artist-authored modules support procedural variation while signature rooms preserve identity.

## Proposed creature roster

Full ecology, anatomy, loot and telegraphs are in the [bestiary research](research/creature-design.md). The pack covers ten species; the intended world can expand after its visual and technical foundations work.

| ID | Creature | Domain / visual hook | Function |
|---|---|---|---|
| C01 | Ribbonwake Glider | Sea; four petal fins and curled ribbon tail | Peaceful current-reading filter feeder. |
| C02 | Kettleback Crab | Shore; cream dome and two organic vents | Pressure-venting scavenger. |
| C03 | Lanternjaw Skulker | Sea; low body and folding throat light | Twilight ambush predator. |
| C04 | Tidebell Colossus | Sea; bell shell and six substantial arms | Current-control boss; proposed Pressure discovery. |
| C05 | Brinecap Browser | Land; stout body and broad salt fan | Grazing animal and memorable mineral source. |
| C06 | Basalt Knuckler | Land; six limbs and oversized foreknuckles | Territorial forager with telegraphed slams. |
| C07 | Orchard Reliquary | Land; plated dome carrying a small grove | Waterworks guardian boss; proposed Bind discovery. |
| C08 | Threadwing Skater | Sky; four delta wings and forked tail | Seed eater that reveals airflow. |
| C09 | Cumulus Grazer | Sky; four inflatable lobes and anchoring tail | Slow herbivore of sheltered floating islands. |
| C10 | Stormglass Roc | Sky; angular wings and amber throat crest | Rare storm-edge predator. |

An individual mob owns one rolled inventory. Opening its corpse repeatedly must not reroll or duplicate contents. Keep species, spawn rarity, individual variant, item rarity and drop chance separate. Ordinary mobs provide materials, curios and potion ingredients; only the specified boss/dungeon progression pools provide learnable spell pieces.

## Spellbook, equipment and economy

Use three comprehensible groups: **Delivery, Effect, Modifier**. The order of effects matters; each modifier visibly attaches to a compatible delivery or effect. The book previews meaning, mana, target count and incompatible combinations before saving. Named recipes can be revised and taught to a staff only when their constituent knowledge has been earned.

The first proposed set is Bolt and Touch; Gust and Draw; Swift and Broad. Larger areas, lingering effects, soaking/chilling, lifting and multi-stage combinations follow only after basic casting is readable and bounded. Runtime budgets should cap active projectiles, lifetime, affected bodies and total force. These are design controls, not tested performance limits.

A staff has exactly one taught recipe and a bounded set of randomly rolled equipment affixes. These affixes apply to the stored spell when compatible; they do not grant reusable book modifiers. Teaching a new spell replaces the old one. The shop displays which affixes will apply before the player commits.

Biome compasses point to an eligible region in the actual world manifest. Island compasses bind to a stable island ID. A hearthstone binds to its shop island and a safe arrival marker. Its channel, cancellation, cooldown and cargo rules should be visible; exact values remain open for tuning. Ordinary loot sales support expedition preparation rather than replacing exploration-based spell progression.

The host validates recipes, casts, purchases, inventory transfers, unlocks and recall destinations. Replicate authoritative outcomes with stable IDs and revisions. Shared seeds do not make physics deterministic between clients.

## Technical choices to test after approval

The initial terrain recommendation is **Terrain3D**, using heightfields for ordinary islands and mesh scenes for caves, buildings and stacked sky islands. **HTerrain** is an alternative. **Voxel Tools** should be reserved for a demonstrated need for volumetric terrain editing; physics spells alone do not require a destructible voxel world.

For water, compare an economical existing Gerstner implementation, beginning with **Boujie Water Shader**, against the FFT candidates **GodotOceanWaves** and **godot4-oceanfft**. **Ocean3D Lite** is another useful surface/physics baseline. Preserve a replaceable surface-query interface for height, normal and water velocity. Match host-side wave sampling to visible gameplay waves and test shoreline depth/refraction on the chosen engine version.

The world research identifies current versions and licenses, including compatibility gaps. Its release findings do not establish that the engine, terrain extension and water shader work together. Pin a proven combination only after an exported comparison scene runs correctly on this laptop.

Observed system memory is **25,132,560,384 bytes, approximately 23.4 GiB total RAM**. The GPU is identified as an **RTX 3060 Laptop GPU**. Exact dedicated VRAM is unverified: `nvidia-smi` was not on PATH and the WMI adapter-memory value is not reliable for this purpose. Available memory, thermal behavior and real gameplay budgets remain unmeasured.

Later model work should begin with small reusable meshes, modest textures, shared materials and LODs. The [checked asset candidates](research/asset-pipeline.md) favor **Blender** for characters, the boat and modular architecture, with **TripoSR** as the first optional reconstruction trial and **Stable Fast 3D** as a second option with first-party ComfyUI support. Both reconstruction projects document approximately 6 GB default VRAM demand; this is not evidence that either fits this laptop. Reduced extraction settings need measurement. TripoSR uses MIT, while SF3D weights have access and Stability AI Community License conditions. Heavier SPAR3D/Hunyuan/TRELLIS workflows are deferred.

Inspect existing local nodes before adding dependencies and verify exact/free VRAM before inference. Run one isolated object and one reconstruction model at a time, separately from gameplay profiling. Feed a single clear three-quarter object view to a single-image reconstructor, not an entire multi-view sheet. Generated models still need topology, scale, material, collision, rig and license/provenance checks. Blender remains the controlled modeling/cleanup baseline. No candidate has been run or benchmarked here.

## Build sequence and evidence gates

| Gate | Work after authorization | Acceptance evidence |
|---|---|---|
| 0. Art approval | Review the 26 boards, settle representative silhouettes, mood and priority changes. | User explicitly approves the visual direction and says to begin game creation. Until then, remain in preproduction. |
| 1. Technical comparison | Install a local portable Godot version; test terrain/water candidates with one boat, island and two connected players. | Record exported-build frame times, generation spikes, RAM/VRAM peaks, wave contact and compatibility. Select a stack from measured results. |
| 2. Moving-boat proof | Walking, boarding, jumping, helm control, cargo and Gust-to-sail casting on a shared boat. | Both peers agree on hits and motion; demonstrate behavior under added latency/loss, with no persistent deck sliding or duplicate forces. |
| 3. First expedition | Safe starter, tutorial glyph cache, shop, a small generated archipelago, valid routes, one dungeon, common wildlife and one boss. | Complete the intended voyage end-to-end; all required paths and rewards are reachable without circular spell dependencies. |
| 4. Persistence and shared waters | Per-world player saves, crew/ship ownership, late join, death drops, floating loot chests, staff inscription, compasses and hearthstone return. | No duplicate loot, cross-world progression leaks, unsafe recall, lost learned spells, or additional crew ships. Validate capacity with 18 connected players and up to six ships, including geographically separated crews. |
| 5. Broader biome and underwater slice | Add contrasting sea/land regions, distinctive underwater flora/fauna, substantial submerged exploration, limited breath and time-specific variants. | Spawn legality, swimming, breath feedback and underwater visibility hold across a bounded seed set; updated performance remains within agreed measured budgets. |
| 6. Sky expansion | Add one sky region with a swimmable waterfall on every island and an observatory family before widening content. | Each waterfall has a reachable lower entry, continuous ascent and safe top exit usable without future Air Bubble or hover-sail upgrades. Arrival, departure, navigation and streaming remain valid and affordable. |

The first coherent vertical slice is gates 1–4, not every pictured biome and creature at once. The art pack establishes a shared destination for a larger game. Each later content increase must earn its CPU, GPU, memory and production cost through measured results.

Principal risks are moving-platform networking, rendering/physics wave mismatch, runtime terrain/navigation stalls, uncontrolled spell combinations, save compatibility and scope growth. The mitigation is to prove the shared boat and bounded spell response before expanding the map, then test generation invariants before adding decoration. High visual fidelity alone does not resolve these risks.

## Concept-art pack index

All 26 boards below have been generated, saved in the project, and approved by the user. Their IDs and titles match the [art manifest](manifest.js); [the art index](ART-INDEX.md) links to the selected images. Biome and dungeon naming follows the associated art prompts: four sea biomes, four land biomes and three sky biomes, eleven in total. Exact prompts and generated-file provenance are recorded in [generation-manifest.json](generation-manifest.json).

| Board | Subject | Review purpose |
|---|---|---|
| 00-voyage | A world worth sailing | Establish the crew, boat, sea, island and distant sky-world promise in one image. |
| 01-wizard | The seafaring wizard | Outfit, staff/book carrying, silhouette, customization range and scale. |
| 02-shopkeeper | Mara, the harbour keeper | Character personality, shop role and shared character proportions. |
| 03-boat | The spellwake sloop | Hull/sail silhouette, deck layout, equipment and readable crew space. |
| 04-starter-island | Hearthharbour starter island | Safe harbor, tutorial route, shop, lighthouse and return pad. |
| 05-buildings | Coastal buildings & modular pieces | Compatible roof/wall/door/stair/quay kit and landmark variation. |
| 06-sea-biomes | Sea biomes | Sunlit Shoals, Kelp Channels, Lantern Trench and Storm Reach. |
| 07-land-biomes | Land biomes | Saltgrass Coast, Mangrove Orchard, Basalt Heath and Glass Dunes. |
| 08-sky-biomes | Sky island biomes | Cloud Meadow, Stormglass Reef and Astral Orchard. |
| 09-tide-vault | Dungeon: The Tide Vault | Entrance, dry starter annex, flooded connectors, tide mechanism and reliquary. |
| 10-root-archive | Dungeon: The Root Archive | Library ruins, root bridge, boss court and exploration side chamber. |
| 11-storm-observatory | Dungeon: The Storm Observatory | Sky landing, wind-vane hall and sheltered star-chart reliquary. |
| 12-ribbonwake | Ribbonwake Glider | Multi-angle creature approval sheet. |
| 13-kettleback | Kettleback Crab | Multi-angle creature approval sheet. |
| 14-lanternjaw | Lanternjaw Skulker | Multi-angle creature approval sheet. |
| 15-tidebell | Tidebell Colossus | Multi-angle boss sheet with ship/player scale. |
| 16-brinecap | Brinecap Browser | Multi-angle creature approval sheet. |
| 17-basalt | Basalt Knuckler | Multi-angle creature approval sheet. |
| 18-orchard | Orchard Reliquary | Multi-angle boss sheet with anatomy beneath foliage. |
| 19-threadwing | Threadwing Skater | Multi-angle creature approval sheet. |
| 20-cumulus | Cumulus Grazer | Multi-angle creature approval sheet. |
| 21-stormglass | Stormglass Roc | Multi-angle creature approval sheet. |
| 22-equipment | Gear, loot & trade | Staffs, compasses, potions, hearthstone, materials and exclusive loot. |
| 23-spellbook | Spellbook & crafting grammar | Legible composition grammar, modifier attachment and recipe preview. |
| 24-spell-physics | Spells that move the world | Wind into sail, moving cargo and creature/environment responses. |
| 25-island-paths | Island scale & connected paths | Small/medium/large silhouettes, POI connections and valid landings. |

## Approval checklist

- [ ] The ocean, lighting, foam and painted/faceted materials match the intended style.
- [ ] Wizard, shopkeeper and boat silhouettes feel like one game and work at player scale.
- [ ] Sea, land and sky biomes remain distinct while sharing the reference's color language.
- [ ] The ten creatures, two bosses and their multiple-angle sheets are an acceptable initial direction.
- [ ] Buildings and dungeon rooms explain usable spaces, connections and entrances.
- [ ] The spellbook composition, staff behavior and exploration-only spell progression match the brief.
- [ ] The first co-op vertical slice and later expansion boundary are acceptable.
- [ ] Changes requested on individual boards have been identified; names and details can remain provisional.
- [ ] The user explicitly says to begin game creation after reviewing the art.

Art approval authorizes moving into the first technical and gameplay gates. It does not convert untested performance assumptions or every pictured future feature into a completed deliverable.
