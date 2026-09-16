extends SceneTree

const WorldModel = preload("res://scripts/data/world_state.gd")
const Catalog = preload("res://scripts/data/game_catalog.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	_test_capacity()
	_test_hijack_and_replacement()
	_test_death_loot_and_safe_zone()
	_test_disconnect_combat_delay()
	_test_world_saves_and_progression()
	_test_unique_staffs()
	_test_species_loot_and_boss_rewards()
	print("RULES_TEST: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 and assertions >= 100 else 1)

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("RULE FAILED: " + message)

func _test_capacity() -> void:
	var world = WorldModel.new("capacity", 123)
	for index in range(18):
		check(world.connect_player("p%d" % index).ok, "18 players can enter")
	check(not world.connect_player("p18").ok, "19th concurrent player refused")
	check(world.online_count() == 18, "18-player cap exact")
	check(world.active_ship_count() == 5, "crew grouping creates five ships for 18 players")
	var first_crew: String = world.players.p0.crew_id
	check(world.crews[first_crew].members.size() == 4, "crew permits four members")
	world.disconnect_player("p17", 0.0)
	check(not world.connect_player("outsider", "Other", first_crew).ok, "fifth crew member refused")
	check(world.create_crew("p0", "Sixth crew", 0.0).ok, "sixth ship permitted")
	check(world.active_ship_count() == 6, "six-ship cap reached")
	check(not world.create_crew("p1", "Seventh crew", 0.0).ok, "seventh ship refused")
	var enemy_ship: String = world.crews[world.players.p1.crew_id].ship_id
	world.update_player_position("p0", Vector3(90, 0, 90), false)
	world.update_ship_position(enemy_ship, Vector3(90, 0, 90), false)
	check(world.hijack_ship("p0", enemy_ship).ok, "hijack permitted at the six-ship cap")
	world.kill_player("p1", true)
	check(world.respawn_player("p1").ok, "displaced crew receives a replacement at capacity")
	check(world.active_ship_count() == 6, "replacement after hijack preserves exact six-ship cap")
	check(world.invariant_errors().is_empty(), "capacity operations preserve all links")

func _two_crews() -> RefCounted:
	var world = WorldModel.new("rules", 456)
	world.connect_player("a", "Aster")
	world.connect_player("b", "Bram")
	world.create_crew("b", "Rivals", 0.0)
	return world

func _test_hijack_and_replacement() -> void:
	var world = _two_crews()
	var a_crew: String = world.players.a.crew_id
	var b_crew: String = world.players.b.crew_id
	var a_ship: String = world.crews[a_crew].ship_id
	var b_ship: String = world.crews[b_crew].ship_id
	world.update_player_position("a", Vector3(100, 0, 100), false)
	world.update_ship_position(a_ship, Vector3(100, 0, 100), false)
	world.update_ship_position(b_ship, Vector3(100, 0, 100), true)
	check(not world.hijack_ship("a", b_ship).ok, "protected ship cannot be stolen")
	world.update_ship_position(b_ship, Vector3(100, 0, 100), false)
	check(world.hijack_ship("a", b_ship).ok, "rival ship can be hijacked at sea")
	check(world.can_pilot("a", b_ship), "hijacker pilots captured ship")
	check(not world.can_pilot("a", a_ship), "hijacker loses former helm")
	check(not world.can_pilot("b", b_ship), "displaced crew loses captured helm")
	check(world.ships[a_ship].crew_id == "", "previous ship becomes unowned")
	world.kill_player("b", true)
	var respawn: Dictionary = world.respawn_player("b")
	check(respawn.ok and not respawn.aboard, "displaced player respawns at harbour")
	check(world.crews[b_crew].ship_id == a_ship, "abandoned hull recycled as basic replacement")
	check(world.active_ship_count() == 2, "replacement does not inflate ship count")
	check(world.invariant_errors().is_empty(), "hijack and replacement preserve ownership")
	world.update_ship_position(b_ship, Vector3(100, 0, 100), true)
	check(not world.damage_ship("a", b_ship, 100, 10).ok, "harbour hull damage prohibited")
	world.update_ship_position(b_ship, Vector3(100, 0, 100), false)
	check(world.damage_ship("a", b_ship, 10, 10).ok, "crew can damage its own ship at sea")
	world.sink_ship(b_ship)
	world.kill_player("a", true)
	check(world.respawn_player("a").ok, "sunk-ship crew receives replacement")
	check(world.can_pilot("a", world.crews[a_crew].ship_id), "replacement is owned by its crew")

func _test_death_loot_and_safe_zone() -> void:
	var world = WorldModel.new("loot", 789)
	world.connect_player("a")
	world.connect_player("b")
	check(not world.apply_damage("a", "b", 10.0, 10.0).ok, "starter combat prohibited")
	check(world.players.a.crew_id == world.players.b.crew_id, "test members share a crew")
	world.update_player_position("a", Vector3(100, 0, 100), false)
	world.update_player_position("b", Vector3(100, 0, 100), false)
	check(world.apply_damage("a", "b", 10.0, 10.0).ok, "friendly fire allowed at sea")
	check(world.players.b.health == 90.0, "friendly fire deals damage")
	world.claim_apprentice_cache("b")
	var staff_id := ""
	for item in world.players.b.equipment:
		if world.items.has(item):
			staff_id = item
	world.players.b.inventory.pearl = 3
	var death: Dictionary = world.kill_player("b", true)
	check(death.ok and death.floating, "open-water death makes floating chest")
	check(world.players.b.inventory == {"spellbook": 1}, "all carried loot except book is dropped")
	check(world.players.b.equipment.is_empty(), "all equipped gear is dropped")
	check(world.players.b.learned.has("wind") and world.players.b.spells.has("Gale"), "learned spells survive death")
	check(world.loot[death.loot_id].items.has(staff_id), "equipped unique staff is in chest")
	check(not world.kill_player("b", true).ok, "death cannot duplicate loot")
	check(world.take_loot("a", death.loot_id).ok, "another player can take floating chest")
	check(world.players.a.inventory.pearl == 3, "loot transferred exactly")
	check(not world.take_loot("a", death.loot_id).ok, "second loot claim cannot duplicate items")
	world.respawn_player("b")
	world.update_player_position("b", Vector3.ZERO, true)
	world.update_player_position("a", Vector3.ZERO, true)
	var protected_death: Dictionary = world.kill_player("b", false)
	check(not world.take_loot("a", protected_death.loot_id).ok, "harbour prevents loot theft")
	world.respawn_player("b")
	world.update_player_position("b", Vector3.ZERO, true)
	check(world.take_loot("b", protected_death.loot_id).ok, "owner can recover protected belongings")

func _test_disconnect_combat_delay() -> void:
	var world = WorldModel.new("logout", 1)
	world.connect_player("a")
	world.connect_player("b")
	var ship_id: String = world.crews[world.players.a.crew_id].ship_id
	world.ships[ship_id].cargo = {"pearl": 8}
	world.update_player_position("a", Vector3(100, 0, 100), false)
	world.update_player_position("b", Vector3(100, 0, 100), false)
	world.apply_damage("a", "b", 1.0, 90.0)
	world.disconnect_player("a", 95.0)
	world.tick(200.0)
	check(world.ships[ship_id].active, "ship stays while one crewmate is online")
	world.disconnect_player("b", 100.0)
	world.tick(131.0)
	check(world.ships[ship_id].active, "recent combat delays logout despawn")
	world.tick(136.0)
	check(not world.ships[ship_id].active, "last-crew logout eventually removes ship")
	check(world.ships[ship_id].cargo.pearl == 8, "removed ship retains cargo")
	check(world.connect_player("a").ok and world.ships[ship_id].active, "reconnect restores owned ship")
	check(world.ships[ship_id].cargo.pearl == 8, "reconnect restores cargo")

func _test_world_saves_and_progression() -> void:
	var world = WorldModel.new("save-alpha", 982)
	world.connect_player("a")
	check(world.players.a.learned.is_empty() and world.players.a.spells.is_empty(), "new wizard starts with an empty spellbook")
	check(not world.buy_item("a", "power", 1).ok, "shop never sells spell modifiers")
	check(not world.learn_glyph("a", "power", "shop").ok, "shop cannot grant unlocks")
	check(world.claim_apprentice_cache("a").ok, "dungeon cache grants introductory glyphs")
	check(not world.claim_apprentice_cache("a").ok, "dungeon cache claimed once per player per world")
	check(world.learn_glyph("a", "power", "boss").ok, "boss can grant a modifier")
	check(world.save_spell("a", "Gust", ["projectile", "wind", "power"]).ok, "known form-effect-modifier recipe accepted")
	check(not world.save_spell("a", "Bad", ["wind", "projectile"]).ok, "invalid spell ordering rejected")
	check(not Catalog.valid_recipe(["projectile", "heal"], world.players.a.learned), "locked spell effects rejected")
	world.players.a.inventory.pearl = 7
	var path := "user://tests/rules_alpha.json"
	check(world.save_to(path) == OK, "world save succeeds")
	var restored = WorldModel.new("save-alpha", 0)
	check(restored.load_from(path).ok, "world save loads")
	check(restored.players.a.inventory.pearl == 7 and restored.players.a.learned.has("power"), "saved inventory and learned glyphs survive")
	check(restored.seed_value == 982, "world seed persists")
	check(not restored.players.a.online and restored.active_ship_count() == 0, "load does not invent online players or active ships")
	check(restored.connect_player("a").ok, "stable identity reconnects to its saved progression")
	check(not restored.connect_player("a").ok, "simultaneous duplicate identity refused")
	var other = WorldModel.new("save-beta", 0)
	check(not other.load_from(path).ok, "cross-world save import refused")
	other.connect_player("a")
	check(not other.players.a.inventory.has("pearl") and other.players.a.learned.is_empty(), "same identity starts separate progression in another world")
	check(restored.invariant_errors().is_empty(), "save round trip preserves invariants")
	DirAccess.remove_absolute(path)

func _test_unique_staffs() -> void:
	var world = WorldModel.new("staffs", 431)
	world.connect_player("a")
	world.connect_player("b")
	world.players.a.inventory.gold = 200
	var purchase: Dictionary = world.buy_item("a", "driftwood_staff", 2)
	check(purchase.ok and purchase.item_ids.size() == 2, "staff purchase creates two unique instances")
	var staff_id: String = purchase.item_ids[0]
	check(staff_id != purchase.item_ids[1], "staff IDs never stack")
	check(not world.staff_cast_profile("a", staff_id).ok, "blank staff cannot cast")
	check(not world.teach_staff("a", staff_id, "Gale").ok, "staff cannot learn an unknown spell")
	world.claim_apprentice_cache("a")
	check(world.teach_staff("a", staff_id, "Gale").ok, "known spell can be taught to owned staff")
	check(not world.teach_staff("b", staff_id, "Gale").ok, "another player cannot alter an unowned staff")
	var profile: Dictionary = world.staff_cast_profile("a", staff_id)
	check(profile.ok and profile.recipe == ["projectile", "wind", "push"], "staff profile contains the taught recipe")
	check(float(profile[world.items[staff_id].stat]) > 1.0, "random staff affix modifies a real runtime factor")
	check(world.teach_staff("a", staff_id, "Ember").ok and world.items[staff_id].recipe == ["projectile", "spark"], "new inscription replaces the only stored spell")
	var original_affix: Dictionary = world.items[staff_id].duplicate(true)
	world.update_player_position("a", Vector3(80, 0, 80), false)
	world.update_player_position("b", Vector3(80, 0, 80), false)
	var death: Dictionary = world.kill_player("a", true)
	check(world.take_loot("b", death.loot_id).ok, "unique staff transfers through death chest")
	check(not world.staff_cast_profile("a", staff_id).ok, "dead former owner cannot cast dropped staff")
	check(world.staff_cast_profile("b", staff_id).ok, "looter can use the inscribed equipment without gaining book knowledge")
	check(world.players.b.learned.is_empty(), "stolen staff never unlocks its glyphs")
	check(world.items[staff_id] == original_affix, "loot transfer preserves exact staff roll and inscription")
	var path := "user://tests/staff_world.json"
	check(world.save_to(path) == OK, "staff world saves")
	var restored = WorldModel.new("staffs", 0)
	var loaded: Dictionary = restored.load_from(path)
	check(loaded.ok, "staff save loads")
	if loaded.ok:
		var saved: Dictionary = restored.items[staff_id]
		check(saved.id == original_affix.id and saved.affix == original_affix.affix and saved.stat == original_affix.stat and saved.recipe == original_affix.recipe and is_equal_approx(float(saved.magnitude), float(original_affix.magnitude)), "staff identity and affix survive save round trip")
	check(world.invariant_errors().is_empty(), "unique item ownership remains valid")
	DirAccess.remove_absolute(path)

func _test_species_loot_and_boss_rewards() -> void:
	var world = WorldModel.new("ecology", 771)
	world.connect_player("a")
	world.update_player_position("a", Vector3(100, 0, 100), false)
	check(not world.spawn_mob("lanternjaw", "Kelp Channels", 12.0, Vector3.ZERO).ok, "nocturnal predator cannot spawn at noon")
	check(not world.spawn_mob("lanternjaw", "Glass Dunes", 21.0, Vector3.ZERO).ok, "predator cannot spawn in the wrong biome")
	check(not world.spawn_mob("brinecap", "Saltgrass Coast", 12.0, Vector3.ZERO, "impossible").ok, "invalid mob rarity rejected")
	var spawn: Dictionary = world.spawn_mob("lanternjaw", "Kelp Channels", 21.0, Vector3(100, -8, 100), "rare", "kelp_predator_1")
	check(spawn.ok, "legal biome/time/rarity spawn succeeds")
	var inventory: Dictionary = world.mobs[spawn.mob_id].inventory.duplicate(true)
	check(world.mobs[spawn.mob_id].max_health > Catalog.SPECIES.lanternjaw.health, "rarity changes actual creature health")
	check(world.spawn_mob("lanternjaw", "Kelp Channels", 21.0, Vector3.ZERO, "rare", "kelp_predator_1").reused, "persistent spawn identity reuses an existing individual")
	check(world.mobs[spawn.mob_id].inventory == inventory, "spawn reuse never rerolls loot")
	var killed: Dictionary = world.kill_mob(spawn.mob_id, "a")
	check(killed.ok and killed.glyph == "", "ordinary mobs grant no spell knowledge")
	check(world.loot[killed.loot_id].items == inventory, "corpse receives exactly its once-rolled inventory")
	check(not world.kill_mob(spawn.mob_id, "a").ok, "repeat mob death cannot duplicate loot")
	check(not world.spawn_mob("reliquary", "Mangrove Orchard", 12.0, Vector3.ZERO).ok, "boss requires designated encounter source")
	var boss: Dictionary = world.spawn_mob("reliquary", "Mangrove Orchard", 12.0, Vector3(100, 0, 100), "", "archive_guardian", "root_archive")
	check(boss.ok, "designated dungeon creates its boss")
	check(world.mobs[boss.mob_id].inventory.has("living_bark_plate"), "boss guaranteed material is rolled at spawn")
	check(not world.spawn_mob("reliquary", "Mangrove Orchard", 12.0, Vector3.ZERO, "", "another_boss", "root_archive").ok, "one boss per encounter prevents duplicate reward source")
	var boss_death: Dictionary = world.kill_mob(boss.mob_id, "a")
	check(boss_death.ok and boss_death.glyph == "power" and world.players.a.learned.has("power"), "boss grants only its designated glyph")
	check(not world.players.a.learned.has("range"), "other boss glyph remains locked")
	var path := "user://tests/ecology_world.json"
	check(world.save_to(path) == OK, "individual mob state saves")
	var restored = WorldModel.new("ecology", 0)
	check(restored.load_from(path).ok and not restored.mobs[spawn.mob_id].alive, "dead individual remains dead after load")
	check(restored.mobs[boss.mob_id].loot_id == boss_death.loot_id, "saved boss corpse retains its original loot identity")
	DirAccess.remove_absolute(path)
