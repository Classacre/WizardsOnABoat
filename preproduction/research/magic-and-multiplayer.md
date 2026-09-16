# Magic, progression, loot, and multiplayer

Research checked 16 September 2026. This is a preproduction proposal for review, not an implemented game. The user's subsequent confirmed rules are recorded in [decisions.md](../decisions.md) and take precedence over earlier proposals below: first person, 18 players, six ships, one ship per crew, world-specific progression, full gear/loot loss except the spellbook, floating lootable death chests, and underwater/waterfall traversal. Named mechanics and tuning limits remain provisional unless identified as user requirements.

## Fixed requirements from the brief

- Godot multiplayer sailing adventure, with spells that physically affect boats, creatures, and suitable world objects.
- A procedurally created world with land, sea, and sky-island biomes; island sizes vary and points of interest have connecting paths.
- Players begin on a starter island with a spellbook. Its shop buys and sells ordinary supplies, biome/island compasses, potions, hearthstones, and staffs that hold exactly one taught spell and have random modifiers.
- A hearthstone returns its user to the island where its shop is based.
- Learnable spell components and spell modifiers cannot be bought in the shop. They come from dungeon exploration and designated boss encounters.
- Mobs have individual loot inventories; drop chances and exclusive items vary by species. Spawn rules can depend on biome, time of day, and rarity.
- Game creation starts only after the user reviews the concept art and explicitly says to begin.

## What Ars Nouveau actually does

The upstream [Ars Nouveau repository](https://github.com/baileyholl/Ars-Nouveau) links its documentation website; that website now redirects to Ars.Guide. These are primary project documentation and source references, rather than third-party modpack advice. Features can differ by Minecraft/mod version.

| Researched mechanic | Verified behavior | Useful lesson for this game |
|---|---|---|
| Spell grammar | A spell starts with one Form. Effects resolve in their authored order. Compatible Augments apply to the preceding Form or Effect; several can modify that same part. Augments do not modify other Augments. Glyph tiers I–III require the corresponding book progression. | Show attachment and order visually so players understand why a recipe behaves differently. [Glyphs](https://ars.guide/book/getting_started/introduction_to_glyphs/) |
| Authoring | The player edits a recipe inside the selected spellbook, names it, and saves it. The documented book stores ten spells in selectable bookmarks. | Keep experimentation portable and preserve named recipes. Ten recipe slots is a researched Ars detail, not a mandated limit for our game. [Spellcrafting](https://ars.guide/book/getting_started/introduction_to_spellcrafting/) |
| Learning | Scribe's Table recipes consume specified items and experience to create a glyph, which is then consumed to learn it. An Annotated Codex shares knowledge. | Distinguish acquiring a component from combining known components. Our acquisition economy deliberately follows the user's dungeon/boss requirement. [Learning Glyphs](https://ars.guide/book/getting_started/learning_glyphs/) |
| Inscription | The table can inscribe an existing spell on parchment or appropriate enchanted items. | A staff can store a validated copy of one recipe. [Scribe's Table](https://ars.guide/book/crafting/scribes_table/) |
| Cost | Casting consumes mana according to the glyphs used. Mana regenerates; learned glyphs and several forms of equipment/progression can improve capacity and regeneration. | Preview total cost before committing, and charge recurring effects over their lifetime. [Mana](https://ars.guide/book/getting_started/spell_mana/) |

Do not conflate creating a glyph at the Scribe's Table with composing a spell in the book. Reuse the compositional idea while creating original names, icons, effects, UI, assets, and code.

## Proposed spell system: a readable sequence

The book presents three groups: **Delivery**, **Effect**, and **Modifier**. A simple row is internally grouped as delivery-with-modifiers followed by one or more effects-with-modifiers. Players see a plain-language preview alongside icons.

| Proposed recipe | Preview and physical result |
|---|---|
| Bolt → Gust | Send a small wind projectile. On a valid collision, push the struck body along the bolt's travel direction. A sail receiver transfers the wind to its boat. |
| Bolt + Swift → Gust + Broad | A faster projectile produces a wider gust at impact. Swift belongs to Bolt; Broad belongs to Gust. |
| Touch → Draw | Pull a salvage object toward the caster with bounded force. It can also tug a creature within its resistance limits. |
| Bolt → Soak → Chill | Wet the target, then cool it. Interaction tables decide the extra chill effect; the order is meaningful. |
| Circle → Lift + Lingering | Create a temporary updraft for a limited number of objects or characters. This is later content, after boat physics and basic networking work. |

Proposed first slice: Bolt and Touch deliveries; Gust and Draw effects; Swift and Broad modifiers. Expand only after each combination has readable feedback and a bounded physics cost. Start with six total recipe pieces, at most two effects, and at most two compatible modifiers per affected piece. These are tuning starting points, not measured performance limits. Complex spells also obey a runtime budget: lifetime, affected targets, total impulse, active projectiles, and spawned secondary effects. No recursive self-casting in the first system.

The editor highlights modifier scope, incompatible pieces, estimated mana, and resulting target count. The server validates a canonical recipe before saving or teaching it. A cast references the validated recipe's ID and revision, then supplies aim/input; it never supplies a trusted damage value or arbitrary executable code. The server recomputes mana, cooldown, unlock eligibility, and equipped-staff effects.

### Acquiring knowledge without shopping for it

To satisfy the exclusivity rule literally, the player spawns with the book but gets their first usable Delivery and Effect from a guaranteed, accessible starter-island tutorial dungeon. Its first chamber requires walking and a simple physical interaction, so the player cannot be blocked by lacking magic. The teaching moment is a cache containing the first two pieces, followed by a sail or wind mechanism on which to try the recipe. The dungeon must never require its own final reward to enter or complete.

Each dungeon family has a discovery pool; each designated boss has its own unlock pool and signature component. Ordinary creatures drop crafting materials, potion ingredients, curios, and species-exclusive salvage, not learnable spell pieces. First completion should guarantee an eligible discovery for every participating player, with repeat completion offering currency/material rewards or another still-unknown piece. This avoids a co-op progression bottleneck where a single lucky player receives the only essential unlock.

Persist learned knowledge and player data separately for each world. The spellbook and learned spells survive death; all other equipped gear and carried loot drop. On open water, those belongings become one floating chest that other players can take and open. Save identity is world plus stable player identity, not a transient connection ID. Do not offer a shop buyback, stock reroll, staff dismantling, or NPC exchange that converts ordinary currency into learnable components. A traded recipe can be viewed, but the proposed eligibility rule requires its user to have earned the constituent knowledge in that world before casting or staff teaching.

### Staffs and the shop

A staff stores exactly one taught spell. Re-teaching replaces that recipe; it does not add a hidden second slot. Its random affixes are equipment properties such as reduced mana cost, increased projectile speed, or stronger compatible wind force. They apply to the taught spell where relevant, display the before/after values, and do not become reusable book modifiers. An affix that cannot affect a taught recipe shows as inactive before inscription. Staff rarity controls bounded affix quantity/quality, not access to locked components.

Shop inventory includes ordinary supplies, the user's requested potions, blank staffs with rolled affixes, biome compasses, island compasses, and hearthstones. Selling ordinary loot and equipment funds better expeditions. Biome compasses choose a valid matching region in this world's manifest; island compasses store a stable island ID. Avoid selling a pointer to a nonexistent destination. Show a fallback status if a target is unavailable after a world-version migration.

A hearthstone stores the source shop island's ID and a safe return marker. Proposed return behavior: a visible channel, cancellation on damage, a cooldown, and teleport of the player plus their permitted personal inventory. It must not silently recall the ship or other players. Decide later whether high-value cargo blocks recall; state that rule in the item description. The server validates destination safety and loads the destination before completing travel.

## Making wind in a sail feel physical

The requested interaction should be a general material response: a Gust hitting a sail, a loose crate, a hanging sign, or a small creature all follows the same directional cause, with each receiver deciding how much force it accepts.

1. The server simulates or sweeps the projectile and resolves one authoritative impact with a cast ID.
2. A sail receiver evaluates hit position, current orientation, sail area/condition, and alignment to the incoming wind. A hit on the useful side visibly fills the cloth; a badly aligned hit produces less useful thrust and can alter heading.
3. For the first slice, the impact creates a short wind pulse at the sail. Each physics tick the boat receives a force at the sail's application point, yielding forward acceleration and bounded torque. A separate direct impact on a rigid prop uses a one-time impulse.
4. The boat's buoyancy, drag, rudder, and sail forces continue to operate. Magic contributes to the physical force budget instead of setting a speed multiplier or overriding the boat's velocity.
5. Mana, pulse duration, resistance, and a saturation curve limit combined crew casting. Feedback includes sail deformation, a pale cyan wind ribbon, creaking rigging, spray, and a readable acceleration change.

Godot distinguishes continuous forces from one-time impulses, and permits safe state access in `_integrate_forces`. Positioned force/impulse arguments use an offset from the body's origin in global axes. Applying an impulse every rendered frame creates frame-dependent behavior. These details matter for a sail mounted above the center of mass. [RigidBody3D reference](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html)

Proposed simplification: cloth motion is cosmetic, while a simple sail surface receives hits. Use a handful of buoyancy samples against the same wave-height function the renderer uses, with a cheaper server evaluation of those waves. Do not require GPU ocean readback or full fluid/cloth simulation for gameplay. Stable, repeatable boat response and convincing spray are the immediate objective.

## Multiplayer: prove the moving boat early

**Confirmed scope: up to 18 simultaneous players and six ships in shared open waters, with at most four members and one ship per crew.** Rival crews can hijack ships; crew members cannot pilot multiple ships at once. Player hosting is the initial deployment, with a separately running server option later. Combat and friendly fire apply between all players outside starter islands; starter islands prevent combat and theft. Begin technical verification with two clients, then expand acceptance tests to six separated crews and 18 players. The server owns capacity reservations and crew/ship assignments so hijacking, respawns, reconnects and competing creation requests cannot exceed those limits.

Godot offers ENet in its high-level multiplayer API, authority-controlled RPCs, transfer modes, and channels. Gameplay-critical input should be validated by the server; simply using the API does not make inventory or combat trustworthy. ENet uses UDP, and internet hosting involves network reachability beyond a LAN connection. [Godot high-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)

| State | Proposed owner | Replication strategy |
|---|---|---|
| Boat, loose cargo, creatures, hits | Server/host | Timestamped snapshots; clients interpolate remote motion and play event-driven effects. |
| Player movement | Server with local client prediction | Send sequenced inputs; reconcile position and velocity from acknowledgements. First prove walking and jumping on a rolling boat. |
| Spell recipes and casts | Server validates all recipes/casts | Reliable recipe save/equip acknowledgement; sequenced casts; compact projectile/impact events plus corrections where needed. |
| Loot, trade, staff inscription, unlocks | Server | Reliable transactions with unique IDs and inventory revisions; duplicate messages are harmless. |
| World manifest and saved changes | Server | Versioned region descriptors, hashes, and persistent deltas, streamed by proximity. |
| Foam, small fish schools, cloth, distant birds | Client presentation | Derive from shared parameters when useful; no per-particle replication. |

Godot's `MultiplayerSpawner` replicates configured spawned scenes. `MultiplayerSynchronizer` replicates authority-owned properties and provides visibility filtering; it does not synchronize Resource objects, RIDs, or per-process instance IDs. Use stable game IDs and compact serializable data for creatures, recipes, inventories, and regions. These facilities are useful building blocks; prediction and boat-relative reconciliation still need deliberate design. [Spawner](https://docs.godotengine.org/en/stable/classes/class_multiplayerspawner.html), [Synchronizer](https://docs.godotengine.org/en/stable/classes/class_multiplayersynchronizer.html)

Keep motion snapshots separate from reliable inventory traffic so a large purchase/save acknowledgement does not delay fresh movement. Send only relevant nearby entities; include remote ship silhouettes at reduced detail if needed. On late join, restore that player's world-specific save and crew assignment, then load manifest/version, required regions, current ship state, players, active combat and inventory revisions before enabling control. The world is initially available while its player-host runs it; saving/stopping the host ends that session, with independent server hosting reserved for later. When a non-host crew's final member disconnects, save and remove its ship/cargo after a configurable delay; recent combat blocks immediate disappearance. Rejoining during that delay must reattach to the existing ship. Players respawn on their surviving crew ship, otherwise at the starter island with a basic replacement ship, while dropped belongings remain recoverable or stealable.

### Risks to settle before expanding content

- **Moving-deck prediction:** reconciling a player against a different boat transform causes skating, jitter, or falls. Keep deck-relative state while aboard, account for platform velocity when jumping, and test boarding/disembarking transitions under latency.
- **Double physics:** a client and server both applying a Gust can double its force. Only the authoritative simulation commits it; predicted feedback reconciles by cast ID.
- **Wave mismatch:** a beautiful surface and incompatible buoyancy waves make a boat visibly float above/below water. Share phase, amplitude, direction, world time, and a compatible evaluation model.
- **Physics nondeterminism:** matching world seeds does not make rigid-body simulation agree across machines. Replicate authoritative physical outcomes; never base persistent loot on client physics outcomes.
- **Fast projectiles and thin sails:** discrete collision may miss the sail. Sweep from previous to next projectile position against dedicated receivers.
- **Unbounded spell combinations:** large areas, repeated chain hits, and hundreds of props can exhaust CPU/network budgets. Validate recipe complexity and enforce lifetime/target/cast budgets server-side.
- **Terrain edits:** unrestricted digging or deformation complicates navigation, saves, collision rebuilding, and replication. First permit physics on authored props and designated mechanisms; persistent terrain deformation needs a separate approved scope.
- **Public hosting:** NAT traversal/relay, account identity, griefing controls, and dedicated hosting are additional work. A successful localhost demo does not validate internet play.

## Mob inventories, rarity, and spawning

Treat a species definition, a live creature, and its eventual loot container as separate records. The species specifies habitat, behavior, rarity distribution, and loot table. Each live creature receives a stable entity ID and one rolled inventory; death transfers that inventory into a corpse/container instead of generating a fresh roll every time the corpse opens.

Use explicit independent rolls for ordinary drops, and named weighted groups when exactly one mutually exclusive item is intended. Store quantity ranges and conditional eligibility alongside each entry. Distinguish spawn rarity, creature variant rarity, item rarity, and drop probability in data and UI; they are different concepts.

Example tuning only: an ordinary reef scavenger might have shell fragments at 100% (quantity 1–3), briny resin at 30% (quantity 1), and its exclusive spiral plate at 5%. A rare variant could raise the plate chance to 15% and add a distinct visual material. Those independent rolls may all succeed. A boss's signature discovery belongs to a separate eligibility rule with an explicit first-completion guarantee, not the ordinary materials table.

Spawn selection first filters legal candidates by domain (land/sea/sky), biome, depth/altitude, time window, weather, terrain suitability, minimum distance to players, local population cap, and progression. Only then apply weights and rarity variants. Rarity cannot override an illegal habitat. Keep a low-frequency simulation of distant population state and activate detailed AI only near players. Do not despawn a rare creature mid-encounter when dawn arrives; its spawn rule controls creation, while a clear retreat behavior handles changed conditions.

Validate a loot claim against container ID, range, life state, slot, quantity, and inventory revision. Commit removal from the corpse and addition to the player as one transaction. Preserve a claimed-item ledger/revision across saves and reconnects so opening the same corpse twice cannot duplicate it.

## World seed and persistence contract

Proposed manifest identity: world ID, seed, generator version, content version, starter-island ID, region coordinates, and generated placement records. Derive independent random streams for terrain, structures, paths, spawns, loot, and merchant stock. Adding a decorative tree must not shift every later boss or loot roll.

Generate a guaranteed reachable starter island and a guaranteed first tutorial dungeon. Store biome/POI descriptors and durable object IDs. The seed recreates the baseline; deltas record opened chests, killed unique bosses, depleted resources, moved persistent cargo, learned knowledge, shop inventories, and hearthstone bindings. Persist rolled loot when its creature is instantiated or when first committed to the save. Reloading a region must not reroll living creatures or replenish looted containers accidentally.

A shared seed is an optimization, not a sufficient network contract: engine noise changes, generation order, or content updates can diverge. Pin generator/content versions, hash generated region descriptors, and let the server provide canonical placement data when hashes differ. Keep old worlds on their generator version or explicitly migrate them; never silently regenerate a starter island under saved players.

## Staged vertical slice after art approval

| Stage | Playable proof | Exit evidence |
|---|---|---|
| 1. Boat and network risk | Two players board, walk, steer, jump, and cast wind into one sail. | Both peers agree on impacts and boat motion; no persistent deck sliding in measured latency/loss tests; record CPU/GPU/RAM. |
| 2. Expedition loop | Starter shop → sail to one generated island → follow valid path → enter one dungeon → defeat one creature/boss → return. | Guaranteed reachable entrance and reward; seed reload preserves world and inventories. |
| 3. Spell progression | Find first components, compose named recipes, earn a boss modifier, teach one staff. | Invalid/locked recipes rejected; staff affixes preview accurately; no shop route unlocks book components. |
| 4. Ecology and economy | Two sea biomes, two land biomes, time-gated variants, exclusive drops, compass purchase, hearthstone. | Spawn legality, rare variant readability, single-claim loot, purchase rollback, late join, and safe recall verified. |
| 5. Expand vertically | One sky island biome with one route and dungeon family. | Streaming and travel remain within measured laptop budgets; new content adds no unbounded spell/AI cost. |

The confirmed game target includes 18 players, six ships, four-member crews, player hosting, hijacking, friendly fire, protected starter islands, substantial underwater exploration and waterfall access to every sky island. Future extensions include independent server hosting, more ship classes, additional creature families, Air Bubble, advanced spells and skill-based hover sails. Unrestricted terrain/building destruction is excluded. These requirements do not imply approval to start game development before the user says to begin.
