class_name WorldState
extends RefCounted

const Catalog = preload("res://scripts/data/game_catalog.gd")
const VERSION := 1
const CURRENT_GENERATOR_VERSION := 2
const MAX_PLAYERS := 18
const MAX_SHIPS := 6
const MAX_CREW := 4
const LOGOUT_DELAY := 30.0
const COMBAT_DELAY := 45.0
const STARTER_POSITION := [0.0, 2.0, 0.0]

var world_id := "harbour"
var seed_value := 72841
var generator_version := CURRENT_GENERATOR_VERSION
var players: Dictionary = {}
var crews: Dictionary = {}
var ships: Dictionary = {}
var loot: Dictionary = {}
var items: Dictionary = {}
var mobs: Dictionary = {}
var next_id := 1
var revision := 0

func _init(id: String = "harbour", world_seed: int = 72841, generation: int = CURRENT_GENERATOR_VERSION) -> void:
	world_id = id
	seed_value = world_seed
	generator_version = generation

func _id(prefix: String) -> String:
	var result := "%s_%d" % [prefix, next_id]
	next_id += 1
	return result

func _ok(extra: Dictionary = {}) -> Dictionary:
	revision += 1
	var result := {"ok": true}
	result.merge(extra)
	return result

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}

func online_count() -> int:
	var count := 0
	for player in players.values():
		if player.online:
			count += 1
	return count

func active_ship_count() -> int:
	var count := 0
	for ship in ships.values():
		if ship.alive and ship.active:
			count += 1
	return count

func connect_player(player_id: String, display_name: String = "Wizard", requested_crew: String = "") -> Dictionary:
	if player_id.is_empty() or player_id.length() > 96:
		return _fail("Invalid player identity.")
	if players.has(player_id) and players[player_id].online:
		return _fail("This identity is already connected.")
	if online_count() >= MAX_PLAYERS:
		return _fail("This world already has 18 players.")
	if players.has(player_id):
		var existing: Dictionary = players[player_id]
		var restored := ensure_ship(existing.crew_id)
		if not restored.ok:
			return restored
		existing.online = true
		crews[existing.crew_id].offline_since = -1.0
		return _ok({"player_id": player_id, "crew_id": existing.crew_id, "reconnected": true})
	var crew_id := requested_crew
	if not crew_id.is_empty():
		if not crews.has(crew_id) or crews[crew_id].members.size() >= MAX_CREW:
			return _fail("Crew does not exist or already has four members.")
	else:
		for candidate_id in crews:
			if crews[candidate_id].members.size() < MAX_CREW and _crew_online(candidate_id):
				crew_id = candidate_id
				break
	if crew_id.is_empty():
		if active_ship_count() >= MAX_SHIPS:
			return _fail("All six ship slots are occupied. Join an existing crew.")
		crew_id = _id("crew")
		crews[crew_id] = {"id": crew_id, "name": "Crew %d" % crews.size(), "members": [], "ship_id": "", "offline_since": -1.0, "last_combat": -1000.0}
	var ship_result := ensure_ship(crew_id)
	if not ship_result.ok:
		return ship_result
	var name := display_name.strip_edges().left(24)
	if name.is_empty():
		name = "Wizard"
	players[player_id] = {
		"id": player_id, "name": name, "crew_id": crew_id, "online": true, "alive": true,
		"health": 100.0, "position": STARTER_POSITION.duplicate(), "safe_zone": true,
		"inventory": {"spellbook": 1, "gold": 30, "healing_potion": 2},
		"equipment": ["sailcloth_coat"], "learned": [],
		"spells": {}, "claimed_caches": [],
		"last_combat": -1000.0,
	}
	crews[crew_id].members.append(player_id)
	crews[crew_id].offline_since = -1.0
	create_staff(player_id, true)
	return _ok({"player_id": player_id, "crew_id": crew_id, "reconnected": false})

func _crew_online(crew_id: String) -> bool:
	for member in crews[crew_id].members:
		if players.has(member) and players[member].online:
			return true
	return false

func create_crew(player_id: String, crew_name: String, now: float) -> Dictionary:
	if not _can_shop(player_id):
		return _fail("Crew changes are available in the protected starter harbour.")
	if active_ship_count() >= MAX_SHIPS:
		return _fail("All six ship slots are occupied.")
	var old_crew: String = players[player_id].crew_id
	var crew_id := _id("crew")
	crews[crew_id] = {"id": crew_id, "name": crew_name.strip_edges().left(24), "members": [], "ship_id": "", "offline_since": -1.0, "last_combat": -1000.0}
	var result := ensure_ship(crew_id)
	if not result.ok:
		crews.erase(crew_id)
		return result
	crews[old_crew].members.erase(player_id)
	if not _crew_online(old_crew):
		crews[old_crew].offline_since = now
	crews[crew_id].members.append(player_id)
	players[player_id].crew_id = crew_id
	return _ok({"crew_id": crew_id, "ship_id": result.ship_id})

func join_crew(player_id: String, crew_id: String, now: float) -> Dictionary:
	if not _can_shop(player_id) or not crews.has(crew_id) or crews[crew_id].members.size() >= MAX_CREW:
		return _fail("Crew changes require a harbour and a crew with an open berth.")
	if players[player_id].crew_id == crew_id:
		return _ok({"crew_id": crew_id})
	var result := ensure_ship(crew_id)
	if not result.ok:
		return result
	var old_crew: String = players[player_id].crew_id
	crews[old_crew].members.erase(player_id)
	if not _crew_online(old_crew):
		crews[old_crew].offline_since = now
	crews[crew_id].members.append(player_id)
	crews[crew_id].offline_since = -1.0
	players[player_id].crew_id = crew_id
	return _ok({"crew_id": crew_id})

func disconnect_player(player_id: String, now: float) -> Dictionary:
	if not players.has(player_id):
		return _fail("Unknown player.")
	players[player_id].online = false
	var crew_id: String = players[player_id].crew_id
	if not _crew_online(crew_id):
		crews[crew_id].offline_since = now
	return _ok()

func ensure_ship(crew_id: String) -> Dictionary:
	if not crews.has(crew_id):
		return _fail("Unknown crew.")
	var crew: Dictionary = crews[crew_id]
	var owned: String = crew.ship_id
	if ships.has(owned) and ships[owned].alive and ships[owned].crew_id == crew_id:
		if not ships[owned].active and active_ship_count() >= MAX_SHIPS:
			return _fail("Six ships are already at sea; ship restoration is waiting.")
		ships[owned].active = true
		return _ok({"ship_id": owned})
	# Recycling abandoned hulls preserves the cap. Their cargo becomes public salvage.
	var replacement := ""
	for ship_id in ships:
		if ships[ship_id].alive and ships[ship_id].active and ships[ship_id].crew_id.is_empty():
			replacement = ship_id
			if not ships[ship_id].cargo.is_empty():
				_create_loot("", ships[ship_id].cargo, ships[ship_id].position, true, ships[ship_id].safe_zone)
			break
	if replacement.is_empty():
		if active_ship_count() >= MAX_SHIPS:
			return _fail("Replacement ship is waiting for a free ship slot.")
		replacement = _id("ship")
	ships[replacement] = {"id": replacement, "crew_id": crew_id, "kind": "starter_sloop", "alive": true, "active": true, "health": 250.0, "cargo": {}, "position": [14.0 + crews.size() * 9.0, 0.5, 18.0], "safe_zone": true}
	crew.ship_id = replacement
	return _ok({"ship_id": replacement})

func can_pilot(player_id: String, ship_id: String) -> bool:
	if not players.has(player_id) or not ships.has(ship_id):
		return false
	var player: Dictionary = players[player_id]
	var ship: Dictionary = ships[ship_id]
	return player.online and player.alive and ship.active and ship.alive and player.crew_id == ship.crew_id and crews[player.crew_id].ship_id == ship_id

func hijack_ship(player_id: String, ship_id: String) -> Dictionary:
	if not players.has(player_id) or not ships.has(ship_id):
		return _fail("Unknown player or ship.")
	var player: Dictionary = players[player_id]
	var ship: Dictionary = ships[ship_id]
	if not player.online or not player.alive or not ship.alive or not ship.active:
		return _fail("Player or ship is unavailable.")
	if player.safe_zone or ship.safe_zone:
		return _fail("Starter harbours prevent theft.")
	if _distance(player.position, ship.position) > 12.0:
		return _fail("Move aboard the ship to claim its helm.")
	var new_crew: String = player.crew_id
	if ship.crew_id == new_crew:
		return _ok({"ship_id": ship_id})
	var former_crew: String = ship.crew_id
	var released: String = crews[new_crew].ship_id
	# A single synchronous transaction; no crew can ever retain two owned helms.
	if ships.has(released):
		ships[released].crew_id = ""
	if crews.has(former_crew):
		crews[former_crew].ship_id = ""
	ship.crew_id = new_crew
	crews[new_crew].ship_id = ship_id
	return _ok({"ship_id": ship_id, "released_ship": released, "displaced_crew": former_crew})

func update_player_position(player_id: String, position: Vector3, safe_zone: bool = false) -> void:
	if players.has(player_id) and position.is_finite():
		players[player_id].position = [position.x, position.y, position.z]
		players[player_id].safe_zone = safe_zone

func update_ship_position(ship_id: String, position: Vector3, safe_zone: bool = false) -> void:
	if ships.has(ship_id) and position.is_finite():
		ships[ship_id].position = [position.x, position.y, position.z]
		ships[ship_id].safe_zone = safe_zone

func can_damage(attacker_id: String, target_id: String) -> bool:
	if not players.has(attacker_id) or not players.has(target_id):
		return false
	var attacker: Dictionary = players[attacker_id]
	var target: Dictionary = players[target_id]
	# No crew comparison: friendly fire is always enabled outside protected harbours.
	return attacker.online and target.online and attacker.alive and target.alive and not attacker.safe_zone and not target.safe_zone

func apply_damage(attacker_id: String, target_id: String, amount: float, now: float, on_open_water: bool = false) -> Dictionary:
	if not is_finite(amount) or amount <= 0.0 or not can_damage(attacker_id, target_id):
		return _fail("Combat is not allowed here.")
	for id in [attacker_id, target_id]:
		players[id].last_combat = now
		crews[players[id].crew_id].last_combat = now
	players[target_id].health = maxf(0.0, players[target_id].health - amount)
	if players[target_id].health <= 0.0:
		return kill_player(target_id, on_open_water)
	return _ok({"health": players[target_id].health})

func kill_player(player_id: String, on_open_water: bool) -> Dictionary:
	if not players.has(player_id) or not players[player_id].alive:
		return _fail("Player has already died.")
	var player: Dictionary = players[player_id]
	var dropped: Dictionary = player.inventory.duplicate(true)
	dropped.erase("spellbook")
	for item in player.equipment:
		dropped[item] = int(dropped.get(item, 0)) + 1
	player.inventory = {"spellbook": 1}
	player.equipment = []
	player.alive = false
	player.health = 0.0
	var loot_id := _create_loot(player_id, dropped, player.position, on_open_water, player.safe_zone)
	return _ok({"loot_id": loot_id, "floating": on_open_water})

func _create_loot(owner_id: String, items: Dictionary, position: Array, floating: bool, safe_zone: bool) -> String:
	var loot_id := _id("loot")
	var loot_position := position.duplicate()
	if floating:
		loot_position[1] = 0.45
	loot[loot_id] = {"id": loot_id, "owner_id": owner_id, "items": items.duplicate(true), "position": loot_position, "floating": floating, "safe_zone": safe_zone}
	return loot_id

func take_loot(player_id: String, loot_id: String) -> Dictionary:
	if not players.has(player_id) or not loot.has(loot_id):
		return _fail("Loot is no longer available.")
	var player: Dictionary = players[player_id]
	var chest: Dictionary = loot[loot_id]
	if not player.online or not player.alive:
		return _fail("Player cannot loot now.")
	if (player.safe_zone or chest.safe_zone) and chest.owner_id != player_id:
		return _fail("Starter harbours prevent theft.")
	if _distance(player.position, chest.position) > 6.0:
		return _fail("Move closer to collect the chest.")
	var items: Dictionary = chest.items.duplicate(true)
	for item in items:
		player.inventory[item] = int(player.inventory.get(item, 0)) + int(items[item])
	loot.erase(loot_id)
	return _ok({"items": items})

func respawn_player(player_id: String) -> Dictionary:
	if not players.has(player_id) or players[player_id].alive:
		return _fail("Player is not awaiting respawn.")
	var player: Dictionary = players[player_id]
	var crew: Dictionary = crews[player.crew_id]
	var ship_id: String = crew.ship_id
	var aboard: bool = ships.has(ship_id) and ships[ship_id].alive and ships[ship_id].active
	if aboard:
		player.position = ships[ship_id].position.duplicate()
		player.position[1] += 2.5
		player.safe_zone = ships[ship_id].safe_zone
	else:
		player.position = STARTER_POSITION.duplicate()
		player.safe_zone = true
		ensure_ship(player.crew_id)
	player.alive = true
	player.health = 100.0
	return _ok({"position": player.position.duplicate(), "aboard": aboard, "ship_id": crew.ship_id})

func sink_ship(ship_id: String) -> Dictionary:
	if not ships.has(ship_id) or not ships[ship_id].alive:
		return _fail("Ship is already sunk.")
	var ship: Dictionary = ships[ship_id]
	if not ship.cargo.is_empty():
		_create_loot("", ship.cargo, ship.position, true, ship.safe_zone)
	ship.cargo = {}
	ship.alive = false
	ship.active = false
	ship.health = 0.0
	if crews.has(ship.crew_id):
		crews[ship.crew_id].ship_id = ""
	ship.crew_id = ""
	return _ok()

func damage_ship(attacker_id: String, ship_id: String, amount: float, now: float) -> Dictionary:
	if not players.has(attacker_id) or not ships.has(ship_id) or not is_finite(amount) or amount <= 0:
		return _fail("Invalid ship damage.")
	var attacker: Dictionary = players[attacker_id]
	var ship: Dictionary = ships[ship_id]
	if not attacker.online or not attacker.alive or attacker.safe_zone or ship.safe_zone or not ship.alive or not ship.active:
		return _fail("Ship combat is not permitted here.")
	attacker.last_combat = now
	crews[attacker.crew_id].last_combat = now
	if crews.has(ship.crew_id):
		crews[ship.crew_id].last_combat = now
	ship.health = maxf(0.0, float(ship.health) - amount)
	if ship.health <= 0.0:
		return sink_ship(ship_id)
	return _ok({"health": ship.health})

func tick(now: float) -> bool:
	var changed := false
	for crew in crews.values():
		if crew.offline_since < 0.0 or _crew_online(crew.id):
			continue
		if now - float(crew.offline_since) < LOGOUT_DELAY or now - float(crew.last_combat) < COMBAT_DELAY:
			continue
		var ship_id: String = crew.ship_id
		if ships.has(ship_id) and ships[ship_id].active:
			ships[ship_id].active = false
			changed = true
	if changed:
		revision += 1
	return changed

func buy_item(player_id: String, item_id: String, quantity: int = 1) -> Dictionary:
	if not _can_shop(player_id) or not Catalog.SHOP.has(item_id) or quantity < 1 or quantity > 99:
		return _fail("This item cannot be bought here.")
	var inventory: Dictionary = players[player_id].inventory
	var cost: int = int(Catalog.SHOP[item_id].buy) * quantity
	if int(inventory.get("gold", 0)) < cost:
		return _fail("Not enough gold.")
	inventory.gold = int(inventory.get("gold", 0)) - cost
	if item_id == "driftwood_staff":
		var bought: Array = []
		for index in range(quantity):
			bought.append(create_staff(player_id).item_id)
		return _ok({"item_ids": bought})
	inventory[item_id] = int(inventory.get(item_id, 0)) + quantity
	return _ok()

func sell_item(player_id: String, item_id: String, quantity: int = 1) -> Dictionary:
	if not _can_shop(player_id) or quantity < 1 or quantity > 99:
		return _fail("Shop unavailable.")
	var price: int = Catalog.item_sell_value("driftwood_staff" if items.has(item_id) else item_id)
	var inventory: Dictionary = players[player_id].inventory
	if price <= 0 or int(inventory.get(item_id, 0)) < quantity:
		return _fail("This item cannot be sold.")
	inventory[item_id] -= quantity
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	inventory.gold = int(inventory.get("gold", 0)) + price * quantity
	if items.has(item_id):
		items.erase(item_id)
	return _ok()

func create_staff(player_id: String, equipped: bool = false) -> Dictionary:
	if not players.has(player_id):
		return _fail("Unknown player.")
	var item_id := _id("staff")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ item_id.hash()
	var affix: Dictionary = Catalog.STAFF_AFFIXES[rng.randi_range(0, Catalog.STAFF_AFFIXES.size() - 1)]
	var magnitude := snappedf(rng.randf_range(float(affix.min), float(affix.max)), 0.01)
	items[item_id] = {"id": item_id, "type": "driftwood_staff", "name": "%s Driftwood Staff" % affix.name, "affix": affix.id, "stat": affix.stat, "magnitude": magnitude, "spell_name": "", "recipe": []}
	if equipped:
		players[player_id].equipment.append(item_id)
	else:
		players[player_id].inventory[item_id] = 1
	return _ok({"item_id": item_id})

func owns_item(player_id: String, item_id: String) -> bool:
	return players.has(player_id) and (players[player_id].equipment.has(item_id) or int(players[player_id].inventory.get(item_id, 0)) > 0)

func teach_staff(player_id: String, item_id: String, spell_name: String) -> Dictionary:
	if not items.has(item_id) or not owns_item(player_id, item_id) or not players[player_id].alive:
		return _fail("You must own this staff to teach it a spell.")
	if not players[player_id].spells.has(spell_name):
		return _fail("Teach a spell already written in your own spellbook.")
	var recipe: Array = players[player_id].spells[spell_name]
	if not Catalog.valid_recipe(recipe, players[player_id].learned):
		return _fail("This recipe uses a glyph you have not discovered.")
	# Replaces the previous inscription; a staff never accumulates multiple spells.
	items[item_id].spell_name = spell_name
	items[item_id].recipe = recipe.duplicate()
	return _ok({"item_id": item_id, "spell_name": spell_name})

func staff_cast_profile(player_id: String, item_id: String) -> Dictionary:
	if not items.has(item_id) or not owns_item(player_id, item_id) or not players[player_id].alive or not players[player_id].online:
		return _fail("Staff is not available.")
	var staff: Dictionary = items[item_id]
	if not Catalog.valid_recipe(staff.recipe, Catalog.GLYPHS.keys()):
		return _fail("Teach this staff a spell first.")
	var profile := {"ok": true, "item_id": item_id, "recipe": staff.recipe.duplicate(), "spell_name": staff.spell_name, "affix": staff.affix, "power_multiplier": 1.0, "speed_multiplier": 1.0, "range_multiplier": 1.0, "impulse_multiplier": 1.0}
	profile[staff.stat] = float(staff.magnitude)
	return profile

func spawn_mob(species_id: String, biome: String, hour: float, position: Vector3, rarity: String = "", spawn_key: String = "", encounter_id: String = "") -> Dictionary:
	if not Catalog.spawn_allowed(species_id, biome, hour) or not position.is_finite():
		return _fail("Species is not eligible in this biome or time window.")
	var definition: Dictionary = Catalog.SPECIES[species_id]
	var boss: bool = definition.get("boss", false)
	if boss and encounter_id != definition.encounter:
		return _fail("This boss requires its designated dungeon encounter.")
	if not spawn_key.is_empty() and mobs.has(spawn_key):
		if mobs[spawn_key].species != species_id:
			return _fail("A different species already owns this spawn identity.")
		return _ok({"mob_id": spawn_key, "reused": true})
	if boss:
		for mob in mobs.values():
			if mob.encounter_id == encounter_id:
				return _fail("This dungeon boss has already been created.")
	var mob_id := _id("mob") if spawn_key.is_empty() else spawn_key
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ mob_id.hash() ^ species_id.hash()
	var allowed_rarities: Array = definition.get("rarities", Catalog.RARITY_WEIGHTS.keys())
	if boss:
		if not rarity.is_empty() and rarity != "boss":
			return _fail("Dungeon bosses use boss status rather than ordinary rarity.")
		rarity = "boss"
	elif rarity.is_empty():
		var total := 0.0
		for entry in allowed_rarities:
			total += float(Catalog.RARITY_WEIGHTS[entry])
		var roll := rng.randf() * total
		for entry in allowed_rarities:
			roll -= float(Catalog.RARITY_WEIGHTS[entry])
			if roll <= 0.0:
				rarity = entry
				break
		if rarity.is_empty():
			rarity = allowed_rarities.back()
	elif not allowed_rarities.has(rarity):
		return _fail("Invalid rarity for this species.")
	var inventory: Dictionary = {}
	for entry in definition.loot:
		if rng.randf() <= float(entry.chance):
			inventory[entry.item] = rng.randi_range(int(entry.min), int(entry.max))
	var health: float = float(definition.health) * float(Catalog.RARITY_HEALTH[rarity])
	mobs[mob_id] = {"id": mob_id, "species": species_id, "name": definition.name, "biome": biome, "spawn_hour": hour, "rarity": rarity, "position": [position.x, position.y, position.z], "inventory": inventory, "alive": true, "health": health, "max_health": health, "safe_zone": false, "encounter_id": encounter_id, "loot_id": ""}
	return _ok({"mob_id": mob_id, "rarity": rarity, "reused": false})

func update_mob_position(mob_id: String, position: Vector3, safe_zone: bool = false) -> void:
	if mobs.has(mob_id) and position.is_finite():
		mobs[mob_id].position = [position.x, position.y, position.z]
		mobs[mob_id].safe_zone = safe_zone

func kill_mob(mob_id: String, killer_id: String) -> Dictionary:
	if not mobs.has(mob_id) or not mobs[mob_id].alive or not players.has(killer_id) or not players[killer_id].alive or not players[killer_id].online:
		return _fail("Mob has already died or attacker is unavailable.")
	var mob: Dictionary = mobs[mob_id]
	if mob.safe_zone or players[killer_id].safe_zone:
		return _fail("Starter harbours prevent combat.")
	mob.alive = false
	mob.health = 0.0
	mob.loot_id = _create_loot(killer_id, mob.inventory, mob.position, false, false)
	mob.inventory = {}
	var reward := ""
	var definition: Dictionary = Catalog.SPECIES[mob.species]
	if definition.get("boss", false) and mob.encounter_id == definition.encounter:
		reward = definition.glyph
		learn_glyph(killer_id, reward, "boss")
	return _ok({"loot_id": mob.loot_id, "glyph": reward})

func _can_shop(player_id: String) -> bool:
	return players.has(player_id) and players[player_id].online and players[player_id].alive and players[player_id].safe_zone

func learn_glyph(player_id: String, glyph: String, source: String) -> Dictionary:
	if not players.has(player_id) or not Catalog.GLYPHS.has(glyph) or not ["dungeon", "boss"].has(source):
		return _fail("Glyphs must be discovered in dungeons or earned from bosses.")
	if not players[player_id].learned.has(glyph):
		players[player_id].learned.append(glyph)
	return _ok()

func claim_apprentice_cache(player_id: String) -> Dictionary:
	# Called only after host simulation validates proximity to the tutorial dungeon cache.
	if not players.has(player_id) or not players[player_id].alive or not players[player_id].online:
		return _fail("Player cannot claim this cache.")
	var player: Dictionary = players[player_id]
	if not player.has("claimed_caches"):
		player.claimed_caches = []
	if player.claimed_caches.has("apprentice_cache"):
		return _fail("This world's apprentice cache was already claimed.")
	player.claimed_caches.append("apprentice_cache")
	for glyph in Catalog.STARTING_GLYPHS:
		learn_glyph(player_id, glyph, "dungeon")
	save_spell(player_id, "Gale", ["projectile", "wind", "push"])
	save_spell(player_id, "Ember", ["projectile", "spark"])
	return _ok({"glyphs": Catalog.STARTING_GLYPHS.duplicate()})

func save_spell(player_id: String, spell_name: String, recipe: Array) -> Dictionary:
	if not players.has(player_id) or not Catalog.valid_recipe(recipe, players[player_id].learned):
		return _fail("Spell needs one known form followed by known effects and modifiers.")
	if spell_name.strip_edges().is_empty() or players[player_id].spells.size() >= 16 and not players[player_id].spells.has(spell_name):
		return _fail("Spellbook is full or spell name is empty.")
	players[player_id].spells[spell_name.strip_edges().left(32)] = recipe.duplicate()
	return _ok()

func snapshot() -> Dictionary:
	return {"version": VERSION, "world_id": world_id, "seed": seed_value, "generator_version": generator_version, "players": players.duplicate(true), "crews": crews.duplicate(true), "ships": ships.duplicate(true), "loot": loot.duplicate(true), "items": items.duplicate(true), "mobs": mobs.duplicate(true), "next_id": next_id, "revision": revision}

func save_to(path: String) -> Error:
	var data := snapshot()
	for player in data.players.values():
		player.online = false
	for ship in data.ships.values():
		ship.active = false
	for crew in data.crews.values():
		crew.offline_since = -1.0
	var dir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_error != OK:
		return dir_error
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "", true, true))
	file.close()
	# Keep the previous complete file if the write or rename fails.
	return DirAccess.rename_absolute(path + ".tmp", path)

func load_from(path: String, expected_seed: Variant = null) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("No saved world at this path.")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("version", -1) != VERSION or parsed.get("world_id", "") != world_id:
		return _fail("Unsupported save version or different world identity.")
	var saved_seed: Variant = parsed.get("seed")
	if not (saved_seed is int or saved_seed is float) or not is_finite(float(saved_seed)) or float(saved_seed) != float(int(saved_seed)):
		return _fail("Save has an invalid world seed.")
	if expected_seed != null and int(saved_seed) != int(expected_seed):
		return _fail("This save slot uses seed %d, but seed %d was entered. Enter %d to continue it, or choose a new world name for a different seed." % [int(saved_seed),int(expected_seed),int(saved_seed)])
	var saved_generation: int = int(parsed.get("generator_version",1))
	if saved_generation < 1 or saved_generation > CURRENT_GENERATOR_VERSION:
		return _fail("Unsupported world generator version %d." % saved_generation)
	for key in ["players", "crews", "ships", "loot"]:
		if not parsed.get(key) is Dictionary:
			return _fail("Save is missing its %s table." % key)
	var shape_error := _save_shape_error(parsed)
	if not shape_error.is_empty():
		return _fail("Invalid save: " + shape_error)
	# Loading into a temporary model avoids partial replacement on invalid references.
	var candidate = get_script().new(world_id, int(saved_seed), saved_generation)
	candidate.players = parsed.players
	candidate.crews = parsed.crews
	candidate.ships = parsed.ships
	candidate.loot = parsed.loot
	candidate.items = parsed.get("items", {})
	candidate.mobs = parsed.get("mobs", {})
	candidate.next_id = int(parsed.get("next_id", 1))
	var problems: Array = candidate.invariant_errors()
	if not problems.is_empty():
		return _fail("Invalid ownership in saved world: " + "; ".join(problems))
	players = candidate.players
	crews = candidate.crews
	ships = candidate.ships
	loot = candidate.loot
	items = candidate.items
	mobs = candidate.mobs
	next_id = candidate.next_id
	seed_value = candidate.seed_value
	generator_version = candidate.generator_version
	for player in players.values():
		player.online = false
	for ship in ships.values():
		ship.active = false
	return _ok()

static func _save_shape_error(data: Dictionary) -> String:
	if int(data.get("next_id", 0)) < 1:
		return "invalid ID counter"
	if not data.get("items", {}) is Dictionary or not data.get("mobs", {}) is Dictionary:
		return "invalid item or mob table"
	for player_id in data.players:
		var player = data.players[player_id]
		if not player is Dictionary:
			return "invalid player record"
		if player.get("id", "") != player_id or not player.get("crew_id") is String:
			return "invalid player identity"
		for key in ["online", "alive", "safe_zone"]:
			if not player.get(key) is bool:
				return "invalid player status"
		if not player.get("inventory") is Dictionary or not player.get("equipment") is Array or not player.get("learned") is Array or not player.get("spells") is Dictionary:
			return "invalid player inventory or spellbook"
		if not _valid_position(player.get("position")):
			return "invalid player position"
	for crew_id in data.crews:
		var crew = data.crews[crew_id]
		if not crew is Dictionary or crew.get("id", "") != crew_id or not crew.get("members") is Array or not crew.get("ship_id") is String:
			return "invalid crew record"
	for ship_id in data.ships:
		var ship = data.ships[ship_id]
		if not ship is Dictionary or ship.get("id", "") != ship_id or not ship.get("crew_id") is String:
			return "invalid ship record"
		if not ship.get("alive") is bool or not ship.get("active") is bool or not ship.get("cargo") is Dictionary or not _valid_position(ship.get("position")):
			return "invalid ship status"
	for loot_id in data.loot:
		var chest = data.loot[loot_id]
		if not chest is Dictionary or chest.get("id", "") != loot_id or not chest.get("items") is Dictionary or not _valid_position(chest.get("position")):
			return "invalid loot record"
	for item_id in data.get("items", {}):
		var item = data.items[item_id]
		if not item is Dictionary or item.get("id", "") != item_id or item.get("type", "") != "driftwood_staff" or not item.get("recipe") is Array:
			return "invalid staff record"
		if not ["power_multiplier", "speed_multiplier", "range_multiplier", "impulse_multiplier"].has(item.get("stat", "")):
			return "invalid staff modifier"
		var magnitude: float = float(item.get("magnitude", 0.0))
		if not is_finite(magnitude) or magnitude < 1.0 or magnitude > 1.5:
			return "invalid staff modifier value"
	for mob_id in data.get("mobs", {}):
		var mob = data.mobs[mob_id]
		if not mob is Dictionary or mob.get("id", "") != mob_id or not Catalog.SPECIES.has(mob.get("species", "")):
			return "invalid mob species"
		if not mob.get("alive") is bool or not mob.get("inventory") is Dictionary or not _valid_position(mob.get("position")):
			return "invalid individual mob state"
	return ""

static func _valid_position(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)):
			return false
	return true

func invariant_errors() -> Array:
	var errors: Array = []
	if online_count() > MAX_PLAYERS:
		errors.append("player capacity")
	if active_ship_count() > MAX_SHIPS:
		errors.append("ship capacity")
	for crew_id in crews:
		var crew: Dictionary = crews[crew_id]
		if crew.get("members", []).size() > MAX_CREW:
			errors.append("crew capacity")
		var ship_id: String = crew.get("ship_id", "")
		if not ship_id.is_empty() and (not ships.has(ship_id) or ships[ship_id].get("crew_id", "") != crew_id):
			errors.append("crew ship link")
		for member in crew.get("members", []):
			if not players.has(member) or players[member].get("crew_id", "") != crew_id:
				errors.append("crew member link")
	for player in players.values():
		if not crews.has(player.get("crew_id", "")) or not crews[player.crew_id].members.has(player.get("id", "")):
			errors.append("player crew link")
	for ship_id in ships:
		var owner: String = ships[ship_id].get("crew_id", "")
		if not owner.is_empty() and (not crews.has(owner) or crews[owner].get("ship_id", "") != ship_id):
			errors.append("ship owner link")
	var references: Dictionary = {}
	for item_id in items:
		references[item_id] = 0
	var containers: Array = []
	for player in players.values():
		containers.append(player.inventory)
		for item_id in player.equipment:
			if references.has(item_id):
				references[item_id] += 1
	for ship in ships.values():
		containers.append(ship.cargo)
	for chest in loot.values():
		containers.append(chest.items)
	for mob in mobs.values():
		containers.append(mob.inventory)
	for container in containers:
		for item_id in container:
			if references.has(item_id):
				references[item_id] += int(container[item_id])
	for count in references.values():
		if count != 1:
			errors.append("unique staff ownership")
	return errors

static func _distance(a: Array, b: Array) -> float:
	return Vector3(float(a[0]), float(a[1]), float(a[2])).distance_to(Vector3(float(b[0]), float(b[1]), float(b[2])))
