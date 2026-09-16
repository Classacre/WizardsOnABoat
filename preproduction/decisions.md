# Project decisions

## Confirmed by the user

- All 26 concept-art boards are approved, including the corrected building board and the ten multi-angle creature sheets.
- The original game requirements remain in force.
- The user has asked for remaining questions before beginning game creation. Art approval is recorded; implementation has not been started.
- First-person play, with the character visible to other players.
- Shared open waters support up to 18 simultaneous players and at most six ships. One crew has one ship; crew members cannot pilot multiple ships at once. Do not infer a three-player crew cap by dividing the two world limits.
- Crews have at most four members. The 18-player world cap and six-ship world cap apply independently of that crew limit. Rival crews may hijack ships, while still respecting one ship per crew.
- Worlds are player-hosted initially. Support for a separately running server is a future option.
- Combat is allowed between all players, including crewmates; friendly fire is always on wherever combat is allowed. Starter islands prevent combat and theft, overriding combat permission within those protected areas.
- Progression is separate for every world. Each world saves each player's progress and data so crew members can disconnect and reconnect without losing their progress there. No progression or equipment transfer between worlds is implied.
- Death preserves learned spells and the player's spellbook with its spells. All other equipped gear and carried loot are dropped. Death on open water places the belongings in a floating chest that other players can take and open.
- Spells affect creatures, ships, movable objects and designated breakable structures. Free-form digging, island reshaping and unrestricted building destruction are outside the agreed scope.
- Substantial underwater exploration is required, with different underwater flora and fauna in each biome. Wizards can swim/dive but have limited breath. An Air Bubble spell extending underwater time is a future feature.
- Every sky island must have a waterfall that players can swim up to reach it. This is the normal sky-island access route, available without future flight upgrades.
- Future boat upgrades can flatten the sails enough for skilled players to direct wind spells into them and make the boat hover. This is intentionally difficult, skill-based traversal, not the normal access requirement.
- Players respawn on their crew's ship if it survives; otherwise they respawn at the starter island and receive a basic replacement ship. Dropped belongings remain recoverable or stealable. Replacement must still obey the ship/crew capacity limits.
- When the last crew member disconnects, save and remove their ship and cargo after a delay. Recent combat prevents immediate disappearance. The exact delay and combat timeout are tuning values, not unanswered design requirements.

## Readiness and implementation defaults

No blocking design questions remain from the pre-build clarification. Game creation still awaits the user's instruction to begin. Use configurable starting values for breath, respawn/logout timers, loot-chest lifetime, spell costs and rarity/drop tuning, then refine them through playtesting. These values are implementation proposals, not additional confirmed rules.

Hijacking, respawning, replacement ships and reconnects must share one authoritative crew/ship ownership model so no action creates a second pilotable crew ship or bypasses world capacity. Keep the future dedicated-server option possible without requiring a paid server now.

The earlier 2–4-player/single-ship game proposal is superseded. Small two-client development tests remain useful, but the game architecture and capacity acceptance criteria must target 18 players and six crew-owned ships.
