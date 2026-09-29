class_name SeaCreatureManager
extends Node3D
## Server-owned ecology. Persistent identities, loot and deaths belong to
## WorldState and survive host restarts.

const Catalog = preload("res://scripts/data/game_catalog.gd")
const MODELS := {
	"ribbonwake": "res://assets/models/supplied/ribbonwake.glb",
	"kettleback": "res://assets/models/supplied/crab.glb",
	"lanternjaw": "res://assets/models/supplied/lanternjaw.glb",
	"tidebell": "res://assets/models/supplied/tidebell.glb",
	"brinecap": "res://assets/models/supplied/brinecap.glb",
	"knuckler": "res://assets/models/supplied/basalt.glb",
	"reliquary": "res://assets/models/supplied/orchard.glb",
	"threadwing": "res://assets/models/supplied/glider.glb",
	"cumulus": "res://assets/models/supplied/cumulus.glb",
	"stormglass_roc": "res://assets/models/supplied/stormglass.glb",
}
const LEGACY_MODELS := {
	"kettleback": "res://assets/models/crab.glb",
	"threadwing": "res://assets/models/glider.glb",
}
const SPAWN_COUNTS := {"kettleback": 4, "threadwing": 3, "brinecap": 2, "knuckler": 2, "cumulus": 2, "stormglass_roc": 1, "reliquary": 1}
const SKY_ORBITS := {"threadwing": [0.45, 0.42], "cumulus": [1.1, 0.65], "stormglass_roc": [2.5, 0.65]}
const COLLIDERS := {
	"ribbonwake": [1.1, 2.4, 0.0], "kettleback": [0.68, 1.38, 0.63],
	"lanternjaw": [0.72, 1.5, 0.0], "tidebell": [2.5, 5.0, 2.5],
	"brinecap": [0.7, 2.3, 1.15], "knuckler": [1.0, 2.3, 1.15],
	"reliquary": [1.8, 5.0, 2.5], "threadwing": [0.45, 1.0, 0.0],
	"cumulus": [1.4, 3.0, 0.0], "stormglass_roc": [0.9, 2.2, 0.0],
}
const SEA_HABITATS := {
	"needle_cay": {"biome": "sunlit_shoals", "species": "ribbonwake", "count": 3},
	"rootwatch": {"biome": "kelp_channels", "species": "lanternjaw", "count": 2},
	"tide_vault": {"biome": "lantern_trench", "species": "tidebell", "count": 1},
}
const SEA_BOUNDS := {
	"ribbonwake": [-1.07, 1.07, 1.8],
	"lanternjaw": [-0.75, 0.75, 0.9],
	"tidebell": [0.0, 5.0, 2.6],
}
const STREAM_RADIUS := 430.0
const DUNGEON_STREAM_RADIUS := 90.0
const MAX_ACTIVE_ACTORS := 96
const MOTION_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap;
uniform bool has_texture = false;
uniform vec3 glow : source_color = vec3(0.0);
uniform float metal = 0.0;
uniform float roughness_value = 0.8;
uniform float phase = 0.0;
uniform float activity = 1.0;
uniform bool winged = false;
void vertex() {
	if (winged) {
		float membrane = smoothstep(0.23, 0.75, abs(VERTEX.x)) * (1.0-smoothstep(0.86, 1.12, VERTEX.z));
		VERTEX.y += sin(phase*7.5) * abs(VERTEX.x) * 0.15 * membrane;
	} else {
		float leg = smoothstep(0.65, 0.92, abs(VERTEX.x)) * (1.0-smoothstep(0.56,0.72,VERTEX.y));
		VERTEX.y += max(0.0,sin(phase*8.0 + VERTEX.z*14.0 + sign(VERTEX.x)*1.8)) * 0.075 * leg * activity;
	}
}
void fragment() {
	vec4 surface = base_color;
	if (has_texture) { surface *= texture(base_texture,UV); }
	ALBEDO=surface.rgb;
	ROUGHNESS=roughness_value;
	METALLIC=metal;
	EMISSION=glow;
}
"""

var archipelago: Node3D
var ocean: Node3D
var time_of_day := 12.0
var actors: Dictionary = {}
var _recipes: Array[Dictionary] = []
var _clock := 0.0
var _spawn_clock := 0.0
var _motion_shader: Shader
var _model_cache: Dictionary = {}
var _client_mode := false
var _reconcile_revision := -1
var _stream_anchors: Array[Vector3] = []
var _streaming_enabled := false
var _stream_dirty := false
var _profile_stream := OS.get_environment("SPELLWAKE_PROFILE_STREAM") == "1"

func configure(island_world: Node3D, water: Node3D) -> void:
	archipelago = island_world
	ocean = water
	if _motion_shader == null:
		_motion_shader = Shader.new()
		_motion_shader.code = MOTION_SHADER

func set_stream_anchors(anchors: Array[Vector3]) -> void:
	var changed := not _streaming_enabled or anchors.size() != _stream_anchors.size()
	if not changed:
		for i in anchors.size():
			if anchors[i].distance_squared_to(_stream_anchors[i]) > 35.0 * 35.0:
				changed = true
				break
	_streaming_enabled = true
	_stream_anchors = anchors.duplicate()
	_stream_dirty = _stream_dirty or changed

func _streaming_active() -> bool:
	return _streaming_enabled and archipelago != null and archipelago.has_method("stream_around")

func seed_world(world: RefCounted) -> int:
	if not _can_author():
		return 0
	var profile_start_us := Time.get_ticks_usec() if _profile_stream else 0
	_client_mode = false
	_recipes.clear()
	if not is_instance_valid(archipelago):
		return 0
	for island in archipelago.island_records:
		if bool(island.get("safe",false)):
			continue
		var biome := str(island.biome)
		for species in SPAWN_COUNTS:
			var profile: Dictionary = Catalog.SPECIES[species]
			if not profile.biomes.has(_biome_key(biome)) or (profile.domain == "sky") != bool(island.sky):
				continue
			var count: int = SPAWN_COUNTS[species]
			for index in count:
				var spawn := _spawn_position(island,index,count,species)
				if not spawn.is_finite() or archipelago.is_safe_zone(spawn):
					continue
				var allowed_rarities: Array = profile.get("rarities",[])
				var rarity := "boss" if profile.get("boss",false) else str(allowed_rarities[0]) if not allowed_rarities.is_empty() else "uncommon" if index == count-1 else "common"
				_recipes.append({"key":"wild/%s/%s/%d" % [island.id,species,index],"species":species,"biome":biome,"island_id":str(island.id),"position":spawn,"rarity":rarity})
		if ocean != null:
			var habitat: Dictionary = _sea_habitat(island)
			if habitat.is_empty():
				continue
			for index in int(habitat.count):
				var spawn := _sea_spawn_position(island,index,int(habitat.count),str(habitat.species))
				if not spawn.is_finite() or archipelago.is_safe_zone(spawn):
					continue
				var species: String = habitat.species
				_recipes.append({"key":"wild/%s/%s/%d" % [island.id,species,index],"species":species,"biome":habitat.biome,"island_id":str(island.id),"position":spawn,"rarity":"boss" if Catalog.SPECIES[species].get("boss",false) else "common"})
	var created := _spawn_eligible(world)
	_reconcile_world(world)
	_reconcile_revision = world.revision
	_stream_dirty = false
	if _profile_stream:
		var elapsed_us := Time.get_ticks_usec()-profile_start_us
		if elapsed_us >= 20000:
			print("CREATURE_STREAM_PROFILE seed_world_us=",elapsed_us," islands=",archipelago.island_records.size()," recipes=",_recipes.size()," created=",created," actors=",actors.size())
	return created

func _sea_habitat(island: Dictionary) -> Dictionary:
	if SEA_HABITATS.has(str(island.id)):
		return SEA_HABITATS[island.id]
	if not bool(island.get("procedural",false)) or bool(island.get("sky",false)):
		return {}
	var variant := absi((str(island.id).hash() ^ int(archipelago.world_seed)) % 97)
	match _biome_key(str(island.biome)):
		"saltgrass_coast", "glass_dunes":
			return {"biome":"sunlit_shoals","species":"ribbonwake","count":2 + variant % 2}
		"mangrove_orchard":
			return {"biome":"kelp_channels","species":"lanternjaw","count":2}
		"basalt_heath":
			# Storm coasts retain their shore Kettlebacks. Only some deep shelves
			# support Lanternjaws; a larger ruin can very rarely host the one
			# world-owned Tidebell encounter, never a generic open-sea boss.
			if float(island.radius) >= 75.0 and variant % 37 == 0:
				for poi in island.get("pois",[]):
					if str(poi.kind) == "dungeon":
						return {"biome":"lantern_trench","species":"tidebell","count":1}
			if variant % 3 == 0:
				return {"biome":"lantern_trench","species":"lanternjaw","count":2}
	return {}

func _spawn_position(island: Dictionary, index: int, count: int, species: String) -> Vector3:
	var center: Vector3 = island.center
	var p := center
	if species == "reliquary":
		for poi in island.get("pois",[]):
			if poi.kind == "dungeon":
				p = poi.position + Vector3(2,0,0)
				break
	elif Catalog.SPECIES[species].domain != "sky" and not island.get("paths",[]).is_empty():
		var path: PackedVector3Array = island.paths[0]
		if not path.is_empty():
			# Seed on the authored grade-aware path, not in a random cliff face.
			var offset := float(str(species).hash()%19)*0.01
			var sample := clampi(int(path.size()*(0.13+offset+index*0.15)),0,path.size()-1)
			p = path[sample]
	else:
		var orbit: Array = SKY_ORBITS.get(species,[0.45,0.43])
		var angle := float(index)/maxi(count,1)*TAU+float(orbit[0])
		var radius := float(island.radius)*float(orbit[1])
		p = center+Vector3(cos(angle)*radius,0,sin(angle)*radius)
	p.y = float(archipelago.sample_surface_at(p))
	if Catalog.SPECIES[species].domain == "sky":
		p.y += 3.3
	return p

func activate_dungeon(world: RefCounted, dungeon_id: String) -> int:
	# Stable identities preserve deaths and loot across revisits and world saves.
	# Interior encounters are created on entry, not while sailing past an island.
	if not _can_author() or archipelago == null:
		return 0
	var dungeon: Dictionary = archipelago.get_dungeon(dungeon_id)
	if dungeon.is_empty():
		return 0
	var biome := str(dungeon.get("biome", ""))
	var species := "kettleback" if _biome_key(biome) == "basalt_heath" else "brinecap"
	var created := 0
	var positions: Array = dungeon.get("guard_positions", [])
	for index in mini(2, positions.size()):
		var key := "dungeon/%s/%s/%d" % [dungeon_id, species, index]
		if world.mobs.has(key):
			continue
		var at: Vector3 = positions[index]
		var result: Dictionary = world.spawn_mob(species, biome, time_of_day, at, "common", key)
		if not result.get("ok", false):
			continue
		var record: Dictionary = world.mobs[key]
		record["home"] = _array(at)
		record["island_id"] = dungeon_id
		record["dungeon_id"] = dungeon_id
		record["yaw"] = float(key.hash() % 628) / 100.0
		created += 1
	if created > 0:
		world.revision += 1
	_reconcile_world(world)
	_reconcile_revision = world.revision
	return created

func _sea_spawn_position(island: Dictionary, index: int, count: int, species: String) -> Vector3:
	var center: Vector3 = island.center
	for attempt in 8:
		var angle := TAU * (float(index) / maxi(count,1) + float(attempt)*0.17) + 0.45
		var radius := float(island.radius) * (1.25 + float(attempt % 3)*0.12)
		var p := center + Vector3(cos(angle)*radius,0,sin(angle)*radius)
		var floor_y := _sea_floor(p,species)
		var surface_y: float = ocean.sample_height(p)
		var safe_height := _sea_vertical_range(species,floor_y,surface_y)
		if safe_height.x <= safe_height.y:
			p.y = lerpf(safe_height.x,safe_height.y,0.3)
			return p
	return Vector3(NAN,NAN,NAN)

func _sea_floor(p: Vector3, species: String) -> float:
	if archipelago == null:
		return -20.0
	var footprint := float(SEA_BOUNDS[species][2])
	var floor_y: float = archipelago.sample_ground_height(p.x,p.z)
	for offset in [Vector2(footprint,0),Vector2(-footprint,0),Vector2(0,footprint),Vector2(0,-footprint)]:
		floor_y = maxf(floor_y,archipelago.sample_ground_height(p.x+offset.x,p.z+offset.y))
	return floor_y

func _sea_vertical_range(species: String, floor_y: float, surface_y: float) -> Vector2:
	var bounds: Array = SEA_BOUNDS[species]
	return Vector2(floor_y-float(bounds[0])+0.8,surface_y-float(bounds[1])-0.8)

func _loaded_island(island_id: String) -> bool:
	for island in archipelago.island_records:
		if str(island.id) == island_id:
			return true
	return false

func _stream_score(record: Dictionary, mob_id: String) -> float:
	if not _streaming_active():
		return 0.0
	var point := _vector(record.get("position",Vector3.ZERO))
	var dungeon_id := str(record.get("dungeon_id",""))
	if dungeon_id.is_empty() and archipelago.has_method("dungeon_at"):
		dungeon_id = archipelago.dungeon_at(point)
	var radius := DUNGEON_STREAM_RADIUS if not dungeon_id.is_empty() else STREAM_RADIUS
	var best := INF
	for anchor in _stream_anchors:
		if not dungeon_id.is_empty():
			if not archipelago.has_method("dungeon_at") or archipelago.dungeon_at(anchor) != dungeon_id:
				continue
			best = minf(best,point.distance_squared_to(anchor))
		else:
			if archipelago.has_method("dungeon_at") and not archipelago.dungeon_at(anchor).is_empty():
				continue
			best = minf(best,Vector2(point.x-anchor.x,point.z-anchor.z).length_squared())
	if best > radius * radius:
		return INF
	if not dungeon_id.is_empty():
		if archipelago.get_dungeon(dungeon_id).is_empty() or archipelago.dungeon_surface_at(point) < 0.0:
			return INF
		return best
	var island_id := str(record.get("island_id",""))
	if island_id.is_empty() and mob_id.begins_with("wild/"):
		var parts := mob_id.split("/")
		if parts.size() >= 4:
			island_id = parts[1]
	var species := str(record.get("species",""))
	if island_id.is_empty() and Catalog.SPECIES.has(species) and Catalog.SPECIES[species].domain in ["land","shore"]:
		for island in archipelago.island_records:
			if not island.sky and Vector2(point.x-island.center.x,point.z-island.center.z).length_squared() < pow(float(island.radius)*1.2,2.0):
				island_id = str(island.id)
				break
	if not island_id.is_empty() and not _loaded_island(island_id):
		return INF
	if Catalog.SPECIES.has(species) and Catalog.SPECIES[species].domain in ["land","shore"]:
		if island_id.is_empty() or not archipelago.navigation_graphs.has(island_id):
			return INF
	return best

func _stream_candidate_before(a: Dictionary, b: Dictionary) -> bool:
	return float(a.score) < float(b.score) if not is_equal_approx(float(a.score),float(b.score)) else str(a.id) < str(b.id)

func _spawn_eligible(world: RefCounted) -> int:
	var created := 0
	for recipe in _recipes:
		if world.mobs.has(recipe.key):
			continue # Includes dead records: a reconnect must never reroll loot.
		if _stream_score(recipe,str(recipe.key)) == INF:
			continue
		if not Catalog.spawn_allowed(recipe.species,recipe.biome,time_of_day):
			continue
		var encounter_id: String = Catalog.SPECIES[recipe.species].get("encounter","")
		var result: Dictionary = world.spawn_mob(recipe.species,recipe.biome,time_of_day,recipe.position,recipe.rarity,recipe.key,encounter_id)
		if not result.get("ok",false):
			continue
		var record: Dictionary = world.mobs[result.mob_id]
		record["home"] = _array(recipe.position)
		record["island_id"] = recipe.island_id
		record["yaw"] = float(str(recipe.key).hash()%628)/100.0
		created += 1
	return created

func simulate(delta: float, world: RefCounted, wizards: Dictionary) -> bool:
	if not _can_author() or not is_finite(delta) or delta <= 0.0:
		return false
	var profile_start_us := Time.get_ticks_usec() if _profile_stream else 0
	_client_mode = false
	var step := minf(delta,0.1)
	_clock += step
	_spawn_clock += step
	var changed := false
	var reconcile_due := false
	if _spawn_clock >= 2.0:
		_spawn_clock = 0.0
		changed = _spawn_eligible(world) > 0
		reconcile_due = true
	if reconcile_due or world.revision != _reconcile_revision or _stream_dirty:
		_reconcile_world(world)
		_reconcile_revision = world.revision
		_stream_dirty = false
	var eligible_players: Dictionary = {}
	for player_id in world.players:
		var player: Dictionary = world.players[player_id]
		if not player.online or not player.alive or player.safe_zone:
			continue
		var point := _player_position(player_id,world,wizards)
		if archipelago and archipelago.is_safe_zone(point):
			continue
		eligible_players[player_id] = point
	for mob_id in actors.keys():
		if not world.mobs.has(mob_id) or not world.mobs[mob_id].alive:
			continue
		var mob: Dictionary = world.mobs[mob_id]
		var actor: Dictionary = actors[mob_id]
		var body: CharacterBody3D = actor.body
		if not str(mob.get("dungeon_id", "")).is_empty() and _nearby_player(body.position, world, eligible_players, 90.0).is_empty():
			# Unoccupied interiors do not add ongoing AI or collision work.
			body.velocity = Vector3.ZERO
			actor.state = "idle"
			continue
		actor.cooldown = maxf(0.0,float(actor.cooldown)-step)
		actor.decision = float(actor.decision)-step
		var domain := str(Catalog.SPECIES[mob.species].domain)
		var target_id := _nearby_player(body.position,world,eligible_players,13.5 if domain == "shore" else 9.0)
		var target := _vector(mob.get("home",mob.position))
		var chasing := not target_id.is_empty()
		var player_target: Vector3 = eligible_players.get(target_id,Vector3.ZERO)
		if chasing:
			target = player_target
			# Threadwings retreat from approaching wizards; crabs guard their patch.
			if domain == "sky":
				var away := (body.position-target).normalized()
				target = body.position+away*7.0
				target.y = maxf(target.y,float(archipelago.sample_surface_at(body.position))+3.0) if archipelago else target.y
		else:
			if float(actor.decision) <= 0.0 or body.position.distance_to(actor.goal) < 1.0:
				actor.goal = _wander_goal(mob,actor)
				actor.decision = 4.0+float(str(mob_id).hash()%20)*0.1
			target = actor.goal
		var home := _vector(mob.get("home",mob.position))
		if Vector2(body.position.x-home.x,body.position.z-home.z).length() > 24.0:
			target = home
			chasing = false
			actor.state = "returning"
		else:
			actor.state = "fleeing" if chasing and domain == "sky" else "chasing" if chasing else "wandering"
		var old_position := body.position
		if domain == "sea":
			_move_aquatic(actor,target,step)
		elif domain == "sky":
			_move_flying(actor,target,step)
		else:
			_move_grounded(actor,mob,target,step,chasing)
		var in_safe_zone: bool = archipelago != null and archipelago.is_safe_zone(body.position)
		if in_safe_zone:
			body.position = old_position
			body.velocity = Vector3.ZERO
			in_safe_zone = archipelago.is_safe_zone(body.position)
		var distance := old_position.distance_to(body.position)
		if distance > 0.001:
			var direction := body.position-old_position
			body.rotation.y = lerp_angle(body.rotation.y,atan2(-direction.x,-direction.z),1.0-exp(-step*7.0))
		else:
			actor.state = "idle" if not chasing else actor.state
		mob["yaw"] = body.rotation.y
		mob["state"] = actor.state
		mob["phase"] = _clock+float(actor.phase_offset)
		world.update_mob_position(mob_id,body.position,in_safe_zone)
		_animate(actor,step,distance/step)
		if chasing and domain in ["shore", "land", "sea"] and not target_id.is_empty() and body.position.distance_to(player_target) < float(actor.hit_radius)+1.0 and float(actor.cooldown) <= 0.0:
			if not str(mob.get("dungeon_id", "")).is_empty():
				var sight := PhysicsRayQueryParameters3D.create(body.position + Vector3.UP, player_target + Vector3.UP, 1)
				if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
					continue
			if domain == "sea" and ocean and player_target.y > ocean.sample_height(body.position)+0.3:
				continue
			if _attack_player(mob,target_id,world):
				actor.cooldown = 1.6
				changed = true
	if _profile_stream:
		var total_us := Time.get_ticks_usec()-profile_start_us
		if total_us >= 20000:
			print("CREATURE_STREAM_PROFILE simulate_us=",total_us," actors=",actors.size()," recipes=",_recipes.size()," mobs=",world.mobs.size())
	return changed

func _can_author() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

func _nearby_player(position_value: Vector3, world: RefCounted, eligible_players: Dictionary, radius: float) -> String:
	var nearest := ""
	var distance_squared := radius * radius
	for player_id in eligible_players:
		if not world.players[player_id].alive:
			continue
		var candidate := position_value.distance_squared_to(eligible_players[player_id])
		if candidate < distance_squared:
			distance_squared = candidate
			nearest = player_id
	return nearest

func _player_position(player_id: String, world: RefCounted, wizards: Dictionary) -> Vector3:
	if wizards.has(player_id) and is_instance_valid(wizards[player_id]):
		return wizards[player_id].global_position
	return _vector(world.players[player_id].position)

func _wander_goal(mob: Dictionary, actor: Dictionary) -> Vector3:
	var home := _vector(mob.get("home",mob.position))
	var angle := _clock*0.43+float(actor.phase_offset)*2.4
	var p := home+Vector3(cos(angle),0,sin(angle))*5.5
	var domain := str(Catalog.SPECIES[mob.species].domain)
	if archipelago and not str(mob.get("dungeon_id", "")).is_empty():
		var floor_y: float = archipelago.dungeon_surface_at(p)
		if absf(floor_y - home.y) > 1.0:
			return home
		p.y = floor_y
		return p
	if domain == "sea":
		var floor_y := _sea_floor(p,str(mob.species))
		var surface_y: float = ocean.sample_height(p) if ocean else 0.0
		var safe_height := _sea_vertical_range(str(mob.species),floor_y,surface_y)
		if safe_height.x > safe_height.y:
			return home
		p.y = clampf(home.y+sin(angle*0.7)*0.8,safe_height.x,safe_height.y)
	elif archipelago:
		p.y = float(archipelago.sample_surface_at(Vector3(p.x,home.y,p.z)))
	if domain == "sky":
		p.y += 3.2+sin(angle*0.7)*0.5
	return p

func _move_grounded(actor: Dictionary, mob: Dictionary, target: Vector3, delta: float, chasing: bool) -> void:
	var body: CharacterBody3D = actor.body
	var direction := Vector3.ZERO
	var island_id := str(mob.get("island_id",""))
	actor.route_timer = float(actor.route_timer)-delta
	var revision := -1
	if archipelago and archipelago.navigation_graphs.has(island_id):
		revision = int(archipelago.navigation_graphs[island_id].revision)
	if float(actor.route_timer) <= 0.0 or int(actor.route_revision) != revision or actor.route_target.distance_to(target) > 3.0:
		actor.route = _navigation_route(island_id,body.position,target)
		actor.route_index = 0
		actor.route_target = target
		actor.route_timer = 0.75
		actor.route_revision = revision
	var path: PackedVector3Array = actor.route
	while int(actor.route_index) < path.size() and body.position.distance_to(path[int(actor.route_index)]) < 0.8:
		actor.route_index = int(actor.route_index)+1
	var destination := target
	if int(actor.route_index) < path.size():
		destination = path[int(actor.route_index)]
	var clear: bool = archipelago != null and archipelago.route_is_clear(island_id,body.position,destination)
	if clear and body.position.distance_to(destination) > 0.5:
		direction = destination-body.position
		direction.y = 0.0
		direction = direction.normalized()
	var speed := 2.7 if chasing else 1.25
	var next := body.position+direction*speed*delta
	var ground: float = archipelago.sample_surface_at(next) if archipelago else body.position.y
	# An empty/disconnected navigation route cannot license a cliff jump or ocean walk.
	if ground < -0.25 or absf(ground-body.position.y) > maxf(0.35,speed*delta*0.78):
		direction = Vector3.ZERO
	body.velocity = direction*speed
	if direction != Vector3.ZERO:
		body.move_and_slide()
	if archipelago:
		body.position.y = float(archipelago.sample_surface_at(body.position))+0.035

func _navigation_route(island_id: String, from: Vector3, to: Vector3) -> PackedVector3Array:
	var profile_start_us := Time.get_ticks_usec() if _profile_stream else 0
	var route := PackedVector3Array()
	if archipelago and archipelago.get_dungeon(island_id).size() > 0:
		route = archipelago.dungeon_route(island_id, from, to)
	elif archipelago and archipelago.navigation_graphs.has(island_id):
		var graph: Dictionary = archipelago.navigation_graphs[island_id]
		var region: NavigationRegion3D = graph.get("region")
		if region != null and region.is_inside_tree():
			var map := region.get_navigation_map()
			if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
				route = NavigationServer3D.map_get_path(map,from,to,true)
	if _profile_stream:
		var elapsed_us := Time.get_ticks_usec()-profile_start_us
		if elapsed_us >= 20000:
			print("CREATURE_STREAM_PROFILE navigation_route_us=",elapsed_us," island=",island_id," path_points=",route.size()," from=",from," to=",to)
	return route

func _move_flying(actor: Dictionary, target: Vector3, delta: float) -> void:
	var body: CharacterBody3D = actor.body
	var home := _vector(actor.record.get("home",actor.record.position))
	if Vector2(target.x-home.x,target.z-home.z).length() > 18.0:
		target = home
	var direction := target-body.position
	body.velocity = direction.normalized()*minf(3.1,direction.length()*1.8)
	body.move_and_slide()
	if archipelago:
		var ground := float(archipelago.sample_surface_at(Vector3(body.position.x,home.y,body.position.z)))
		body.position.y = maxf(body.position.y,ground+1.7)

func _move_aquatic(actor: Dictionary, target: Vector3, delta: float) -> void:
	var body: CharacterBody3D = actor.body
	var species := str(actor.record.species)
	var floor_y := _sea_floor(target,species)
	var surface_y: float = ocean.sample_height(target) if ocean else 0.0
	var safe_height := _sea_vertical_range(species,floor_y,surface_y)
	if safe_height.x > safe_height.y:
		target = _vector(actor.record.get("home",actor.record.position))
		floor_y = _sea_floor(target,species)
		surface_y = ocean.sample_height(target) if ocean else 0.0
		safe_height = _sea_vertical_range(species,floor_y,surface_y)
	else:
		target.y = clampf(target.y,safe_height.x,safe_height.y)
	var direction := target-body.position
	body.velocity = direction.normalized()*minf(3.0,direction.length())
	body.move_and_slide()
	var current_range := _sea_vertical_range(species,_sea_floor(body.position,species),ocean.sample_height(body.position) if ocean else 0.0)
	if current_range.x <= current_range.y:
		body.position.y = clampf(body.position.y,current_range.x,current_range.y)

func _attack_player(mob: Dictionary, player_id: String, world: RefCounted) -> bool:
	if mob.safe_zone or not world.players.has(player_id):
		return false
	var player: Dictionary = world.players[player_id]
	if not player.online or not player.alive or player.safe_zone:
		return false
	var now := Time.get_unix_time_from_system()
	player.health = maxf(0.0,float(player.health)-(11.0 if mob.rarity == "uncommon" else 8.0))
	player.last_combat = now
	if world.crews.has(player.crew_id):
		world.crews[player.crew_id].last_combat = now
	world.revision += 1
	if player.health <= 0.0:
		var location := _vector(player.position)
		var sea: bool = archipelago.sample_ground_height(location.x,location.z) < 0.0 if archipelago else location.y < 0.0
		world.kill_player(player_id,sea)
	return true

func damage_mob(mob_id: String, attacker_id: String, amount: float, world: RefCounted) -> Dictionary:
	if not _can_author() or not is_finite(amount) or amount <= 0.0 or not world.mobs.has(mob_id) or not world.players.has(attacker_id):
		return {"ok":false,"error":"Invalid creature damage."}
	var mob: Dictionary = world.mobs[mob_id]
	var attacker: Dictionary = world.players[attacker_id]
	if not mob.alive or mob.safe_zone or not attacker.online or not attacker.alive or attacker.safe_zone:
		return {"ok":false,"error":"Combat is not allowed here."}
	if archipelago and (archipelago.is_safe_zone(_vector(mob.position)) or archipelago.is_safe_zone(_vector(attacker.position))):
		return {"ok":false,"error":"Starter harbours prevent combat."}
	var now := Time.get_unix_time_from_system()
	attacker.last_combat = now
	if world.crews.has(attacker.crew_id):
		world.crews[attacker.crew_id].last_combat = now
	if amount >= float(mob.health):
		var result: Dictionary = world.kill_mob(mob_id,attacker_id)
		if result.get("ok",false):
			_remove_actor(mob_id)
		return result
	mob.health = maxf(0.0,float(mob.health)-amount)
	world.revision += 1
	return {"ok":true,"health":mob.health}

func _reconcile_world(world: RefCounted) -> void:
	var profile_start_us := Time.get_ticks_usec() if _profile_stream else 0
	var actors_before := actors.size()
	if _streaming_active():
		var candidates: Array[Dictionary] = []
		for mob_id in world.mobs:
			var record: Dictionary = world.mobs[mob_id]
			if not MODELS.has(record.get("species","")) or not record.get("alive",false):
				continue
			var score := _stream_score(record,str(mob_id))
			if score != INF:
				candidates.append({"id":str(mob_id),"score":score})
		candidates.sort_custom(Callable(self,"_stream_candidate_before"))
		var wanted: Dictionary = {}
		for index in mini(candidates.size(),MAX_ACTIVE_ACTORS):
			wanted[candidates[index].id] = true
		for mob_id in actors.keys():
			if not wanted.has(mob_id):
				_remove_actor(mob_id)
		for candidate in candidates:
			var mob_id := str(candidate.id)
			if not wanted.has(mob_id):
				break
			var record: Dictionary = world.mobs[mob_id]
			if not actors.has(mob_id):
				_create_actor(record)
			if actors.has(mob_id):
				actors[mob_id].record = record
		_profile_reconcile(profile_start_us,actors_before,world)
		return
	for mob_id in world.mobs:
		var record: Dictionary = world.mobs[mob_id]
		if not MODELS.has(record.species) or not record.alive:
			_remove_actor(mob_id)
			continue
		if not actors.has(mob_id):
			_create_actor(record)
		if actors.has(mob_id):
			actors[mob_id].record = record
	for mob_id in actors.keys():
		if not world.mobs.has(mob_id):
			_remove_actor(mob_id)
	_profile_reconcile(profile_start_us,actors_before,world)

func _profile_reconcile(start_us: int, actors_before: int, world: RefCounted) -> void:
	if not _profile_stream: return
	var elapsed_us := Time.get_ticks_usec()-start_us
	if elapsed_us >= 20000:
		print("CREATURE_STREAM_PROFILE reconcile_us=",elapsed_us," actors_before=",actors_before," actors_after=",actors.size()," mobs=",world.mobs.size()," recipes=",_recipes.size())

func _create_actor(record: Dictionary) -> void:
	var profile_start_us := Time.get_ticks_usec() if _profile_stream else 0
	var species := str(record.species)
	if not MODELS.has(species):
		return
	var supplied_model := ResourceLoader.exists(MODELS[species])
	var model_path: String = MODELS[species] if supplied_model else LEGACY_MODELS.get(species, "")
	if not ResourceLoader.exists(model_path):
		return
	var first_model_load := not _model_cache.has(species)
	if first_model_load:
		_model_cache[species] = load(model_path)
	if _motion_shader == null:
		_motion_shader = Shader.new()
		_motion_shader.code = MOTION_SHADER
	var body := CharacterBody3D.new()
	if Catalog.SPECIES[species].domain in ["shore", "land"]:
		# Ground height is authored below; floor classification adds recovery passes.
		body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.name = ("Creature_"+str(record.id)).validate_node_name()
	body.collision_layer = 8
	body.collision_mask = 1|4
	body.set_meta("mob_id",str(record.id))
	body.add_to_group("creatures")
	var shape_node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	var collider: Array = COLLIDERS[species]
	shape.height = float(collider[1])
	shape.radius = float(collider[0])
	shape_node.shape = shape
	shape_node.position.y = float(collider[2])
	body.add_child(shape_node)
	var visual: Node3D = _model_cache[species].instantiate()
	body.add_child(visual)
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	var animation_player: AnimationPlayer = players[0] if not players.is_empty() else null
	var idle_clip := _animation_clip(animation_player, ["idle"])
	var move_clip := _animation_clip(animation_player, ["walk", "swim", "fly", "move"])
	if animation_player:
		for clip in [idle_clip,move_clip]:
			if not clip.is_empty():
				animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var rarity_scale := 1.12 if record.get("rarity","") == "uncommon" else 1.0
	visual.scale = Vector3.ONE*rarity_scale
	var materials: Array[ShaderMaterial] = []
	for mesh_node in visual.find_children("*","MeshInstance3D",true,false):
		if supplied_model or DisplayServer.get_name() == "headless":
			continue # Keep imported PBR materials; dedicated servers need no animated GPU materials.
		var instance: MeshInstance3D = mesh_node
		for surface in instance.mesh.get_surface_count():
			var original := instance.get_active_material(surface)
			if not original is StandardMaterial3D:
				continue
			var animated := ShaderMaterial.new()
			animated.shader = _motion_shader
			animated.set_shader_parameter("base_color",original.albedo_color)
			animated.set_shader_parameter("has_texture",original.albedo_texture != null)
			if original.albedo_texture:
				animated.set_shader_parameter("base_texture",original.albedo_texture)
			animated.set_shader_parameter("roughness_value",original.roughness)
			animated.set_shader_parameter("metal",original.metallic)
			animated.set_shader_parameter("glow",original.emission if original.emission_enabled else Color.BLACK)
			animated.set_shader_parameter("winged",species == "threadwing")
			instance.set_surface_override_material(surface,animated)
			materials.append(animated)
	add_child(body)
	body.position = _vector(record.position)
	body.rotation.y = float(record.get("yaw",0.0))
	var phase := float(str(record.id).hash()%1000)/100.0
	actors[record.id] = {"body":body,"visual":visual,"materials":materials,"animation_player":animation_player,"idle_clip":idle_clip,"move_clip":move_clip,"hit_radius":float(collider[0]),"record":record,"goal":body.position,"state":"idle","cooldown":0.75,"decision":0.0,"phase_offset":phase,"phase":phase,"route":PackedVector3Array(),"route_index":0,"route_target":body.position,"route_timer":0.0,"route_revision":-1,"target_position":body.position,"target_yaw":body.rotation.y}
	if animation_player and not idle_clip.is_empty() and DisplayServer.get_name() != "headless":
		animation_player.play(idle_clip)
	if _profile_stream:
		var elapsed_us := Time.get_ticks_usec()-profile_start_us
		if elapsed_us >= 20000:
			print("CREATURE_STREAM_PROFILE create_actor_us=",elapsed_us," species=",species," first_model_load=",first_model_load," supplied=",supplied_model," actor_id=",str(record.id))

func _remove_actor(mob_id: String) -> void:
	if not actors.has(mob_id):
		return
	var body: CharacterBody3D = actors[mob_id].body
	body.collision_layer = 0
	body.hide()
	body.queue_free()
	actors.erase(mob_id)

func _animation_clip(player: AnimationPlayer, names: Array[String]) -> String:
	if player == null:
		return ""
	for name in player.get_animation_list():
		var label := str(name).to_lower()
		for candidate in names:
			if label.contains(candidate):
				return str(name)
	return ""

func _animate(actor: Dictionary, delta: float, speed: float) -> void:
	actor.phase = float(actor.phase)+delta
	var player: AnimationPlayer = actor.animation_player
	if player and DisplayServer.get_name() != "headless":
		var clip: String = actor.move_clip if speed > 0.15 and not actor.move_clip.is_empty() else actor.idle_clip
		if not clip.is_empty() and player.current_animation != clip:
			player.play(clip,0.2)
	for material_value in actor.materials:
		material_value.set_shader_parameter("phase",float(actor.phase))
		material_value.set_shader_parameter("activity",clampf(speed/1.3,0.08,1.7))
	var visual: Node3D = actor.visual
	if actor.record.species == "threadwing" and player == null:
		visual.position.y = sin(float(actor.phase)*2.4)*0.09
		visual.rotation.z = sin(float(actor.phase)*1.9)*0.035
	elif actor.record.species == "kettleback" and actor.materials.is_empty() and player == null:
		var stride := clampf(speed / 1.3, 0.0, 1.0)
		visual.position.y = maxf(0.0, sin(float(actor.phase)*8.0)) * 0.035 * stride
		visual.rotation.z = sin(float(actor.phase)*8.0) * 0.025 * stride

func simulation_snapshot(world: RefCounted) -> Dictionary:
	var packet := {}
	for mob_id in actors:
		if not world.mobs.has(mob_id) or not world.mobs[mob_id].alive:
			continue
		var record: Dictionary = world.mobs[mob_id]
		packet[mob_id] = {"id":mob_id,"species":record.species,"rarity":record.rarity,"position":record.position.duplicate(),"yaw":float(record.get("yaw",0.0)),"health":record.health,"alive":true,"state":record.get("state","idle"),"phase":float(actors[mob_id].phase)}
	return packet

func sync_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.get("mobs") is Dictionary:
		return
	_client_mode = not _can_author()
	# Client mode is also usable in an offline replay/review scene.
	if not multiplayer.has_multiplayer_peer():
		_client_mode = true
	var records: Dictionary = snapshot.mobs
	var candidates: Array[Dictionary] = []
	for mob_id in records:
		var record: Dictionary = _merged_sim_record(str(mob_id),records[mob_id])
		if not record.get("alive",false) or not MODELS.has(record.get("species","")):
			_remove_actor(mob_id)
			continue
		var score := _stream_score(record,str(mob_id))
		if score != INF:
			candidates.append({"id":str(mob_id),"score":score,"record":record})
	if _streaming_active():
		candidates.sort_custom(Callable(self,"_stream_candidate_before"))
	var wanted: Dictionary = {}
	for index in mini(candidates.size(),MAX_ACTIVE_ACTORS if _streaming_active() else candidates.size()):
		wanted[candidates[index].id] = true
	for mob_id in actors.keys():
		if not wanted.has(mob_id):
			_remove_actor(mob_id)
	for candidate in candidates:
		var mob_id := str(candidate.id)
		if not wanted.has(mob_id):
			break
		var record: Dictionary = candidate.record
		if not actors.has(mob_id):
			_create_actor(record)
		if not actors.has(mob_id):
			continue
		var actor: Dictionary = actors[mob_id]
		actor.record = record
		actor.target_position = _vector(record.position)
		actor.target_yaw = float(record.get("yaw",0.0))
		actor.phase = float(record.get("phase",actor.phase))

func _merged_sim_record(mob_id: String, incoming: Dictionary) -> Dictionary:
	if not actors.has(mob_id) or incoming.has("island_id") or incoming.has("inventory"):
		return incoming
	# 20 Hz simulation packets are compact. Keep the authoritative island,
	# dungeon, home and loot metadata supplied by the reliable world snapshot.
	var result: Dictionary = actors[mob_id].record.duplicate(false)
	result.merge(incoming,true)
	return result

func _process(delta: float) -> void:
	if not _client_mode:
		return
	for actor in actors.values():
		var body: CharacterBody3D = actor.body
		var distance: float = body.position.distance_to(actor.target_position)
		if distance > 12.0:
			body.position = actor.target_position
		else:
			body.position = body.position.lerp(actor.target_position,1.0-exp(-delta*14.0))
		body.rotation.y = lerp_angle(body.rotation.y,float(actor.target_yaw),1.0-exp(-delta*14.0))
		_animate(actor,delta,distance*14.0)

static func _biome_key(value: String) -> String:
	return value.to_lower().replace(" ","_")

static func _vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.ZERO

static func _array(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
