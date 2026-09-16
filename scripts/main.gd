extends Node3D
## Host owns physics and progression; clients predict their own movement and render snapshots.

const WizardScript = preload("res://scripts/actors/wizard.gd")
const BoatScript = preload("res://scripts/actors/boat.gd")
const HudScript = preload("res://scripts/ui/sea_hud.gd")
const OceanScript = preload("res://scripts/world/ocean.gd")
const WorldScript = preload("res://scripts/world/archipelago.gd")
const SkyScript = preload("res://scripts/world/sky.gd")
const CreatureScript = preload("res://scripts/actors/creature_manager.gd")

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
var _last_input: Dictionary = {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--showcase": showcase = true
		if arg.begins_with("--capture="): capture_path = arg.trim_prefix("--capture=")
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
	for arg in OS.get_cmdline_user_args():
		if arg == "--quickstart": _host("Playtest",7319,"Wayfarer")

func _setup_input() -> void:
	var keys := {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"jump":KEY_SPACE,"dive":KEY_CTRL,"sprint":KEY_SHIFT,"interact":KEY_E,"book":KEY_B,"satchel":KEY_I,"crew":KEY_C,"hearth":KEY_H,"potion":KEY_Q}
	for action_name in keys:
		if not InputMap.has_action(action_name): InputMap.add_action(action_name)
		var event := InputEventKey.new()
		event.physical_keycode=keys[action_name]
		InputMap.action_add_event(action_name,event)

func _build_world(seed_value: int) -> void:
	_built_seed=seed_value
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
	archipelago.configure(seed_value)
	archipelago.build()
	ocean=OceanScript.new()
	scenery.add_child(ocean)
	ocean.set_shore_data(archipelago.shore_texture,Vector2(-512,-512),Vector2(1024,1024))
	creature_manager=CreatureScript.new()
	scenery.add_child(creature_manager)
	creature_manager.configure(archipelago,ocean)
	interactables.clear()
	for poi in archipelago.pois:
		var at: Vector3=poi.position
		match str(poi.kind):
			"shop":
				_place_model("shop",at,scenery,PI,true)
				_place_model("shopkeeper",at+Vector3(1,0,5.0),scenery,PI)
				interactables.append({"kind":"shop","position":at+Vector3(1,0,5),"name":"Mara's Chandlery"})
			"lighthouse": _place_model("lighthouse",at,scenery,0,true)
			"dock":
				_place_model("dock",at-Vector3(0,0.35,0),scenery,-0.6,true)
				_place_model("barrel",at+Vector3(1.6,0,0),scenery)
			"spawn": _place_model("hearthstone",at,scenery)
			"tutorial_ruin", "dungeon":
				_place_model("ruin_arch",at,scenery,0,true)
				_place_model("ruin_arch",at+Vector3(-4,0,-5),scenery,PI/2,true)
				if poi.kind == "dungeon":
					_place_model("loot_chest",at+Vector3(0,0.25,-3),scenery)
					interactables.append({"kind":"dungeon","position":at+Vector3(0,0,-3),"id":poi.id,"name":poi.name})
			"apprentice_cache":
				_place_model("loot_chest",at,scenery)
				interactables.append({"kind":"cache","position":at,"name":"Apprentice's Wind Cache"})
	# Decorative village follows the approved harbour material and architecture kit.
	for offset in [Vector2(-18,5),Vector2(13,-10),Vector2(-10,-15)]:
		var p:=Vector3(-37+offset.x,0,-48+offset.y)
		p.y=archipelago.sample_ground_height(p.x,p.z)
		var house:=_place_model("shop",p,scenery,0.35,true)
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

func _place_model(asset: String, at: Vector3, parent: Node3D, angle:=0.0, collision:=false) -> Node3D:
	var path:="res://assets/models/%s.glb"%asset
	if not ResourceLoader.exists(path): return null
	var model: Node3D=load(path).instantiate()
	parent.add_child(model)
	model.position=at
	model.rotation.y=angle
	if collision:
		_add_mesh_collisions(model)
	return model

func _add_mesh_collisions(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		node.create_trimesh_collision()
	for child in node.get_children():
		if not child is StaticBody3D: _add_mesh_collisions(child)

func _host(world_name:String,seed_value:int,wizard_name:String) -> void:
	Session.display_name=wizard_name
	if Session.start_host(world_name,seed_value)!=OK: return
	if Session.world.seed_value!=_built_seed:
		_build_world(Session.world.seed_value)
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
	if data.get("seed",_built_seed)!=_built_seed:
		_build_world(int(data.seed))
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
	simulation_time+=delta
	ocean.set_simulation_time(simulation_time)
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
		if creature_manager.simulate(delta,Session.world,wizards): Session.publish_state()
		for ship_id in boats:
			var boat:Node3D=boats[ship_id]
			boat.steering=0;boat.throttle=0
			if not boat.pilot_id.is_empty() and wizards.has(boat.pilot_id) and wizards[boat.pilot_id].helm_id==ship_id and Session.world.can_pilot(boat.pilot_id,ship_id):
				var pilot:Node=wizards[boat.pilot_id]
				boat.steering=-float(pilot.input_data.get("move_x",0))
				boat.throttle=-float(pilot.input_data.get("move_y",0))
			else: boat.pilot_id=""
			boat.simulate(delta)
			Session.world.update_ship_position(ship_id,boat.global_position,archipelago.is_safe_zone(boat.global_position))
			Session.world.ships[ship_id]["heading"]=boat.heading
		for player_id in wizards:
			var wizard:Node3D=wizards[player_id]
			if not wizard.helm_id.is_empty() and (not boats.has(wizard.helm_id) or boats[wizard.helm_id].pilot_id!=player_id or not Session.world.can_pilot(player_id,wizard.helm_id)):
				_release_helm(player_id)
			for boat in boats.values():
				var previous_local:Vector3=boat.last_transform.affine_inverse()*wizard.global_position
				if wizard.helm_id.is_empty() and absf(previous_local.x)<3.1 and absf(previous_local.z)<5.5 and previous_local.y>0.6 and previous_local.y<3.5:
					wizard.aboard_id=boat.ship_id
					wizard.global_position=boat.global_transform*(boat.last_transform.affine_inverse()*wizard.global_position)
			wizard.simulate(delta,boats)
			Session.world.update_player_position(player_id,wizard.global_position,archipelago.is_safe_zone(wizard.global_position))
		_update_projectiles(delta)
		survival_timer+=delta
		if survival_timer>1:
			survival_timer=0
			for player_id in wizards:
				var wizard:Node=wizards[player_id]
				if wizard.alive and (wizard.breath<=0 or wizard.global_position.y < -80):
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

func _process(delta:float) -> void:
	if in_game and local_wizard:
		selected_target=_nearest_interaction(local_wizard.global_position)
		var hint:=""
		if not local_wizard.helm_id.is_empty(): hint="W / S  Sail   A / D  Steer   E  Release helm"
		elif not selected_target.is_empty(): hint="E  ·  "+str(selected_target.name)
		var area:="The Great Sea"
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
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and not modal_open and local_wizard:
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

func _nearest_interaction(pos:Vector3) -> Dictionary:
	var best:Dictionary={}
	var distance_value:=6.0
	for item in interactables:
		var d:=pos.distance_to(item.position)
		if d<distance_value: best=item;distance_value=d
	for id in boats:
		var p:Vector3=boats[id].to_global(Vector3(0,1.1,3.5))
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
	match str(selected_target.kind):
		"shop": hud.open_shop()
		"cache": Session.request_action("claim_cache",{})
		"dungeon": Session.request_action("interact",{"kind":"dungeon","id":selected_target.id})
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
			elif boats.has(id) and wizard.global_position.distance_to(boats[id].to_global(Vector3(0,1.1,3.5)))<6:
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
						var target:Dictionary=archipelago.island_records[3] if p.inventory.get("reef_compass",0)>0 else archipelago.island_records[7]
						var bearing:=fposmod(rad_to_deg(atan2(target.center.x-wizard.position.x,-(target.center.z-wizard.position.z))),360)
						result={"ok":true,"message":"%s · bearing %03d° · %dm"%[target.name,bearing,wizard.position.distance_to(target.center)]}
				"dungeon":
					for poi in interactables:
						if poi.kind=="dungeon" and poi.id==data.get("id","") and wizard.position.distance_to(poi.position)<6:
							if not p.claimed_caches.has(poi.id):
								p.claimed_caches.append(poi.id)
								var glyphs:=["power","range","heal","split"]
								var glyph:String=glyphs[absi(str(poi.id).hash())%glyphs.size()]
								Session.world.learn_glyph(player_id,glyph,"dungeon")
								p.inventory.ancient_coin=int(p.inventory.get("ancient_coin",0))+3
								result={"ok":true,"message":"Discovered glyph: "+glyph.capitalize()+". Three ancient coins recovered."}
							else: result={"ok":false,"error":"You have already studied this reliquary in this world."}
	Session.world.update_player_position(player_id,wizard.global_position,archipelago.is_safe_zone(wizard.global_position))
	Session.publish_state()
	_broadcast_simulation()
	_notify_player(player_id,str(result.get("message","Done.")) if result.ok else str(result.get("error","Unavailable.")))

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
	var orb:=MeshInstance3D.new()
	var mesh:=SphereMesh.new()
	mesh.radius=0.14;mesh.height=0.28
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("91f9e4") if recipe.has("wind") else Color("ffb86a")
	material.emission_enabled=true;material.emission=material.albedo_color;material.emission_energy_multiplier=2
	mesh.material=material;orb.mesh=mesh
	add_child(orb);orb.position=origin+direction*0.65
	var rings: Array[Node3D]=[]
	for i in 3:
		var ring:=MeshInstance3D.new()
		var torus:=TorusMesh.new()
		torus.inner_radius=0.22+float(i)*0.045;torus.outer_radius=0.245+float(i)*0.045
		torus.rings=24;torus.ring_segments=6;torus.material=material
		ring.mesh=torus;orb.add_child(ring);ring.rotation=Vector3(PI/2,0,0);rings.append(ring)
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

func _capture(path:String) -> void:
	await RenderingServer.frame_post_draw
	var image_value:=get_viewport().get_texture().get_image()
	image_value.save_png(path)
	var sum:=0.0
	for dt in capture_frames: sum+=dt
	var fps:=float(capture_frames.size())/maxf(sum,0.0001)
	print("CAPTURE ",path," FPS ",fps," frames ",capture_frames.size())
	get_tree().quit()

