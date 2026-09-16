class_name SeaCreatureManager
extends Node3D
## Server-owned ecology. Static art is animated at the vertex level; persistent
## identities, loot and deaths belong to WorldState and survive host restarts.

const Catalog = preload("res://scripts/data/game_catalog.gd")
const MODELS := {
	"kettleback": "res://assets/models/crab.glb",
	"threadwing": "res://assets/models/glider.glb",
}
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

func configure(island_world: Node3D, water: Node3D) -> void:
	archipelago = island_world
	ocean = water
	if _motion_shader == null:
		_motion_shader = Shader.new()
		_motion_shader.code = MOTION_SHADER

func seed_world(world: RefCounted) -> int:
	if not _can_author():
		return 0
	_client_mode = false
	_recipes.clear()
	if not is_instance_valid(archipelago):
		return 0
	for island in archipelago.island_records:
		if bool(island.get("safe",false)):
			continue
		var biome := str(island.biome)
		var species := "threadwing" if bool(island.sky) else "kettleback"
		if not Catalog.SPECIES[species].biomes.has(_biome_key(biome)):
			continue
		var count := 3 if species == "threadwing" else 4
		for index in count:
			var spawn := _spawn_position(island,index,count,species)
			if not spawn.is_finite() or archipelago.is_safe_zone(spawn):
				continue
			_recipes.append({"key":"wild/%s/%s/%d" % [island.id,species,index],"species":species,"biome":biome,"island_id":str(island.id),"position":spawn,"rarity":"uncommon" if index == count-1 else "common"})
	var created := _spawn_eligible(world)
	_reconcile_world(world)
	return created

func _spawn_position(island: Dictionary, index: int, count: int, species: String) -> Vector3:
	var center: Vector3 = island.center
	var p := center
	if species == "kettleback" and not island.get("paths",[]).is_empty():
		var path: PackedVector3Array = island.paths[0]
		if not path.is_empty():
			# Seed on the authored grade-aware path, not in a random cliff face.
			var sample := clampi(int(path.size()*(0.13+index*0.15)),0,path.size()-1)
			p = path[sample]
	else:
		var angle := float(index)/maxi(count,1)*TAU+0.45
		var radius := float(island.radius)*0.43
		p = center+Vector3(cos(angle)*radius,0,sin(angle)*radius)
	p.y = float(archipelago.sample_surface_at(p))
	if species == "threadwing":
		p.y += 3.3
	return p

func _spawn_eligible(world: RefCounted) -> int:
	var created := 0
	for recipe in _recipes:
		if world.mobs.has(recipe.key):
			continue # Includes dead records: a reconnect must never reroll loot.
		if not Catalog.spawn_allowed(recipe.species,recipe.biome,time_of_day):
			continue
		var result: Dictionary = world.spawn_mob(recipe.species,recipe.biome,time_of_day,recipe.position,recipe.rarity,recipe.key)
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
	_client_mode = false
	var step := minf(delta,0.1)
	_clock += step
	_spawn_clock += step
	var changed := false
	if _spawn_clock >= 2.0:
		_spawn_clock = 0.0
		changed = _spawn_eligible(world) > 0
	_reconcile_world(world)
	for mob_id in actors.keys():
		if not world.mobs.has(mob_id) or not world.mobs[mob_id].alive:
			continue
		var mob: Dictionary = world.mobs[mob_id]
		var actor: Dictionary = actors[mob_id]
		var body: CharacterBody3D = actor.body
		actor.cooldown = maxf(0.0,float(actor.cooldown)-step)
		actor.decision = float(actor.decision)-step
		var domain := str(Catalog.SPECIES[mob.species].domain)
		var target_id := _nearby_player(body.position,world,wizards,13.5 if domain == "shore" else 9.0)
		var target := _vector(mob.get("home",mob.position))
		var chasing := not target_id.is_empty()
		if chasing:
			target = _player_position(target_id,world,wizards)
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
		if archipelago and archipelago.is_safe_zone(body.position):
			body.position = old_position
			body.velocity = Vector3.ZERO
		var distance := old_position.distance_to(body.position)
		if distance > 0.001:
			var direction := body.position-old_position
			body.rotation.y = lerp_angle(body.rotation.y,atan2(-direction.x,-direction.z),1.0-exp(-step*7.0))
		else:
			actor.state = "idle" if not chasing else actor.state
		mob["yaw"] = body.rotation.y
		mob["state"] = actor.state
		mob["phase"] = _clock+float(actor.phase_offset)
		world.update_mob_position(mob_id,body.position,archipelago.is_safe_zone(body.position) if archipelago else false)
		_animate(actor,step,distance/step)
		if chasing and domain == "shore" and not target_id.is_empty() and body.position.distance_to(_player_position(target_id,world,wizards)) < 2.25 and float(actor.cooldown) <= 0.0:
			if _attack_player(mob,target_id,world):
				actor.cooldown = 1.6
				changed = true
	return changed

func _can_author() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()

func _nearby_player(position_value: Vector3, world: RefCounted, wizards: Dictionary, radius: float) -> String:
	var nearest := ""
	var distance := radius
	for player_id in world.players:
		var player: Dictionary = world.players[player_id]
		if not player.online or not player.alive or player.safe_zone:
			continue
		var point := _player_position(player_id,world,wizards)
		if archipelago and archipelago.is_safe_zone(point):
			continue
		var candidate := position_value.distance_to(point)
		if candidate < distance:
			distance = candidate
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
	if archipelago:
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
	body.move_and_slide()
	if archipelago:
		body.position.y = float(archipelago.sample_surface_at(body.position))+0.035

func _navigation_route(island_id: String, from: Vector3, to: Vector3) -> PackedVector3Array:
	if not archipelago or not archipelago.navigation_graphs.has(island_id):
		return PackedVector3Array()
	var graph: Dictionary = archipelago.navigation_graphs[island_id]
	var region: NavigationRegion3D = graph.get("region")
	if region != null and region.is_inside_tree():
		var map := region.get_navigation_map()
		if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
			return NavigationServer3D.map_get_path(map,from,to,true)
	return PackedVector3Array()

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
	# Reserved for genuine modeled sea species; none is represented with substitute art.
	var body: CharacterBody3D = actor.body
	var surface := float(ocean.sample_height(body.position)) if ocean else 0.0
	var floor_y := float(archipelago.sample_ground_height(target.x,target.z)) if archipelago else -20.0
	target.y = clampf(target.y,floor_y+1.0,surface-1.2)
	var direction := target-body.position
	body.velocity = direction.normalized()*minf(3.0,direction.length())
	body.move_and_slide()
	body.position.y = minf(body.position.y,surface-0.6)

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

func _create_actor(record: Dictionary) -> void:
	var species := str(record.species)
	if not MODELS.has(species) or not ResourceLoader.exists(MODELS[species]):
		return
	if not _model_cache.has(species):
		_model_cache[species] = load(MODELS[species])
	if _motion_shader == null:
		_motion_shader = Shader.new()
		_motion_shader.code = MOTION_SHADER
	var body := CharacterBody3D.new()
	body.name = ("Creature_"+str(record.id)).validate_node_name()
	body.collision_layer = 8
	body.collision_mask = 1|4
	body.set_meta("mob_id",str(record.id))
	body.add_to_group("creatures")
	var shape_node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.68 if species == "kettleback" else 0.45
	shape.height = 1.38 if species == "kettleback" else 1.0
	shape_node.shape = shape
	shape_node.position.y = 0.63 if species == "kettleback" else 0.0
	body.add_child(shape_node)
	var visual: Node3D = _model_cache[species].instantiate()
	body.add_child(visual)
	var rarity_scale := 1.12 if record.get("rarity","") == "uncommon" else 1.0
	visual.scale = Vector3.ONE*rarity_scale
	var materials: Array[ShaderMaterial] = []
	for mesh_node in visual.find_children("*","MeshInstance3D",true,false):
		if DisplayServer.get_name() == "headless":
			continue # Dedicated simulation does not allocate animated GPU materials.
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
	actors[record.id] = {"body":body,"visual":visual,"materials":materials,"record":record,"goal":body.position,"state":"idle","cooldown":0.75,"decision":0.0,"phase_offset":phase,"phase":phase,"route":PackedVector3Array(),"route_index":0,"route_target":body.position,"route_timer":0.0,"route_revision":-1,"target_position":body.position,"target_yaw":body.rotation.y}

func _remove_actor(mob_id: String) -> void:
	if not actors.has(mob_id):
		return
	var body: CharacterBody3D = actors[mob_id].body
	body.collision_layer = 0
	body.hide()
	body.queue_free()
	actors.erase(mob_id)

func _animate(actor: Dictionary, delta: float, speed: float) -> void:
	actor.phase = float(actor.phase)+delta
	for material_value in actor.materials:
		material_value.set_shader_parameter("phase",float(actor.phase))
		material_value.set_shader_parameter("activity",clampf(speed/1.3,0.08,1.7))
	var visual: Node3D = actor.visual
	if actor.record.species == "threadwing":
		visual.position.y = sin(float(actor.phase)*2.4)*0.09
		visual.rotation.z = sin(float(actor.phase)*1.9)*0.035

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
	for mob_id in records:
		var record: Dictionary = records[mob_id]
		if not record.get("alive",false) or not MODELS.has(record.get("species","")):
			_remove_actor(mob_id)
			continue
		if not actors.has(mob_id):
			_create_actor(record)
		if not actors.has(mob_id):
			continue
		var actor: Dictionary = actors[mob_id]
		actor.record = record
		actor.target_position = _vector(record.position)
		actor.target_yaw = float(record.get("yaw",0.0))
		actor.phase = float(record.get("phase",actor.phase))
	for mob_id in actors.keys():
		if not records.has(mob_id):
			_remove_actor(mob_id)

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
