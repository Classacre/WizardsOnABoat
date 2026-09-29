extends Node3D
## Host owns physics and progression; clients predict their own movement and render snapshots.

const WizardScript = preload("res://scripts/actors/wizard.gd")
const BoatScript = preload("res://scripts/actors/boat.gd")
const HudScript = preload("res://scripts/ui/sea_hud.gd")
const OceanScript = preload("res://scripts/world/ocean.gd")
const WorldScript = preload("res://scripts/world/archipelago.gd")
const SkyScript = preload("res://scripts/world/sky.gd")
const CreatureScript = preload("res://scripts/actors/creature_manager.gd")
const SECONDS_PER_GAME_HOUR := 60.0
const SUPPLIED_MODELS := {
	"barrel": "barrel",
	"cottage": "cottage",
	"crate": "crate",
	"dock": "dock",
	"hearthstone": "hearth_pad",
	"lantern": "lantern",
	"loot_chest": "loot_chest",
	"ruin_arch": "ruin_arch",
	"shop": "cottage",
	"tide_gate": "tide_gate",
}

var ocean: Node3D
var archipelago: Node3D
var sky: Node3D
var hud: CanvasLayer
var preview_camera: Camera3D
var scenery: Node3D
var creature_manager: Node3D
var preview_boat: Node3D
var wizards: Dictionary = {}
var boats: Dictionary = {}
var chests: Dictionary = {}
var projectiles: Array[Dictionary] = []
var creatures: Dictionary = {}
var interactables: Array[Dictionary] = []
var snapshot: Dictionary = {}
var local_wizard: CharacterBody3D
var current_recipe: Array = []
var current_spell := "Empty spellbook"
var current_staff := ""
var in_game := false
var modal_open := true
var simulation_time := 0.0
var snapshot_timer := 0.0
var survival_timer := 0.0
var selected_target: Dictionary = {}
var showcase := false
var capture_path := ""
var capture_timer := 0.0
var capture_frames: Array[float] = []
var _network_sequence := 0
var _built_seed := 7319
var _built_generator := 2
var _stream_timer := 0.0
var _poi_nodes: Dictionary = {}
var _stream_publish_pending := false
var _last_input: Dictionary = {}
var _projectile_visuals: Dictionary = {}
var _scenery_scenes: Dictionary = {}
var _scenery_collision_shapes: Dictionary = {}
var _profile_stream := OS.has_environment("SPELLWAKE_PROFILE_STREAM")
var _projectile_prewarmed := false
var _quickstart_requested := false
var _dev_last_spawn_msec := 0
var _dev_suppress_cast_until_msec := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--showcase": showcase = true
		if arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
		if arg == "--quickstart": _quickstart_requested = true
	_prepare_projectile_visuals()
	_setup_input()
	Session.state_changed.connect(_receive_state)
	Session.input_received.connect(_receive_input)
	Session.cast_requested.connect(_cast)
	Session.staff_cast_requested.connect(_cast_staff)
	Session.action_requested.connect(_action)
	Session.simulation_received.connect(_receive_simulation)
	Session.player_joined.connect(_player_joined)
	Session.player_left.connect(_player_left)
	_build_world(7319)
	hud = HudScript.new()
	add_child(hud)
	hud.host_requested.connect(_host)
	hud.join_requested.connect(_join)
	hud.dev_requested.connect(_open_dev_menu)
	hud.dev_action.connect(_dev_action)
	hud.action.connect(func(name_value:String,data:Dictionary):
		if name_value == "leave": _leave()
		else: Session.request_action(name_value,data)
	)
	hud.spell_selected.connect(_select_spell)
	hud.staff_selected.connect(func(id:String):current_staff=id;hud.close_panel();hud.spell_label.text="INSCRIBED STAFF  ·  LEFT CLICK")
	hud.modal_changed.connect(func(value:bool):
		modal_open=value
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	)
	Session.connection_status.connect(hud.show_notice)
	if showcase:
		hud.hide()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_prewarm_projectile_visuals.call_deferred()

func _prepare_projectile_visuals() -> void:
	if not _projectile_visuals.is_empty(): return
	for kind in ["wind","ember"]:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("91f9e4") if kind == "wind" else Color("ffb86a")
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 2
		var orb_mesh := SphereMesh.new()
		orb_mesh.radius = 0.14
		orb_mesh.height = 0.28
		orb_mesh.material = material
		var ring_meshes: Array[Mesh] = []
		for i in 3:
			var torus := TorusMesh.new()
			torus.inner_radius = 0.22+float(i)*0.045
			torus.outer_radius = 0.245+float(i)*0.045
			torus.rings = 24
			torus.ring_segments = 6
			torus.material = material
			ring_meshes.append(torus)
		_projectile_visuals[kind] = {"orb":orb_mesh,"rings":ring_meshes}

func _make_projectile_visual(kind: String) -> Dictionary:
	var resources: Dictionary = _projectile_visuals[kind]
	var orb := MeshInstance3D.new()
	orb.mesh = resources.orb
	var rings: Array[Node3D] = []
	for ring_mesh in resources.rings:
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		orb.add_child(ring)
		ring.rotation = Vector3(PI/2,0,0)
		rings.append(ring)
	return {"node":orb,"rings":rings}

func _prewarm_projectile_visuals() -> void:
	if DisplayServer.get_name() != "headless":
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera:
			var warmups: Array[Node3D] = []
			for kind in ["wind","ember"]:
				var visual: Dictionary = _make_projectile_visual(kind)
				var orb: Node3D = visual.node
				orb.scale = Vector3.ONE*0.02
				camera.add_child(orb)
				orb.position = Vector3(-0.035 if kind == "wind" else 0.035,-0.05,-0.2)
				warmups.append(orb)
			await RenderingServer.frame_post_draw
			for orb in warmups:
				if is_instance_valid(orb): orb.queue_free()
	_projectile_prewarmed = true
	if _quickstart_requested and not Session.is_session_active():
		_host("Playtest",7319,"Wayfarer")

func _setup_input() -> void:
	var keys := {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"jump":KEY_SPACE,"dive":KEY_CTRL,"sprint":KEY_SHIFT,"interact":KEY_E,"book":KEY_B,"satchel":KEY_I,"crew":KEY_C,"hearth":KEY_H,"potion":KEY_Q}
	for action_name in keys:
		if not InputMap.has_action(action_name): InputMap.add_action(action_name)
		var event := InputEventKey.new()
		event.physical_keycode=keys[action_name]
		InputMap.action_add_event(action_name,event)

func _build_world(seed_value: int, generator_version: int = 2) -> void:
	_built_seed=seed_value
	_built_generator=generator_version
	if scenery:
		remove_child(scenery)
		scenery.queue_free()
	scenery=Node3D.new()
	scenery.name="ArchipelagoScene"
	add_child(scenery)
	sky=SkyScript.new()
	scenery.add_child(sky)
	archipelago=WorldScript.new()
	scenery.add_child(archipelago)
	archipelago.configure(seed_value,generator_version)
	archipelago.build()
	ocean=OceanScript.new()
	ocean.configure(seed_value)
	scenery.add_child(ocean)
	ocean.set_shore_data(archipelago.shore_texture,Vector2(-512,-512),Vector2(1024,1024))
	creature_manager=CreatureScript.new()
	scenery.add_child(creature_manager)
	creature_manager.configure(archipelago,ocean)
	interactables.clear()
	_poi_nodes.clear()
	for poi in archipelago.pois:
		_add_world_poi(poi)
	# Decorative village follows the approved harbour material and architecture kit.
	for offset in [Vector2(-18,5),Vector2(13,-10),Vector2(-10,-15)]:
		var p:=Vector3(-37+offset.x,0,-48+offset.y)
		p.y=archipelago.sample_ground_height(p.x,p.z)
		var house:=_place_model("cottage",p,scenery,0.35,true)
		if house: house.scale=Vector3.ONE*0.72
	preview_boat=BoatScript.new()
	preview_boat.ship_id="preview"
	preview_boat.ocean=ocean
	preview_boat.archipelago=archipelago
	scenery.add_child(preview_boat)
	preview_boat.position=Vector3(5,0,60)
	preview_boat.heading=-0.7
	var poses:=["wizard_cast","wizard_helm","wizard_green","wizard_rust"]
	var crew_positions:=[Vector3(-0.55,1.18,0.8),Vector3(0,1.18,4.1),Vector3(-1.7,1.18,3.4),Vector3(1.8,1.18,3.0)]
	for i in 4:
		_place_model(poses[i] if ResourceLoader.exists("res://assets/models/%s.glb"%poses[i]) else "wizard",crew_positions[i],preview_boat,0)
	var wind:Node3D=load("res://scripts/world/wind_ribbon.gd").new()
	preview_boat.add_child(wind)
	wind.position=Vector3(-0.4,5.1,0.5)
	preview_camera=Camera3D.new()
	scenery.add_child(preview_camera)
	preview_camera.position=Vector3(6.4,6.4,73)
	preview_camera.fov=50
	preview_camera.far=2000
	preview_camera.look_at(Vector3(6.4,4.0,58))
	preview_camera.current=true
	_refresh_shore_patches([preview_camera.position])
	for boat in boats.values():
		boat.ocean=ocean
		boat.archipelago=archipelago
	for wizard in wizards.values():
		wizard.ocean=ocean
		wizard.archipelago=archipelago
	if in_game and local_wizard and local_wizard.camera:
		local_wizard.camera.current=true
		preview_boat.hide()
		preview_boat.collision_layer=0

func _add_world_poi(poi: Dictionary) -> void:
	if _poi_nodes.has(str(poi.id)): return
	var started := Time.get_ticks_usec() if _profile_stream else 0
	var holder := Node3D.new()
	holder.name = ("POI_"+str(poi.id)).validate_node_name()
	scenery.add_child(holder)
	_poi_nodes[str(poi.id)] = holder
	var at: Vector3 = poi.position
	var biome: String = str(poi.get("biome",archipelago.biome_at(at)))
	match str(poi.kind):
		"shop":
			_place_model("shop",at,holder,PI,true)
			_place_model("shopkeeper",at+Vector3(1,0,5.0),holder,PI)
			interactables.append({"kind":"shop","position":at+Vector3(1,0,5),"name":"Mara's Chandlery","id":poi.id})
		"lighthouse": _place_model("lighthouse",at,holder,0,true)
		"dock":
			_place_model("dock",at-Vector3(0,0.35,0),holder,-0.6,true)
			_place_model("barrel",at+Vector3(1.6,0,0),holder)
			_place_model("crate",at+Vector3(-1.8,0,1.6),holder)
			_place_model("lantern",at+Vector3(1.4,0,-2.0),holder)
		"spawn": _place_model("hearthstone",at,holder)
		"tutorial_ruin", "dungeon":
			if biome in ["Basalt Heath","Glass Dunes"]:
				_place_model("tide_gate",at,holder,0,true)
				_place_module("tide_kit","tide_arch",_flat_surface_offset(at,Vector3(-4,0,-1),Vector2(0.7,1.9)),holder,PI/2,true)
				_place_module("tide_kit","tide_rubble",_flat_surface_offset(at,Vector3(4,0,2),Vector2(1.2,1.3)),holder)
			elif biome == "Mangrove Orchard":
				_place_module("root_kit","root_arch",_flat_surface_offset(at,Vector3(-4,0,-2),Vector2(1.2,2.3)),holder,PI/2,true)
			else:
				_place_model("ruin_arch",at,holder,0,true)
				_place_module("coastal_kit","coastal_arch",_flat_surface_offset(at,Vector3(-3,0,-3),Vector2(1.1,1.7)),holder,PI/2,true)
				_place_module("coastal_kit","coastal_moss",_flat_surface_offset(at,Vector3(4,0,2),Vector2(1.6,1.9)),holder)
			if poi.kind == "dungeon":
				_place_model("loot_chest",at+Vector3(0,0.25,-3),holder)
				interactables.append({"kind":"dungeon","position":at+Vector3(0,0,-3),"id":poi.id,"name":poi.name})
		"landing":
			_place_module("coastal_kit","coastal_pillar",_flat_surface_offset(at,Vector3(3,0,2),Vector2(1.3,1.3)),holder)
		"apprentice_cache":
			_place_model("loot_chest",at,holder)
			interactables.append({"kind":"cache","position":at,"name":"Apprentice's Wind Cache","id":poi.id})
	if _profile_stream:
		var elapsed := float(Time.get_ticks_usec()-started)/1000.0
		if elapsed>30.0: print("STREAM_POI ",poi.id," MS=",elapsed)

func _refresh_shore_patches(anchors: Array[Vector3]) -> void:
	if ocean and archipelago.has_method("shore_patches"):
		ocean.set_shore_patches(archipelago.shore_patches(anchors))

func _apply_stream_changes(changes: Dictionary) -> void:
	for id in changes.get("removed_poi_ids",[]):
		if _poi_nodes.has(str(id)):
			_poi_nodes[str(id)].queue_free()
			_poi_nodes.erase(str(id))
		for index in range(interactables.size()-1,-1,-1):
			if str(interactables[index].get("id","")) == str(id): interactables.remove_at(index)
	for poi in changes.get("added_pois",[]): _add_world_poi(poi)
	if not changes.get("added_islands",[]).is_empty() or not changes.get("removed_island_ids",[]).is_empty():
		if Session.hosting and Session.world:
			# State signals are synchronous; publish only after the current receive/
			# stream pass completes, rather than recursively loading every anchor.
			if creature_manager.seed_world(Session.world)>0: _stream_publish_pending=true
		elif creature_manager and not snapshot.is_empty():
			creature_manager.sync_snapshot(snapshot)

func _ensure_surface_for_position(point: Vector3) -> void:
	if not archipelago or not archipelago.has_method("ensure_at"): return
	_apply_stream_changes(archipelago.ensure_at(point))

func _stream_world() -> void:
	var anchors: Array[Vector3] = []
	if in_game:
		for wizard in wizards.values(): anchors.append(wizard.global_position)
		for boat in boats.values(): anchors.append(boat.global_position)
	if anchors.is_empty(): anchors.append(archipelago.get_spawn_position())
	creature_manager.set_stream_anchors(anchors)
	_apply_stream_changes(archipelago.stream_around(anchors,1))
	var camera := get_viewport().get_camera_3d()
	var shore_anchors: Array[Vector3] = []
	if camera:
		shore_anchors.append(camera.global_position)
	else:
		shore_anchors.append_array(anchors)
	_refresh_shore_patches(shore_anchors)

func _place_model(asset: String, at: Vector3, parent: Node3D, angle:=0.0, collision:=false) -> Node3D:
	var path: String = "res://assets/models/%s.glb" % asset
	if SUPPLIED_MODELS.has(asset):
		var supplied_path: String = "res://assets/models/supplied/%s.glb" % SUPPLIED_MODELS[asset]
		if ResourceLoader.exists(supplied_path):
			path = supplied_path
		elif asset == "cottage":
			path = "res://assets/models/shop.glb"
	if not ResourceLoader.exists(path): return null
	var model: Node3D=_scenery_scene(path).instantiate()
	parent.add_child(model)
	model.position=at
	model.rotation.y=angle
	if collision:
		_add_mesh_collisions(model)
	return model

func _flat_surface_offset(at: Vector3, offset: Vector3, half_size: Vector2) -> Vector3:
	var p := at + offset
	p.y = archipelago.sample_surface_at(p)
	for corner in [Vector2(-half_size.x,-half_size.y),Vector2(-half_size.x,half_size.y),Vector2(half_size.x,-half_size.y),Vector2(half_size.x,half_size.y)]:
		var sample: float = archipelago.sample_surface_at(p+Vector3(corner.x,0,corner.y))
		if absf(sample-p.y) > 0.85:
			return Vector3(NAN,NAN,NAN)
	return p

func _place_module(kit: String, module_name: String, at: Vector3, parent: Node3D, angle:=0.0, collision:=false) -> Node3D:
	if not at.is_finite():
		return null
	var path := "res://assets/models/supplied/%s.glb" % kit
	if not ResourceLoader.exists(path):
		return null
	var source: Node3D = _scenery_scene(path).instantiate()
	var original: Node3D = source.find_child(module_name,true,false) as Node3D
	if original == null:
		source.free()
		return null
	var model: Node3D = original.duplicate()
	source.free()
	parent.add_child(model)
	model.position = at
	model.rotation.y = angle
	if collision:
		_add_mesh_collisions(model)
	return model

func _scenery_scene(path: String) -> PackedScene:
	# Keep a strong reference so each streamed copy reuses the imported scene.
	if not _scenery_scenes.has(path):
		_scenery_scenes[path] = load(path)
	return _scenery_scenes[path]

func _add_mesh_collisions(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		# Imported arches contain many triangles. Share their immutable collision
		# shapes so the physics BVH is built once, rather than on every island.
		if not _scenery_collision_shapes.has(node.mesh):
			_scenery_collision_shapes[node.mesh] = node.mesh.create_trimesh_shape()
		var shape: Shape3D = _scenery_collision_shapes[node.mesh]
		if shape:
			var body := StaticBody3D.new()
			var collider := CollisionShape3D.new()
			collider.shape = shape
			body.add_child(collider)
			node.add_child(body)
	for child in node.get_children():
		if not child is StaticBody3D: _add_mesh_collisions(child)

func _host(world_name:String,seed_value:int,wizard_name:String,generator_version:int=2) -> void:
	Session.display_name=wizard_name
	if Session.start_host(world_name,seed_value,Session.DEFAULT_PORT,generator_version)!=OK: return
	if Session.world.seed_value!=_built_seed or Session.world.generator_version!=_built_generator:
		_build_world(Session.world.seed_value,Session.world.generator_version)
	for player_id in Session.world.players:
		var data:Dictionary=Session.world.players[player_id]
		if Vector3(data.position[0],data.position[1],data.position[2]).length()<3:
			Session.world.update_player_position(player_id,_safe_spawn(),true)
	for ship_id in Session.world.ships:
		var ship:Dictionary=Session.world.ships[ship_id]
		if not ship.has("runtime_placed"):
			var berth:=_berth_position(Session.world.ships.keys().find(ship_id))
			Session.world.update_ship_position(ship_id,berth,true)
			if boats.has(ship_id): boats[ship_id].position=berth
			ship["runtime_placed"]=true
	Session.publish_state()
	creature_manager.seed_world(Session.world)
	_enter_game()

func _join(address:String,wizard_name:String) -> void:
	Session.display_name=wizard_name
	Session.join_host(address)

func _enter_game() -> void:
	if in_game: return
	in_game=true
	preview_boat.hide()
	preview_boat.collision_layer=0
	for child in preview_boat.get_children():
		if child is CollisionObject3D: child.collision_layer=0
	hud.entered_world()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	modal_open=false
	if local_wizard and local_wizard.camera: local_wizard.camera.current=true

func _leave() -> void:
	Session.stop_session()
	get_tree().reload_current_scene()

func _player_joined(player_id:String,_peer_id:int) -> void:
	if not Session.hosting: return
	var p:Dictionary=Session.world.players[player_id]
	if _vec(p.position).length()<3 or _vec(p.position).distance_to(archipelago.get_spawn_position())<2.2:
		Session.world.update_player_position(player_id,_safe_spawn(),true)

func _safe_spawn() -> Vector3:
	var point:Vector3=archipelago.get_spawn_position()+Vector3(3.2,0,1.0)
	point.y=archipelago.sample_ground_height(point.x,point.z)+0.35
	return point

func _berth_position(index:int) -> Vector3:
	# Berths hug the southeast quay, inside harbour protection and outside terrain.
	var candidate:=Vector3(-7+float(index%3)*5,0,-28-float(index/3)*12)
	for j in 22:
		if archipelago.sample_ground_height(candidate.x,candidate.z)<-1.0 and archipelago.is_safe_zone(candidate): return candidate
		candidate+=Vector3(0.8,0,-0.8)
	return candidate

func _release_helm(player_id:String) -> void:
	if not wizards.has(player_id): return
	var id:String=wizards[player_id].helm_id
	if boats.has(id) and boats[id].pilot_id==player_id:
		boats[id].pilot_id="";boats[id].throttle=0;boats[id].steering=0
	wizards[player_id].helm_id=""

func _player_left(player_id:String,_peer_id:int) -> void:
	if wizards.has(player_id):
		wizards[player_id].queue_free()
		wizards.erase(player_id)
	for boat in boats.values():
		if boat.pilot_id==player_id: boat.pilot_id="";boat.throttle=0

func _receive_state(data:Dictionary) -> void:
	snapshot=data
	if data.get("seed",_built_seed)!=_built_seed or int(data.get("generator_version",1))!=_built_generator:
		_build_world(int(data.seed),int(data.get("generator_version",1)))
	var stream_anchors: Array[Vector3] = []
	for player_record in data.get("players",{}).values():
		if player_record.get("online",false): stream_anchors.append(_vec(player_record.position))
	for ship_record in data.get("ships",{}).values():
		if ship_record.get("active",false) and ship_record.get("alive",false): stream_anchors.append(_vec(ship_record.position))
	creature_manager.set_stream_anchors(stream_anchors)
	for ship_record in data.get("ships",{}).values():
		if ship_record.get("active",false) and ship_record.get("alive",false): _ensure_surface_for_position(_vec(ship_record.position))
	for player_id in data.get("players",{}):
		var player_record: Dictionary = data.players[player_id]
		if player_record.get("online",false):
			_ensure_surface_for_position(_vec(player_record.position))
			_ensure_dungeon_for_position(_vec(player_record.position))
	for mob_id in data.get("mobs",{}):
		var mob_record: Dictionary = data.mobs[mob_id]
		if mob_record.get("alive",false) and not str(mob_record.get("dungeon_id","")).is_empty():
			_ensure_dungeon_for_position(_vec(mob_record.position))
	if creature_manager and not Session.hosting: creature_manager.sync_snapshot(data)
	for ship_id in data.get("ships",{}):
		var record:Dictionary=data.ships[ship_id]
		if not record.alive or not record.active: continue
		if not boats.has(ship_id):
			var boat:=BoatScript.new()
			boat.ship_id=ship_id
			boat.ocean=ocean
			boat.archipelago=archipelago
			add_child(boat)
			boat.position=_vec(record.position)
			boat.heading=float(record.get("heading",0.0))
			boats[ship_id]=boat
		elif Session.hosting:
			# Domain teleports (new ship / restore) need to reach the simulation once.
			if boats[ship_id].global_position.distance_to(_vec(record.position))>80:
				boats[ship_id].global_position=_vec(record.position)
	for ship_id in boats.keys():
		if not data.ships.has(ship_id) or not data.ships[ship_id].alive or not data.ships[ship_id].active:
			boats[ship_id].queue_free();boats.erase(ship_id)
	for player_id in data.get("players",{}):
		var record:Dictionary=data.players[player_id]
		if not record.online: continue
		if not wizards.has(player_id):
			var wizard:=WizardScript.new()
			wizard.player_id=player_id
			wizard.local_control=player_id==Session.local_player_id
			wizard.ocean=ocean
			wizard.archipelago=archipelago
			add_child(wizard)
			wizard.position=_vec(record.position)
			wizards[player_id]=wizard
			if wizard.local_control:
				local_wizard=wizard
				wizard.yaw=-2.4
		wizards[player_id].alive=record.alive
		if wizards[player_id].visual: wizards[player_id].visual.visible=not wizards[player_id].local_control and record.alive
	for player_id in wizards.keys():
		if not data.players.has(player_id) or not data.players[player_id].online:
			wizards[player_id].queue_free();wizards.erase(player_id)
	for chest_id in data.get("loot",{}):
		var loot_data:Dictionary=data.loot[chest_id]
		if not chests.has(chest_id):
			var chest:=_place_model("loot_chest",_vec(loot_data.position),self)
			if chest: chests[chest_id]=chest
	for chest_id in chests.keys():
		if not data.loot.has(chest_id): chests[chest_id].queue_free();chests.erase(chest_id)
	if local_wizard and hud:
		_enter_game()
		var p:Dictionary=data.players.get(Session.local_player_id,{})
		if current_recipe.is_empty() and not p.get("spells",{}).is_empty():
			var spell_name:String=p.spells.keys()[0]
			_select_spell(p.spells[spell_name],spell_name)

func _receive_input(_peer_id:int,data:Dictionary) -> void:
	var id:String=data.player_id
	if wizards.has(id): wizards[id].input_data=data

func _physics_process(delta:float) -> void:
	var physics_started := Time.get_ticks_usec() if _profile_stream else 0
	simulation_time+=delta
	ocean.set_simulation_time(simulation_time)
	creature_manager.time_of_day = fposmod(12.0 + simulation_time / SECONDS_PER_GAME_HOUR, 24.0)
	if int(simulation_time) != int(simulation_time-delta):
		sky.set_time_of_day(creature_manager.time_of_day)
	if not in_game:
		preview_boat.simulate(delta)
		ocean.set_ship_wakes([Vector4(preview_boat.position.x,preview_boat.position.z,preview_boat.heading,5.0)])
		return
	if local_wizard:
		_network_sequence+=1
		var move:=Vector2.ZERO if modal_open else Input.get_vector("left","right","forward","back")
		_last_input={"move_x":move.x,"move_y":move.y,"yaw":wrapf(local_wizard.yaw,-PI,PI),"pitch":local_wizard.pitch,"jump":not modal_open and Input.is_action_pressed("jump"),"sprint":not modal_open and Input.is_action_pressed("sprint"),"ascend":not modal_open and Input.is_action_pressed("jump"),"descend":not modal_open and Input.is_action_pressed("dive"),"sequence":_network_sequence}
		Session.submit_input(_last_input)
		if not Session.hosting:
			local_wizard.input_data=_last_input
			local_wizard.simulate(delta,boats)
	if Session.hosting:
		var creature_started := Time.get_ticks_usec() if _profile_stream else 0
		var creature_changed: bool = creature_manager.simulate(delta,Session.world,wizards)
		if _profile_stream and Time.get_ticks_usec()-creature_started>30000:
			print("STREAM_CREATURE_SIM_MS=",float(Time.get_ticks_usec()-creature_started)/1000.0)
		if creature_changed: Session.publish_state()
		var boat_previous_inverses: Dictionary = {}
		for ship_id in boats:
			var boat:Node3D=boats[ship_id]
			boat.steering=0;boat.throttle=0
			if not boat.pilot_id.is_empty() and wizards.has(boat.pilot_id) and wizards[boat.pilot_id].helm_id==ship_id and Session.world.can_pilot(boat.pilot_id,ship_id):
				var pilot:Node=wizards[boat.pilot_id]
				boat.steering=-float(pilot.input_data.get("move_x",0))
				boat.throttle=-float(pilot.input_data.get("move_y",0))
			else: boat.pilot_id=""
			boat.simulate(delta)
			boat_previous_inverses[ship_id] = boat.last_transform.affine_inverse()
			Session.world.update_ship_position(ship_id,boat.global_position,archipelago.is_safe_zone(boat.global_position))
			Session.world.ships[ship_id]["heading"]=boat.heading
		for player_id in wizards:
			var wizard:Node3D=wizards[player_id]
			if not wizard.helm_id.is_empty() and (not boats.has(wizard.helm_id) or boats[wizard.helm_id].pilot_id!=player_id or not Session.world.can_pilot(player_id,wizard.helm_id)):
				_release_helm(player_id)
			for ship_id in boats:
				var boat: Node3D = boats[ship_id]
				var previous_inverse: Transform3D = boat_previous_inverses[ship_id]
				var previous_local:Vector3=previous_inverse*wizard.global_position
				if not wizard.dev_fly_enabled and wizard.helm_id.is_empty() and absf(previous_local.x)<3.1 and absf(previous_local.z)<5.5 and previous_local.y>0.6 and previous_local.y<3.5:
					wizard.aboard_id=boat.ship_id
					wizard.global_position=boat.global_transform*previous_local
			wizard.simulate(delta,boats)
			Session.world.update_player_position(player_id,wizard.global_position,archipelago.is_safe_zone(wizard.global_position))
		_update_projectiles(delta)
		survival_timer+=delta
		if survival_timer>1:
			survival_timer=0
			for player_id in wizards:
				var wizard:Node=wizards[player_id]
				if wizard.alive and not wizard.dev_fly_enabled and (wizard.breath<=0 or wizard.global_position.y < -80):
					var p:Dictionary=Session.world.players[player_id]
					p.health=maxf(0,p.health-14)
					if p.health<=0: Session.world.kill_player(player_id,true);Session.publish_state()
		snapshot_timer+=delta
		if snapshot_timer>=0.05:
			snapshot_timer=0
			_broadcast_simulation()
	else:
		_update_projectiles(delta,false)
	var wakes:Array[Vector4]=[]
	for boat in boats.values(): wakes.append(Vector4(boat.position.x,boat.position.z,boat.heading,boat.speed))
	ocean.set_ship_wakes(wakes)
	for chest_id in chests:
		if snapshot.loot.get(chest_id,{}).get("floating",false):
			chests[chest_id].position.y=ocean.sample_height(chests[chest_id].position)+0.2
			chests[chest_id].rotation.z=sin(simulation_time*1.4)*0.08
	if _profile_stream and Time.get_ticks_usec()-physics_started>30000:
		print("STREAM_SCRIPT_PHYSICS_MS=",float(Time.get_ticks_usec()-physics_started)/1000.0)

func _process(delta:float) -> void:
	_stream_timer += delta
	if _stream_timer>=0.15:
		_stream_timer=0.0
		_stream_world()
	elif archipelago.has_pending_stream():
		_apply_stream_changes(archipelago.advance_stream())
	if _stream_publish_pending and Session.hosting and Session.world:
		_stream_publish_pending=false
		Session.publish_state()
	if in_game and local_wizard:
		selected_target=_nearest_interaction(local_wizard.global_position)
		var hint:=""
		if not local_wizard.helm_id.is_empty(): hint="W / S  Sail   A / D  Steer   E  Release helm"
		elif not selected_target.is_empty(): hint="E  ·  "+str(selected_target.name)
		var area:="The Great Sea"
		var current_dungeon: String = archipelago.dungeon_at(local_wizard.global_position)
		if not current_dungeon.is_empty():
			area = str(archipelago.get_dungeon(current_dungeon).name)
		else:
			for island in archipelago.island_records:
				if local_wizard.global_position.distance_to(island.center)<island.radius+20:
					area=island.name;break
		hud.update_player(snapshot,Session.local_player_id,local_wizard,area,hint)
		if snapshot.get("players",{}).get(Session.local_player_id,{}).get("learned",[]).is_empty():
			for item in interactables:
				if item.kind=="cache":
					var meters:float=local_wizard.position.distance_to(item.position)
					hud.objective.text="Follow the stone path to the wind cache  ◇  %d m"%meters
		sky.set_underwater(local_wizard.head_underwater,maxf(0,-local_wizard.global_position.y))
	if not capture_path.is_empty():
		capture_timer+=delta
		if capture_timer>5: capture_frames.append(delta)
		if capture_timer>12:
			var path:=capture_path
			capture_path=""
			_capture.call_deferred(path)

func _input(event: InputEvent) -> void:
	if in_game and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		if modal_open and hud.current_panel == "dev": hud.close_panel()
		else: _open_dev_menu()
		get_viewport().set_input_as_handled()

func _unhandled_input(event:InputEvent) -> void:
	if not in_game: return
	if event is InputEventMouseMotion and not modal_open and local_wizard:
		local_wizard.aim(event.relative)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if modal_open: hud.close_panel()
			else: hud.open_pause()
			return
		if modal_open: return
		match event.physical_keycode:
			KEY_B: hud.open_book()
			KEY_I: hud.open_inventory()
			KEY_C: hud.open_crews()
			KEY_H: Session.request_action("hearthstone",{})
			KEY_Q: Session.request_action("interact",{"kind":"potion"})
			KEY_E: _interact()
			KEY_1: _select_index(0)
			KEY_2: _select_index(1)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and not modal_open and local_wizard and Time.get_ticks_msec()>=_dev_suppress_cast_until_msec:
		if not current_staff.is_empty(): Session.request_staff_cast(current_staff,local_wizard.get_eye_position(),local_wizard.get_aim_direction())
		elif current_recipe.is_empty(): hud.show_notice("Find the apprentice's wind cache in the old ruin to learn your first spells.")
		else: Session.request_cast(current_recipe,local_wizard.get_eye_position(),local_wizard.get_aim_direction())

func _select_index(index:int) -> void:
	var spells:Dictionary=snapshot.get("players",{}).get(Session.local_player_id,{}).get("spells",{})
	if spells.size()>index:
		var key:String=spells.keys()[index]
		_select_spell(spells[key],key)

func _select_spell(recipe:Array,spell_name:String) -> void:
	current_recipe=recipe.duplicate()
	current_staff=""
	current_spell=spell_name
	hud.spell_label.text=spell_name.to_upper()+"  ·  LEFT CLICK"

func _open_dev_menu() -> void:
	if not local_wizard: return
	hud.open_dev(_dev_destinations(),_dev_spawn_catalog(),local_wizard.dev_fly_enabled,Session.hosting)

func _dev_destinations() -> Array:
	var entries: Array = []
	for island in archipelago.island_records:
		entries.append({"id":"island/"+str(island.id),"label":"Island · "+str(island.name)})
	for poi in archipelago.pois:
		entries.append({"id":"poi/"+str(poi.id),"label":"Landmark · "+str(poi.name)})
	if archipelago.has_method("dungeon_landmarks"):
		for landmark in archipelago.dungeon_landmarks():
			entries.append({"id":"dungeon/"+str(landmark.get("id","")),"label":"Dungeon · "+str(landmark.get("label",landmark.get("name","Room")))})
	for ship_id in boats:
		entries.append({"id":"boat/"+str(ship_id),"label":"Ship · "+str(ship_id)})
	for player_id in wizards:
		if player_id != Session.local_player_id:
			entries.append({"id":"player/"+str(player_id),"label":"Player · "+str(snapshot.get("players",{}).get(player_id,{}).get("name",player_id))})
	for mob_id in creature_manager.actors:
		var actor: Dictionary = creature_manager.actors[mob_id]
		entries.append({"id":"mob/"+str(mob_id),"label":"Creature · "+str(GameCatalog.SPECIES[actor.record.species].name)})
	for chest_id in chests:
		entries.append({"id":"loot/"+str(chest_id),"label":"Chest · "+str(chest_id)})
	return entries

func _dev_spawn_catalog() -> Array:
	var entries: Array = [{"id":"chest/salvage","label":"Salvage chest"},{"id":"item/gold","label":"Gold chest · 100"}]
	for species_id in GameCatalog.SPECIES:
		var definition: Dictionary = GameCatalog.SPECIES[species_id]
		if definition.get("boss",false): continue
		entries.append({"id":"mob/"+str(species_id),"label":"Creature · "+str(definition.name)})
	var item_names: Dictionary = {}
	for item_id in GameCatalog.SHOP:
		item_names[item_id] = GameCatalog.SHOP[item_id].name
	for item_id in GameCatalog.SELL_VALUES:
		item_names[item_id] = str(item_id).capitalize()
	for definition in GameCatalog.SPECIES.values():
		for loot_entry in definition.loot:
			item_names[loot_entry.item] = str(loot_entry.item).replace("_"," ").capitalize()
	for item_id in item_names:
		entries.append({"id":"item/"+str(item_id),"label":"Item · "+str(item_names[item_id])})
	return entries

func _dev_action(action_name: String, data: Dictionary) -> void:
	_dev_suppress_cast_until_msec = Time.get_ticks_msec()+250
	if not Session.hosting or Session.world == null or not local_wizard or Session.local_player_id.is_empty():
		hud.show_notice("Developer controls require the host.")
		return
	if not local_wizard.alive:
		hud.show_notice("Respawn before using developer controls.")
		return
	match action_name:
		"fly_toggle":
			if bool(data.get("enabled",false)):
				_release_helm(Session.local_player_id)
				local_wizard.aboard_id = ""
			local_wizard.set_dev_fly(bool(data.get("enabled",false)))
			hud.show_notice("Free fly enabled. Space/Ctrl move vertically." if local_wizard.dev_fly_enabled else "Free fly disabled.")
			hud.close_panel()
		"fly_speed":
			var requested: float = float(data.get("speed",local_wizard.dev_fly_speed))
			if is_finite(requested):
				local_wizard.dev_fly_speed = clampf(requested,5.0,120.0)
				hud.show_notice("Free fly speed: %d m/s" % int(local_wizard.dev_fly_speed))
		"teleport":
			var destination: Dictionary = _dev_destination(str(data.get("id","")))
			if not destination.get("ok",false):
				hud.show_notice(str(destination.get("error","Destination unavailable.")))
				return
			_ensure_surface_for_position(destination.position)
			_release_helm(Session.local_player_id)
			local_wizard.aboard_id = str(destination.get("aboard","")) if not local_wizard.dev_fly_enabled else ""
			local_wizard.velocity = Vector3.ZERO
			local_wizard.knockback = Vector3.ZERO
			local_wizard.global_position = destination.position
			Session.world.update_player_position(Session.local_player_id,local_wizard.global_position,archipelago.is_safe_zone(local_wizard.global_position))
			Session.publish_state()
			_broadcast_simulation()
			hud.show_notice("Teleported to "+str(destination.get("label","destination"))+".")
			hud.close_panel()
		"spawn":
			var now_ms := Time.get_ticks_msec()
			if now_ms-_dev_last_spawn_msec<200: return
			var result: Dictionary = _dev_spawn(str(data.get("id","")))
			if result.get("ok",false):
				_dev_last_spawn_msec = now_ms
				Session.publish_state()
				_broadcast_simulation()
			hud.show_notice(str(result.get("message",result.get("error","Spawn unavailable."))))

func _dev_destination(id: String) -> Dictionary:
	if id.begins_with("island/"):
		var island_id := id.trim_prefix("island/")
		for island in archipelago.island_records:
			if str(island.id) != island_id: continue
			var point: Vector3 = island.center
			for poi in island.pois:
				if poi.kind in ["landing","dock","spawn"]:
					point = poi.position
					break
			point.y = archipelago.sample_surface_at(point)+1.25
			return {"ok":true,"position":point,"label":island.name}
	if id.begins_with("poi/"):
		var poi_id := id.trim_prefix("poi/")
		for poi in archipelago.pois:
			if str(poi.id) != poi_id: continue
			var point: Vector3 = poi.position+Vector3(2.5,0,2.5)
			point.y = archipelago.sample_surface_at(point)+1.25
			return {"ok":true,"position":point,"label":poi.name}
	if id.begins_with("dungeon/") and archipelago.has_method("dungeon_landmarks"):
		var landmark_id := id.trim_prefix("dungeon/")
		for landmark in archipelago.dungeon_landmarks():
			if str(landmark.get("id","")) != landmark_id: continue
			var dungeon_id := str(landmark.get("dungeon_id",""))
			if dungeon_id.is_empty() or archipelago.ensure_dungeon_built(dungeon_id) == null:
				return {"ok":false,"error":"Dungeon is unavailable."}
			return {"ok":true,"position":landmark.position,"label":landmark.get("label","dungeon")}
	if id.begins_with("boat/"):
		var ship_id := id.trim_prefix("boat/")
		if boats.has(ship_id):
			return {"ok":true,"position":boats[ship_id].to_global(Vector3(-1.8,1.25,0)),"aboard":ship_id,"label":"ship"}
	if id.begins_with("player/"):
		var player_id := id.trim_prefix("player/")
		if wizards.has(player_id):
			return {"ok":true,"position":_dev_near_entity(wizards[player_id].global_position),"label":"player"}
	if id.begins_with("mob/"):
		var mob_id := id.trim_prefix("mob/")
		if creature_manager.actors.has(mob_id):
			return {"ok":true,"position":_dev_near_entity(creature_manager.actors[mob_id].body.global_position),"label":"creature"}
	if id.begins_with("loot/"):
		var loot_id := id.trim_prefix("loot/")
		if chests.has(loot_id):
			return {"ok":true,"position":_dev_near_entity(chests[loot_id].global_position),"label":"chest"}
	return {"ok":false,"error":"Destination is no longer available."}

func _dev_near_entity(position_value: Vector3) -> Vector3:
	if archipelago.has_method("dungeon_at"):
		var dungeon_id: String = archipelago.dungeon_at(position_value)
		if not dungeon_id.is_empty():
			archipelago.ensure_dungeon_built(dungeon_id)
			var nearest: Vector3 = archipelago.get_dungeon(dungeon_id).start_position
			var nearest_distance := INF
			for landmark in archipelago.dungeon_landmarks():
				if str(landmark.get("dungeon_id","")) != dungeon_id or archipelago.dungeon_at(landmark.position) != dungeon_id: continue
				var candidate: Vector3 = landmark.position
				var distance: float = position_value.distance_squared_to(candidate)
				if distance < nearest_distance:
					nearest = candidate
					nearest_distance = distance
			return nearest
	var point := position_value+Vector3(2.5,0,2.5)
	point.y = maxf(point.y+1.0,archipelago.sample_surface_at(point)+1.25)
	return point

func _dev_spawn(id: String) -> Dictionary:
	if id == "chest/salvage" or id.begins_with("item/"):
		var contents: Dictionary = {"gold":100,"healing_potion":3,"ancient_coin":5} if id == "chest/salvage" else {}
		if id.begins_with("item/"):
			var item_id := id.trim_prefix("item/")
			if item_id == "driftwood_staff":
				var staff: Dictionary = Session.world.create_staff(Session.local_player_id)
				return {"ok":staff.get("ok",false),"message":"Staff added to inventory.","error":staff.get("error","")}
			if item_id != "gold" and GameCatalog.item_sell_value(item_id) <= 0:
				return {"ok":false,"error":"Unknown item."}
			contents[item_id] = 100 if item_id == "gold" else 1
		if Session.world.loot.size() >= 64:
			return {"ok":false,"error":"Chest limit reached (64)."}
		var chest_position := _dev_spawn_origin()
		var ground_height: float = archipelago.sample_surface_at(chest_position)
		var floating: bool = ground_height < 0.0
		if not floating: chest_position.y = ground_height+0.25
		var chest_id: String = Session.world._create_loot(Session.local_player_id,contents,[chest_position.x,chest_position.y,chest_position.z],floating,archipelago.is_safe_zone(chest_position))
		Session.world.revision += 1
		return {"ok":true,"message":"Spawned chest "+chest_id+"."}
	if id.begins_with("mob/"):
		var species_id := id.trim_prefix("mob/")
		if not GameCatalog.SPECIES.has(species_id) or GameCatalog.SPECIES[species_id].get("boss",false):
			return {"ok":false,"error":"This creature is reserved for its dungeon encounter."}
		if Session.world.mobs.size() >= 256 or creature_manager.actors.size() >= 96:
			return {"ok":false,"error":"Creature limit reached."}
		var definition: Dictionary = GameCatalog.SPECIES[species_id]
		var point := _dev_spawn_origin()
		if archipelago.is_safe_zone(point):
			return {"ok":false,"error":"Move outside the harbour safe zone before spawning a creature."}
		var island_id := ""
		var dungeon_id: String = archipelago.dungeon_at(point) if archipelago.has_method("dungeon_at") else ""
		if not dungeon_id.is_empty():
			archipelago.ensure_dungeon_built(dungeon_id)
			island_id = dungeon_id
			if definition.domain not in ["land","shore"]:
				return {"ok":false,"error":"Only ground creatures can spawn inside a dungeon."}
		for island in archipelago.island_records:
			if not island_id.is_empty(): break
			if Vector2(point.x-island.center.x,point.z-island.center.z).length() < float(island.radius)*1.1 and (not island.sky or definition.domain == "sky"):
				island_id = str(island.id)
				break
		if definition.domain in ["land","shore"]:
			if island_id.is_empty() or (dungeon_id.is_empty() and archipelago.sample_surface_at(point) < 0.0):
				return {"ok":false,"error":"Fly to dry island ground before spawning this creature."}
			point.y = archipelago.sample_surface_at(point)+0.1
		elif definition.domain == "sky":
			point.y = maxf(point.y,archipelago.sample_surface_at(point)+3.3)
		else:
			var bounds: Array = CreatureScript.SEA_BOUNDS[species_id]
			var floor_y: float = archipelago.sample_ground_height(point.x,point.z)
			var surface_y: float = ocean.sample_height(point)
			var low: float = floor_y-float(bounds[0])+0.8
			var high: float = surface_y-float(bounds[1])-0.8
			if low > high:
				return {"ok":false,"error":"Fly over deep water before spawning this creature."}
			point.y = clampf(point.y,low,high)
		var allowed_hours: Array = definition.hours[0]
		var hour: float = (float(allowed_hours[0])+float(allowed_hours[1]))*0.5
		var result: Dictionary = Session.world.spawn_mob(species_id,str(definition.biomes[0]),hour,point)
		if not result.get("ok",false): return result
		var record: Dictionary = Session.world.mobs[result.mob_id]
		record["home"] = [point.x,point.y,point.z]
		record["island_id"] = island_id
		if not dungeon_id.is_empty(): record["dungeon_id"] = dungeon_id
		record["yaw"] = local_wizard.yaw
		record["safe_zone"] = archipelago.is_safe_zone(point)
		return {"ok":true,"message":"Spawned "+str(definition.name)+"."}
	return {"ok":false,"error":"Unknown spawn selection."}

func _dev_spawn_origin() -> Vector3:
	var forward := Vector3(-sin(local_wizard.yaw),0,-cos(local_wizard.yaw))
	var origin: Vector3 = local_wizard.global_position
	var dungeon_id: String = archipelago.dungeon_at(origin) if archipelago.has_method("dungeon_at") else ""
	if not dungeon_id.is_empty():
		for distance_value in [3.0,2.0,1.0]:
			var candidate: Vector3 = origin+forward*distance_value
			if archipelago.dungeon_at(candidate)==dungeon_id and archipelago.dungeon_surface_at(candidate)>0.0:
				return candidate
		return origin
	return origin+forward*7.0

func _nearest_interaction(pos:Vector3) -> Dictionary:
	var best:Dictionary={}
	var distance_value:=6.0
	if archipelago.has_method("dungeon_at"):
		var dungeon_id: String = archipelago.dungeon_at(pos)
		if not dungeon_id.is_empty():
			var dungeon: Dictionary = archipelago.get_dungeon(dungeon_id)
			for kind in ["dungeon_reward","dungeon_exit"]:
				var key := "reward_position" if kind == "dungeon_reward" else "exit_position"
				var point: Vector3 = dungeon.get(key,Vector3.ZERO)
				var distance: float = pos.distance_to(point)
				if distance < distance_value and _dungeon_interaction_visible(pos,point):
					best = {"kind":kind,"id":dungeon_id,"position":point,"name":"Study the reliquary" if kind == "dungeon_reward" else "Leave the dungeon"}
					distance_value = distance
	for item in interactables:
		var d:=pos.distance_to(item.position)
		if d<distance_value: best=item;distance_value=d
	for id in boats:
		var p:Vector3=boats[id].to_global(BoatScript.HELM_LOCAL)
		var d:=pos.distance_to(p)
		if d<distance_value:
			best={"kind":"helm","id":id,"position":p,"name":"Take the helm / claim ship"};distance_value=d
		var ladder:Vector3=boats[id].to_global(Vector3(-3.4,0.2,1.7))
		var ladder_distance:=pos.distance_to(ladder)
		if ladder_distance<4.4 and pos.y<boats[id].position.y+0.9:
			best={"kind":"board","id":id,"position":ladder,"name":"Climb boarding ladder"};distance_value=ladder_distance
	for id in chests:
		var d:=pos.distance_to(chests[id].global_position)
		if d<distance_value: best={"kind":"loot","id":id,"position":chests[id].global_position,"name":"Open floating chest"};distance_value=d
	return best

func _interact() -> void:
	if not local_wizard: return
	if not local_wizard.alive:
		Session.request_action("respawn",{});return
	if not local_wizard.helm_id.is_empty():
		Session.request_action("helm",{"ship_id":""});return
	if selected_target.is_empty(): return
	if local_wizard.dev_fly_enabled and str(selected_target.kind) in ["helm","board"]:
		hud.show_notice("Disable free fly before boarding or piloting a ship.")
		return
	match str(selected_target.kind):
		"shop": hud.open_shop()
		"cache": Session.request_action("claim_cache",{})
		"dungeon": Session.request_action("interact",{"kind":"dungeon","id":selected_target.id})
		"dungeon_reward": Session.request_action("interact",{"kind":"dungeon_reward","id":selected_target.id})
		"dungeon_exit": Session.request_action("interact",{"kind":"dungeon_exit","id":selected_target.id})
		"helm": Session.request_action("helm",{"ship_id":selected_target.id})
		"board": Session.request_action("interact",{"kind":"board","ship_id":selected_target.id})
		"loot": Session.request_action("loot",{"loot_id":selected_target.id})

func _action(player_id:String,action_name:String,data:Dictionary) -> void:
	if not Session.hosting or not wizards.has(player_id): return
	var wizard:Node=wizards[player_id]
	var p:Dictionary=Session.world.players[player_id]
	var result:Dictionary={"ok":false,"error":"Unavailable here."}
	var now:=Time.get_unix_time_from_system()
	if not p.alive and action_name!="respawn": return
	if wizard.dev_fly_enabled and (action_name=="helm" or (action_name=="interact" and str(data.get("kind",""))=="board")):
		_notify_player(player_id,"Disable free fly before boarding or piloting a ship.")
		return
	match action_name:
		"claim_cache":
			if _near_kind(wizard.global_position,"cache",6):
				result=Session.world.claim_apprentice_cache(player_id)
				if result.ok: result["message"]="The wind answers. Gale and Ember are now in your spellbook."
		"save_spell": result=Session.world.save_spell(player_id,str(data.get("name","")),data.get("recipe",[]))
		"teach_staff": result=Session.world.teach_staff(player_id,str(data.get("staff_id","")),str(data.get("spell_name","")))
		"buy", "sell":
			if _near_kind(wizard.global_position,"shop",9):
				var item_id:=str(data.get("item",""))
				if action_name=="buy": result=Session.world.buy_item(player_id,item_id)
				elif item_id=="all_materials":
					result={"ok":true,"message":"Materials sold."}
					for key in p.inventory.keys():
						if not GameCatalog.SHOP.has(key) and GameCatalog.item_sell_value(key)>0: Session.world.sell_item(player_id,key,int(p.inventory[key]))
				else: result=Session.world.sell_item(player_id,item_id)
		"helm":
			var id:=str(data.get("ship_id",""))
			if id.is_empty():
				_release_helm(player_id);result={"ok":true}
			elif boats.has(id) and wizard.global_position.distance_to(boats[id].to_global(BoatScript.HELM_LOCAL))<6:
				var boat:Node=boats[id]
				if not boat.pilot_id.is_empty() and boat.pilot_id!=player_id:
					result={"ok":false,"error":"The helm is occupied."}
				else:
					result={"ok":true} if Session.world.can_pilot(player_id,id) else Session.world.hijack_ship(player_id,id)
					if result.ok:
						for other in boats.values():
							if other.pilot_id==player_id: other.pilot_id=""
						boat.pilot_id=player_id;wizard.helm_id=id
		"loot": result=Session.world.take_loot(player_id,str(data.get("loot_id","")))
		"respawn":
			result=Session.world.respawn_player(player_id)
			if result.ok:
				_release_helm(player_id)
				wizard.global_position=_vec(result.position) if result.aboard else _safe_spawn()
				wizard.breath=30;wizard.velocity=Vector3.ZERO;wizard.helm_id="";wizard.alive=true
		"hearthstone":
			if p.alive and int(p.inventory.get("hearthstone",0))>0 and now-float(p.last_combat)>20:
				_release_helm(player_id)
				wizard.global_position=_safe_spawn()
				wizard.velocity=Vector3.ZERO;wizard.helm_id=""
				result={"ok":true,"message":"The hearthstone carries you home."}
			else: result={"ok":false,"error":"A hearthstone and 20 seconds out of combat are required."}
		"create_crew":
			result=Session.world.create_crew(player_id,str(data.get("name","Wayfarers")),now)
			if result.ok: _release_helm(player_id)
		"join_crew":
			result=Session.world.join_crew(player_id,str(data.get("crew_id","")),now)
			if result.ok: _release_helm(player_id)
		"interact":
			match str(data.get("kind","")):
				"board":
					var id:=str(data.get("ship_id",""))
					if boats.has(id) and wizard.position.distance_to(boats[id].to_global(Vector3(-3.4,0.2,1.7)))<4.5:
						wizard.position=boats[id].to_global(Vector3(-2.45,1.24,1.7))
						wizard.aboard_id=id
						wizard.velocity=Vector3.ZERO;result={"ok":true,"message":"Aboard. The helm is at the stern."}
				"potion":
					if p.alive and int(p.inventory.get("healing_potion",0))>0 and p.health<100:
						p.inventory.healing_potion-=1;p.health=minf(100,p.health+45);result={"ok":true,"message":"Warmth returns. +45 health."}
				"compass":
					if p.inventory.get("reef_compass",0)>0 or p.inventory.get("storm_compass",0)>0:
						var biome := "Glass Dunes" if p.inventory.get("reef_compass",0)>0 else "Stormglass Reef"
						var target := _compass_destination(wizard.position,biome)
						if not target.is_empty():
							var bearing:=fposmod(rad_to_deg(atan2(target.center.x-wizard.position.x,-(target.center.z-wizard.position.z))),360)
							result={"ok":true,"message":"%s · bearing %03d° · %dm"%[target.name,bearing,wizard.position.distance_to(target.center)]}
						else: result={"ok":false,"error":"No matching island within this compass's chart range."}
				"dungeon":
					for poi in interactables:
						if poi.kind=="dungeon" and poi.id==data.get("id","") and wizard.position.distance_to(poi.position)<6:
							var dungeon: Dictionary = archipelago.get_dungeon(str(poi.id))
							if dungeon.is_empty():
								# Existing sky reliquaries retain their original one-time reward.
								result = _grant_dungeon_reward(player_id,str(poi.id))
							elif archipelago.ensure_dungeon_built(str(poi.id)) != null:
								_release_helm(player_id)
								wizard.aboard_id = ""
								wizard.velocity = Vector3.ZERO
								wizard.global_position = dungeon.start_position
								creature_manager.activate_dungeon(Session.world,str(poi.id))
								result={"ok":true,"message":"Entered "+str(poi.name)+". Find the inner reliquary."}
				"dungeon_reward":
					var dungeon_id := str(data.get("id",""))
					if archipelago.dungeon_at(wizard.global_position)==dungeon_id:
						var dungeon: Dictionary = archipelago.get_dungeon(dungeon_id)
						if not dungeon.is_empty() and wizard.global_position.distance_to(dungeon.reward_position)<6.0 and _dungeon_interaction_visible(wizard.global_position,dungeon.reward_position):
							result = _grant_dungeon_reward(player_id,dungeon_id)
				"dungeon_exit":
					var dungeon_id := str(data.get("id",""))
					if archipelago.dungeon_at(wizard.global_position)==dungeon_id:
						var dungeon: Dictionary = archipelago.get_dungeon(dungeon_id)
						if not dungeon.is_empty() and wizard.global_position.distance_to(dungeon.exit_position)<6.0 and _dungeon_interaction_visible(wizard.global_position,dungeon.exit_position):
							_release_helm(player_id)
							wizard.aboard_id = ""
							wizard.velocity = Vector3.ZERO
							wizard.global_position = dungeon.return_position
							result={"ok":true,"message":"Returned to the island."}
	Session.world.update_player_position(player_id,wizard.global_position,archipelago.is_safe_zone(wizard.global_position))
	Session.publish_state()
	_broadcast_simulation()
	_notify_player(player_id,str(result.get("message","Done.")) if result.ok else str(result.get("error","Unavailable.")))

func _grant_dungeon_reward(player_id: String, dungeon_id: String) -> Dictionary:
	var player: Dictionary = Session.world.players[player_id]
	if player.claimed_caches.has(dungeon_id):
		return {"ok":false,"error":"You have already studied this reliquary in this world."}
	player.claimed_caches.append(dungeon_id)
	var glyphs := ["power","range","heal","split"]
	var glyph: String = glyphs[absi(dungeon_id.hash())%glyphs.size()]
	Session.world.learn_glyph(player_id,glyph,"dungeon")
	player.inventory.ancient_coin = int(player.inventory.get("ancient_coin",0))+3
	return {"ok":true,"message":"Discovered glyph: "+glyph.capitalize()+". Three ancient coins recovered."}

func _compass_destination(from: Vector3, biome: String) -> Dictionary:
	var nearest: Dictionary = {}
	var distance := INF
	var candidates: Array = archipelago.island_records.duplicate()
	if archipelago.has_method("sector_manifest"):
		var sector_size: float = WorldScript.ISLAND_GENERATOR.SECTOR_SIZE
		var cell := Vector2i(floori(from.x/sector_size),floori(from.z/sector_size))
		for z in range(cell.y-8,cell.y+9):
			for x in range(cell.x-8,cell.x+9):
				var island: Dictionary = archipelago.sector_manifest(x,z)
				if not island.is_empty(): candidates.append(island)
	for island in candidates:
		if str(island.biome)!=biome: continue
		var candidate: float = from.distance_squared_to(island.center)
		if candidate<distance:
			distance=candidate
			nearest=island
	return nearest

func _dungeon_interaction_visible(from: Vector3, to: Vector3) -> bool:
	# Dungeon walls and floors are static layer 1. Eye-height rays cannot pass
	# through a neighbouring room wall when the two points are only metres apart.
	var query := PhysicsRayQueryParameters3D.create(from+Vector3.UP*1.5,to+Vector3.UP*1.5,1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _near_kind(pos:Vector3,kind:String,distance_value:float) -> bool:
	for item in interactables:
		if item.kind==kind and pos.distance_to(item.position)<distance_value: return true
	return false

func _notify_player(player_id:String,message:String) -> void:
	if player_id==Session.local_player_id: hud.show_notice(message)
	else:
		for peer in Session.peer_player_ids:
			if Session.peer_player_ids[peer]==player_id: _show_notification.rpc_id(peer,message)

@rpc("authority","call_remote","reliable")
func _show_notification(message:String) -> void:
	hud.show_notice(message)

func _cast(player_id:String,recipe:Array,origin:Vector3,direction:Vector3) -> void:
	_cast_staff(player_id,recipe,origin,direction,{})

func _cast_staff(player_id:String,recipe:Array,origin:Vector3,direction:Vector3,modifiers:Dictionary) -> void:
	if not wizards.has(player_id): return
	var wizard:Node=wizards[player_id]
	origin=wizard.get_eye_position()
	var cost:=12.0+float(recipe.size()-2)*4
	if wizard.mana<cost: return
	wizard.mana-=cost
	if recipe[0]=="self":
		if recipe.has("heal"):
			Session.world.players[player_id].health=minf(100,Session.world.players[player_id].health+20)
		if recipe.has("push") or recipe.has("wind"): wizard.knockback+=direction*35+Vector3.UP*14
		Session.publish_state();return
	var speed_value:=32.0*float(modifiers.get("speed_multiplier",1))
	var life:=(3.0 if recipe.has("range") else 1.7)*float(modifiers.get("range_multiplier",1))
	if recipe[0]=="touch": speed_value=18;life=0.18
	var directions:Array[Vector3]=[direction]
	if recipe.has("split"):
		directions.append(direction.rotated(Vector3.UP,0.13));directions.append(direction.rotated(Vector3.UP,-0.13))
	for aim in directions:
		_spawn_projectile(player_id,recipe,origin,aim,speed_value,life,modifiers)
		if not multiplayer.get_peers().is_empty(): _spell_visual.rpc(player_id,recipe,origin,aim,speed_value,life)

@rpc("authority","call_remote","reliable")
func _spell_visual(player_id:String,recipe:Array,origin:Vector3,direction:Vector3,speed_value:float,life:float) -> void:
	_spawn_projectile(player_id,recipe,origin,direction,speed_value,life)

func _spawn_projectile(player_id:String,recipe:Array,origin:Vector3,direction:Vector3,speed_value:float,life:float,modifiers:Dictionary={}) -> void:
	var visual: Dictionary = _make_projectile_visual("wind" if recipe.has("wind") else "ember")
	var orb: MeshInstance3D = visual.node
	var rings: Array[Node3D] = visual.rings
	add_child(orb);orb.position=origin+direction*0.65
	projectiles.append({"node":orb,"owner":player_id,"recipe":recipe,"direction":direction,"speed":speed_value,"life":life,"rings":rings,"modifiers":modifiers})

func _update_projectiles(delta:float,authoritative:=true) -> void:
	for i in range(projectiles.size()-1,-1,-1):
		var shot:Dictionary=projectiles[i]
		shot.life-=delta
		var node:Node3D=shot.node
		var next:Vector3=node.position+shot.direction*shot.speed*delta
		var hit:Dictionary={}
		if authoritative:
			var query:=PhysicsRayQueryParameters3D.create(node.position,next,1|2|4|8)
			if wizards.has(shot.owner): query.exclude=[wizards[shot.owner].get_rid()]
			hit=get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			_apply_impact(shot,hit)
			shot.life=0
		else: node.position=next
		for k in shot.rings.size():
			shot.rings[k].rotation.z+=delta*(3.0+float(k))
		if shot.life<=0: node.queue_free();projectiles.remove_at(i)

func _apply_impact(shot:Dictionary,hit:Dictionary) -> void:
	var collider:Node=hit.collider
	var recipe:Array=shot.recipe
	var modifiers:Dictionary=shot.get("modifiers",{})
	var effect_power:Dictionary={}
	var last_effect:=""
	for glyph in recipe:
		if GameCatalog.GLYPHS.get(glyph,"")=="effect": last_effect=glyph;effect_power[glyph]=float(modifiers.get("power_multiplier",1))
		elif glyph=="power" and not last_effect.is_empty(): effect_power[last_effect]*=1.7
	var power:float=float(effect_power.get("spark",1.0))
	var wind_power:float=float(effect_power.get("wind",effect_power.get("push",1.0)))*float(modifiers.get("impulse_multiplier",1.0))
	if collider.has_meta("sail_ship_id"):
		var id:String=collider.get_meta("sail_ship_id")
		if boats.has(id) and (recipe.has("wind") or recipe.has("push")):
			# Harbour wind works only on your own crew's ship; outsiders cannot shove it.
			if not archipelago.is_safe_zone(boats[id].position) or Session.world.can_pilot(shot.owner,id):
				boats[id].apply_wind(shot.direction,4.5*wind_power)
				if not Session.world.can_pilot(shot.owner,id): _tag_combat(shot.owner,"",id)
	if collider.has_meta("player_id"):
		var id:String=collider.get_meta("player_id")
		if recipe.has("heal") and Session.world.players[id].alive:
			Session.world.players[id].health=minf(100,Session.world.players[id].health+20*float(effect_power.get("heal",1)))
		if Session.world.can_damage(shot.owner,id):
			if recipe.has("spark"): Session.world.apply_damage(shot.owner,id,25*power,Time.get_unix_time_from_system(),wizards[id].position.y<1)
			if recipe.has("wind") or recipe.has("push"):
				wizards[id].knockback+=shot.direction*38*wind_power+Vector3.UP*10
				_tag_combat(shot.owner,id,"")
	if collider.has_meta("ship_id") and recipe.has("spark"):
		Session.world.damage_ship(shot.owner,collider.get_meta("ship_id"),22*power,Time.get_unix_time_from_system())
	if collider.has_meta("mob_id"):
		var id:String=collider.get_meta("mob_id")
		if recipe.has("spark"): creature_manager.damage_mob(id,shot.owner,25*power,Session.world)
		elif recipe.has("wind") or recipe.has("push"):
			creature_manager.damage_mob(id,shot.owner,8*wind_power,Session.world)
	Session.publish_state()

func _tag_combat(attacker:String,target:String,ship_id:String) -> void:
	var now:=Time.get_unix_time_from_system()
	for id in [attacker,target]:
		if Session.world.players.has(id):
			Session.world.players[id].last_combat=now
			Session.world.crews[Session.world.players[id].crew_id].last_combat=now
	if Session.world.ships.has(ship_id):
		var crew:String=Session.world.ships[ship_id].crew_id
		if Session.world.crews.has(crew): Session.world.crews[crew].last_combat=now

func _broadcast_simulation() -> void:
	var packet:={"time":simulation_time,"players":{},"ships":{},"mobs":creature_manager.simulation_snapshot(Session.world)}
	for id in wizards:
		var w:Node3D=wizards[id]
		packet.players[id]={"position":w.position,"yaw":w.yaw,"pitch":w.pitch,"helm":w.helm_id,"aboard":w.aboard_id,"mana":w.mana,"breath":w.breath}
	for id in boats:
		var boat:Node3D=boats[id]
		packet.ships[id]={"position":boat.position,"rotation":boat.rotation,"speed":boat.speed,"heading":boat.heading,"wind":boat.wind_charge}
	Session.broadcast_simulation(packet)

func _receive_simulation(packet:Dictionary) -> void:
	if Session.hosting: return
	simulation_time=float(packet.get("time",simulation_time))
	var stream_anchors: Array[Vector3] = []
	for data in packet.get("players",{}).values(): stream_anchors.append(data.position)
	for data in packet.get("ships",{}).values(): stream_anchors.append(data.position)
	creature_manager.set_stream_anchors(stream_anchors)
	for id in packet.get("players",{}):
		_ensure_surface_for_position(packet.players[id].position)
		_ensure_dungeon_for_position(packet.players[id].position)
	for data in packet.get("ships",{}).values(): _ensure_surface_for_position(data.position)
	for id in packet.get("mobs",{}):
		if str(id).begins_with("dungeon/"):
			_ensure_dungeon_for_position(CreatureScript._vector(packet.mobs[id].position))
	creature_manager.sync_snapshot(packet)
	for id in packet.get("ships",{}):
		if boats.has(id):
			var data:Dictionary=packet.ships[id]
			var previous_transform:Transform3D=boats[id].global_transform
			boats[id].position=data.position
			boats[id].rotation=data.rotation
			boats[id].speed=data.speed;boats[id].heading=data.heading;boats[id].wind_charge=data.wind
			if local_wizard and local_wizard.aboard_id==id and local_wizard.helm_id.is_empty():
				local_wizard.position=boats[id].global_transform*(previous_transform.affine_inverse()*local_wizard.position)
	for id in packet.get("players",{}):
		if wizards.has(id):
			var data:Dictionary=packet.players[id]
			var wizard:Node3D=wizards[id]
			wizard.helm_id=data.helm
			wizard.aboard_id=data.get("aboard","")
			wizard.mana=data.mana;wizard.breath=data.breath
			if id!=Session.local_player_id:
				wizard.position=data.position;wizard.yaw=data.yaw;wizard.pitch=data.pitch;wizard.rotation.y=data.yaw
			elif wizard.position.distance_to(data.position)>1.8:
				wizard.position=data.position

func _vec(value:Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _ensure_dungeon_for_position(position_value: Vector3) -> void:
	if archipelago == null or not archipelago.has_method("dungeon_at"): return
	var dungeon_id: String = archipelago.dungeon_at(position_value)
	if not dungeon_id.is_empty(): archipelago.ensure_dungeon_built(dungeon_id)

func _capture(path:String) -> void:
	await RenderingServer.frame_post_draw
	var image_value:=get_viewport().get_texture().get_image()
	image_value.save_png(path)
	var sum:=0.0
	for dt in capture_frames: sum+=dt
	var fps:=float(capture_frames.size())/maxf(sum,0.0001)
	print("CAPTURE ",path," FPS ",fps," frames ",capture_frames.size())
	get_tree().quit()

