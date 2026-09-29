# Dungeon generation reference

Reviewed 29 September 2026:

- Vazgriz, [Procedurally Generated 3D Dungeons](https://www.youtube.com/watch?v=rBY2Dzej03A): English automatic transcript and selected visual examples reviewed in the browser.
- [Procedurally Generated Dungeons](https://vazgriz.com/119/procedurally-generated-dungeons/): algorithm and staircase constraints.
- [DungeonGenerator source](https://github.com/vazgriz/DungeonGenerator), including `Assets/Scripts2D/Generator2D.cs`, `Assets/Scripts3D/Generator3D.cs` and its license. This is a Unity example, not a Godot dependency.

The useful design is a connected room graph with a small number of extra links, followed by cost-weighted corridor routing. Existing corridors are cheap to reuse; crossing unrelated rooms is expensive. Start, encounter and reward rooms give that structure a gameplay purpose. Connectivity must be checked on the finished walkable floor, not only the room graph.

The game's Godot implementation uses seeded room placement, Delaunay room connections, a spanning tree, additional links and grid pathfinding. It uses compact single-floor interiors with broad passages. Multi-floor stair generation is deferred: the reference's staircase occupancy and headroom constraints can leave graph connections without a usable corridor, and require additional pathfinding state. These interiors are entered through island ruins and share the world and its progression.

The implementation is original GDScript based on the published algorithm. No Unity code, BlueRaja priority queue, or third-party triangulation source is incorporated. Godot's built-in triangulation and a small grid pathfinder avoid adding those dependencies. The referenced repository's MIT license does not cover the example art shown in the video; the game uses its existing supplied assets.

Island surface routes remain terrain-aware and separate from interior corridors. The runtime checks and practical limits for this implementation are recorded in the accompanying tests and validation report.
