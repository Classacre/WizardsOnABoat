extends SceneTree
## Headless main-scene expedition into a streamed generator-v2 island beyond 3 km.
## A disposable identity and an ignored res:// save keep user worlds untouched.
## Add --capture-procedural in a rendered run for menu, far shore, dungeon,
## and exit PNGs under res://output/procedural/.

const WorldModel = preload("res://scripts/data/world_state.gd")
const DungeonLayout = preload("res://scripts/world/dungeon_layout.gd")
const SEED := 948321
const GENERATOR_VERSION := 2
const OUTPUT := "res://output/performance/"
const CAPTURE_OUTPUT := "res://output/procedural/"

var game: Node3D
var session: Node
var failures: Array[String] = []
var checks := 0
var started_ms := Time.get_ticks_msec()
var save_path := ""
var capture_enabled := false

func _initialize() -> void:
	Engine.max_fps = 120
	capture_enabled = OS.get_cmdline_user_args().has("--capture-procedural") and DisplayServer.get_name() != "headless"
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_ms > 240000:
		_check(false,"Procedural expedition timed out after four minutes")
		_finish()
	return false

func _check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures.append(message)

func _run() -> void:
	session = root.get_node("Session")
	session.save_enabled = false
	session._identity_token = Crypto.new().generate_random_bytes(32).hex_encode()
	session.local_player_id = session._identity_token.sha256_text().substr(0,24)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await _capture("seed-main-menu")
	var world_name := "procedural-expedition-" + str(Time.get_ticks_usec())
	game._host(world_name,SEED,"Expedition Wizard",GENERATOR_VERSION)
	if not session.hosting or game.local_wizard == null:
		_check(false,"Generator-v2 main scene hosts with a local wizard")
		_finish()
		return
	_check(session.world.generator_version == GENERATOR_VERSION and game.archipelago.generator_version == GENERATOR_VERSION,"Main and authoritative world use generator v2")
	_check(session.world.seed_value == SEED and game.archipelago.world_seed == SEED,"Entered seed reaches the world generator")
	var manifest: Dictionary = {}
	for sector_x in range(7,18):
		for sector_z in range(-3,4):
			var candidate: Dictionary = game.archipelago.sector_manifest(sector_x,sector_z)
			if not candidate.is_empty() and not candidate.sky and candidate.center.length() > 3000.0:
				manifest = candidate
				break
		if not manifest.is_empty(): break
	_check(not manifest.is_empty(),"Seed has a far ground island beyond 3 km")
	if manifest.is_empty():
		_finish()
		return
	game._ensure_surface_for_position(manifest.center)
	var island: Dictionary = {}
	for record in game.archipelago.island_records:
		if record.id == manifest.id: island = record
	_check(not island.is_empty() and island.get("procedural",false),"Far island streams physical terrain into main scene")
	if island.is_empty():
		_finish()
		return
	var landing: Dictionary = {}
	var dungeon_poi: Dictionary = {}
	for poi in island.pois:
		if poi.kind == "landing": landing = poi
		if poi.kind == "dungeon": dungeon_poi = poi
	_check(not landing.is_empty() and not dungeon_poi.is_empty(),"Streamed island provides a landing and dungeon")
	var interactable_found := false
	for entry in game.interactables:
		if entry.kind == "dungeon" and entry.id == dungeon_poi.get("id",""):
			interactable_found = true
	_check(interactable_found,"Main scene registers streamed dungeon interaction")
	if landing.is_empty() or dungeon_poi.is_empty() or not interactable_found:
		_finish()
		return
	var wizard: CharacterBody3D = game.local_wizard
	var player_id: String = session.local_player_id
	wizard.global_position = landing.position + Vector3.UP*1.15
	wizard.velocity = Vector3.ZERO
	session.world.update_player_position(player_id,wizard.global_position,false)
	await _capture("far-shore",manifest.center + Vector3(95,48,95),manifest.center + Vector3(0,10,0))
	await _settle_on_floor(wizard)
	_print_floor_diagnostic("initial far-shore settle",wizard)
	_check(wizard.is_on_floor() and not wizard.head_underwater,"Wizard stands on the streamed island's physical dry floor")
	var jump_height := wizard.global_position.y
	wizard.input_data = {"jump":true}
	await physics_frame
	wizard.simulate(1.0/30.0,game.boats)
	_check(wizard.velocity.y>0.0 and wizard.global_position.y>jump_height+0.1,"Wizard can jump from streamed terrain")
	wizard.input_data = {}
	_check(await _settle_on_floor(wizard),"Jump lands back on the streamed physical floor")
	var exterior_path := PackedVector3Array()
	for path in island.paths:
		if path.size() > 1 and path[path.size()-1].distance_to(dungeon_poi.position) < 2.0:
			exterior_path = path
			break
	_check(not exterior_path.is_empty(),"Streamed landing connects to dungeon by a graded path")
	if exterior_path.is_empty():
		_finish()
		return
	var walked_outside := await _walk(exterior_path,dungeon_poi.position)
	_check(walked_outside,"Wizard physically walks the far island path to its dungeon")
	if not walked_outside:
		_finish()
		return
	var dungeon_id := str(dungeon_poi.id)
	var dungeon: Dictionary = game.archipelago.get_dungeon(dungeon_id)
	_check(not dungeon.is_empty(),"Far island has a seeded physical dungeon")
	if dungeon.is_empty():
		_finish()
		return
	var coins_before := int(session.world.players[player_id].inventory.get("ancient_coin",0))
	game._action(player_id,"interact",{"kind":"dungeon","id":dungeon_id})
	_check(game.archipelago.dungeon_at(wizard.global_position) == dungeon_id,"Host interaction enters the far dungeon")
	if game.archipelago.dungeon_at(wizard.global_position) != dungeon_id:
		_finish()
		return
	await _settle_on_floor(wizard)
	_check(wizard.is_on_floor() and not wizard.head_underwater,"Dungeon arrival stands on a dry physical floor")
	var to_reward: PackedVector3Array = game.archipelago.dungeon_route(dungeon_id,wizard.global_position,dungeon.reward_position)
	var reached_reward := await _walk(to_reward,dungeon.reward_position)
	_check(reached_reward,"Wizard physically walks dungeon corridors to the reliquary")
	if not reached_reward:
		_finish()
		return
	await _capture("dungeon-reward",wizard.global_position + Vector3(2.0,2.0,3.5),dungeon.reward_position + Vector3.UP)
	game._action(player_id,"interact",{"kind":"dungeon_reward","id":dungeon_id})
	var player: Dictionary = session.world.players[player_id]
	_check(player.claimed_caches.has(dungeon_id) and int(player.inventory.get("ancient_coin",0)) == coins_before+3,"Far reliquary grants a persistent reward")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	save_path = OUTPUT.path_join(world_name.validate_filename() + ".json")
	var inside_save_error: Error = session.world.save_to(save_path)
	var restored_inside = WorldModel.new(world_name,SEED,GENERATOR_VERSION)
	var inside_result: Dictionary = restored_inside.load_from(save_path,SEED) if inside_save_error == OK else {"ok":false}
	_check(inside_save_error == OK and inside_result.ok,"Far dungeon saves and reloads while the wizard is inside")
	if inside_result.ok:
		var saved_position: Vector3 = game._vec(restored_inside.players[player_id].position)
		_check(restored_inside.generator_version == GENERATOR_VERSION and game.archipelago.dungeon_at(saved_position) == dungeon_id,"Inside reload retains version, dungeon position, and identity")
		_check(restored_inside.players[player_id].claimed_caches.has(dungeon_id),"Inside reload retains the claimed reliquary")
	var to_exit: PackedVector3Array = game.archipelago.dungeon_route(dungeon_id,wizard.global_position,dungeon.exit_position)
	var reached_exit := await _walk(to_exit,dungeon.exit_position)
	_check(reached_exit,"Wizard physically walks back to the dungeon exit")
	if not reached_exit:
		_finish()
		return
	game._action(player_id,"interact",{"kind":"dungeon_exit","id":dungeon_id})
	_check(wizard.global_position.distance_to(dungeon.return_position) < 2.0,"Dungeon exit returns wizard to far island")
	await _capture("far-exit",dungeon.return_position + Vector3(12,8,13),dungeon.return_position + Vector3.UP)
	var replay: Dictionary = game.archipelago.sector_manifest(manifest.sector.x,manifest.sector.y)
	_check(not replay.is_empty() and replay.id == manifest.id and replay.center.is_equal_approx(manifest.center),"Far island identity is deterministic for seed and sector")
	var save_error: Error = session.world.save_to(save_path)
	var restored = WorldModel.new(world_name,SEED,GENERATOR_VERSION)
	var load_result: Dictionary = restored.load_from(save_path,SEED) if save_error == OK else {"ok":false}
	_check(save_error == OK and load_result.ok,"Far expedition saves and reloads from an isolated file")
	if load_result.ok:
		_check(restored.seed_value == SEED and restored.generator_version == GENERATOR_VERSION and restored.world_id == world_name,"Reload retains seed, generator version, and world identity")
		_check(restored.players[player_id].claimed_caches.has(dungeon_id) and int(restored.players[player_id].inventory.get("ancient_coin",0)) == coins_before+3,"Reload retains far-dungeon progression")
	_finish()

func _settle_on_floor(wizard: CharacterBody3D) -> bool:
	for frame in 60:
		await physics_frame
		wizard.simulate(1.0/30.0,game.boats)
		if wizard.is_on_floor(): return true
	return false

func _walk(route: PackedVector3Array, destination: Vector3) -> bool:
	if route.is_empty():
		print("EXPEDITION_WALK_DIAGNOSTIC empty route destination=",destination)
		return false
	var wizard: CharacterBody3D = game.local_wizard
	var steps := 0
	for waypoint in route:
		while Vector2(wizard.position.x-waypoint.x,wizard.position.z-waypoint.z).length() > 0.45:
			var direction: Vector3 = waypoint-wizard.position
			wizard.yaw = atan2(-direction.x,-direction.z)
			wizard.input_data = {"move_y":-1.0,"sprint":true,"yaw":wizard.yaw,"pitch":0.0}
			await physics_frame
			wizard.simulate(0.05,game.boats)
			steps += 1
			if steps > 3000:
				print("EXPEDITION_WALK_DIAGNOSTIC timeout steps=",steps," waypoint=",waypoint," destination=",destination," remaining=",Vector2(wizard.position.x-waypoint.x,wizard.position.z-waypoint.z).length())
				_print_floor_diagnostic("walk timeout",wizard)
				var toward: Vector3 = (waypoint-wizard.global_position).normalized()
				var obstacle_ray := PhysicsRayQueryParameters3D.create(wizard.global_position+Vector3.UP,wizard.global_position+Vector3.UP+toward*2.5,1)
				obstacle_ray.exclude = [wizard.get_rid()]
				var obstacle: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(obstacle_ray)
				print("EXPEDITION_WALK_DIAGNOSTIC slide_collisions=",wizard.get_slide_collision_count()," obstacle=",obstacle.get("collider",null)," obstacle_position=",obstacle.get("position",Vector3.INF)," obstacle_normal=",obstacle.get("normal",Vector3.ZERO))
				for collision_index in wizard.get_slide_collision_count():
					var collision: KinematicCollision3D = wizard.get_slide_collision(collision_index)
					print("EXPEDITION_WALK_DIAGNOSTIC slide[",collision_index,"] collider=",collision.get_collider()," normal=",collision.get_normal()," position=",collision.get_position())
				var dungeon_id: String = game.archipelago.dungeon_at(wizard.global_position)
				if not dungeon_id.is_empty():
					var layout: Dictionary = game.archipelago.get_dungeon(dungeon_id)
					print("EXPEDITION_WALK_DIAGNOSTIC dungeon=",dungeon_id," cell=",DungeonLayout.world_to_cell(layout,wizard.global_position)," waypoint_cell=",DungeonLayout.world_to_cell(layout,waypoint)," destination_cell=",DungeonLayout.world_to_cell(layout,destination)," open_current=",layout.open_cells.has(DungeonLayout.world_to_cell(layout,wizard.global_position)))
				wizard.input_data = {}
				return false
	wizard.input_data = {}
	wizard.velocity = Vector3.ZERO
	return wizard.position.distance_to(destination) < 2.0

func _print_floor_diagnostic(label: String, wizard: CharacterBody3D) -> void:
	var at: Vector3 = wizard.global_position
	var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*3.0,at+Vector3.DOWN*8.0,1)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray)
	print("EXPEDITION_FLOOR_DIAGNOSTIC ",label," position=",at," velocity=",wizard.velocity," on_floor=",wizard.is_on_floor()," floor_normal=",wizard.get_floor_normal()," surface_y=",game.archipelago.sample_surface_at(at)," ray_hit=",hit.get("position",Vector3.INF)," ray_normal=",hit.get("normal",Vector3.ZERO)," collider=",hit.get("collider",null))

func _capture(label: String, camera_position: Vector3 = Vector3.INF, target: Vector3 = Vector3.ZERO) -> void:
	if not capture_enabled:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_OUTPUT))
	var overview := camera_position.is_finite()
	var previous_camera: Camera3D = game.get_viewport().get_camera_3d()
	var previous_hud_visible: bool = game.hud.visible
	var staff: Node3D = game.local_wizard.staff if game.local_wizard else null
	var previous_staff_visible: bool = staff.visible if staff else false
	if overview:
		game.hud.hide()
		if staff: staff.hide()
		var camera: Camera3D = game.preview_camera
		camera.global_position = camera_position
		camera.look_at(target)
		camera.current = true
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(CAPTURE_OUTPUT.path_join(label + ".png"))
	if overview:
		game.hud.visible = previous_hud_visible
		if staff: staff.visible = previous_staff_visible
		if is_instance_valid(previous_camera): previous_camera.current = true
	_check(error == OK,"Rendered capture saved: " + label)

func _finish() -> void:
	print("PROCEDURAL_EXPEDITION checks=%d failures=%d" % [checks,failures.size()])
	if session != null: session.stop_session()
	if not save_path.is_empty() and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	quit(0 if failures.is_empty() else 1)
