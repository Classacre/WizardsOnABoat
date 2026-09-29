extends SceneTree
## Real scene, save-free checks for developer controls and physical dungeon traversal.
## Run headless for assertions, or rendered to write review screenshots.

const OUTPUT := "res://output/world-tools"
var game: Node3D
var session: Node
var failures: Array[String] = []
var assertions := 0
var started := Time.get_ticks_msec()

func _initialize() -> void:
	Engine.max_fps = 120
	Engine.time_scale = 3.0
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 240000:
		push_error("World tools integration exceeded four minutes")
		quit(2)
	return false

func check(condition: bool, message: String) -> void:
	assertions += 1
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures.append(message)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var ignore := FileAccess.open(OUTPUT + "/.gdignore", FileAccess.WRITE)
	ignore.close()
	session = root.get_node("Session")
	session.save_enabled = false
	session._identity_token = Crypto.new().generate_random_bytes(32).hex_encode()
	session.local_player_id = session._identity_token.sha256_text().substr(0,24)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	await _capture("main-menu")
	game._host("World tools test",7319,"Test Wayfarer",1)
	if not session.hosting or game.local_wizard == null:
		check(false,"Main scene hosts successfully")
		_finish()
		return
	var wizard: CharacterBody3D = game.local_wizard
	var player_id: String = session.local_player_id
	for item in game.interactables:
		if item.kind == "cache":
			wizard.position = item.position
			game._action(player_id,"claim_cache",{})
	game.hud.notice.text = ""
	game.hud.update_player(session.world.snapshot(),player_id,wizard,"Hearthharbour","")
	game.preview_camera.current = true
	for panel in ["book","inventory","shop","crews","pause"]:
		game.hud.call("open_"+panel)
		await _capture("menu-"+panel)
		var bounds: Rect2 = game.hud.modal.get_global_rect()
		check(bounds.get_center().distance_to(root.get_visible_rect().get_center()) < 1.0,panel+" menu is centered")
		check(root.get_visible_rect().encloses(bounds),panel+" menu is fully on screen")
	var original_size := root.size
	root.size = Vector2i(640,360)
	game.hud.open_book()
	await _capture("menu-book-small-window")
	check(root.get_visible_rect().encloses(game.hud.modal.get_global_rect()),"Open menu fits an actual 640x360 window")
	root.size = original_size
	game.hud.close_panel()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F3
	key.keycode = KEY_F3
	key.pressed = true
	game._input(key)
	check(game.hud.current_panel == "dev" and game.modal_open,"F3 opens developer menu")
	await _capture("menu-developer")
	wizard.camera.current = true
	game._dev_action("fly_toggle",{"enabled":true})
	check(wizard.dev_fly_enabled and wizard.collision_mask == 0,"Developer flight disables collision")
	game.hud.close_panel()
	wizard.position = Vector3(80,25,80)
	var before := wizard.position
	wizard.input_data = {"move_y":-1.0,"ascend":true,"yaw":0.0,"pitch":0.0}
	for index in 15:
		await physics_frame
		wizard.simulate(1.0/30.0,game.boats)
	check(wizard.position.y > before.y+2.0 and wizard.position.z < before.z-2.0,"Flight crosses map and ascends")
	game._dev_action("fly_toggle",{"enabled":false})
	check(not wizard.dev_fly_enabled and wizard.collision_mask == 1,"Disabling flight restores collision")
	wizard.input_data = {}
	var destination_count: int = game._dev_destinations().size()
	check(destination_count > game.archipelago.island_records.size(),"Developer list includes entities and POIs")
	var old_position := wizard.position
	session.hosting = false
	game._dev_action("fly_toggle",{"enabled":true})
	game._dev_action("teleport",{"id":"island/rootwatch"})
	check(not wizard.dev_fly_enabled and wizard.position == old_position,"Client cannot use host developer actions")
	session.hosting = true
	game._dev_action("teleport",{"id":"poi/cinder_crown/dungeon"})
	check(wizard.position.distance_to(game.archipelago.get_dungeon("cinder_crown/dungeon").entrance_position)<8.0,"Developer teleport reaches selected POI")
	var mobs_before: int = session.world.mobs.size()
	game._dev_action("spawn",{"id":"mob/kettleback"})
	check(session.world.mobs.size() == mobs_before+1,"Developer menu spawns a persistent creature")
	var loot_before: int = session.world.loot.size()
	game._dev_last_spawn_msec = 0
	game._dev_action("spawn",{"id":"chest/salvage"})
	check(session.world.loot.size() == loot_before+1 and game.chests.size()>0,"Developer menu spawns a usable loot chest")

	check(game.archipelago.dungeons.size() >= 3,"Large islands have dungeon interiors")
	for dungeon_id in game.archipelago.dungeons:
		var dungeon: Dictionary = game.archipelago.get_dungeon(dungeon_id)
		wizard.position = dungeon.entrance_position
		wizard.velocity = Vector3.ZERO
		var player: Dictionary = session.world.players[player_id]
		var coins_before := int(player.inventory.get("ancient_coin",0))
		game._action(player_id,"interact",{"kind":"dungeon_reward","id":dungeon_id})
		check(int(player.inventory.get("ancient_coin",0)) == coins_before,"Reward rejected from outside "+dungeon_id)
		game._action(player_id,"interact",{"kind":"dungeon","id":dungeon_id})
		check(game.archipelago.dungeon_at(wizard.position) == dungeon_id,"Entrance enters "+dungeon_id)
		for frame in 12:
			await physics_frame
			wizard.simulate(1.0/30.0,game.boats)
		check(wizard.is_on_floor() and not wizard.head_underwater,"Dungeon arrival has a real dry floor "+dungeon_id)
		var route: PackedVector3Array = game.archipelago.dungeon_route(dungeon_id,wizard.position,dungeon.reward_position)
		check(not route.is_empty(),"Reward has a connected route "+dungeon_id)
		var walked := await _walk(route,dungeon.reward_position)
		check(walked,"Wizard physically walks corridors to reward "+dungeon_id)
		if walked:
			game._action(player_id,"interact",{"kind":"dungeon_reward","id":dungeon_id})
			check(player.claimed_caches.has(dungeon_id) and int(player.inventory.get("ancient_coin",0)) == coins_before+3,"Reward grants saved knowledge and coins "+dungeon_id)
			game._action(player_id,"interact",{"kind":"dungeon_reward","id":dungeon_id})
			check(int(player.inventory.get("ancient_coin",0)) == coins_before+3,"Dungeon reward cannot be farmed "+dungeon_id)
		game.hud.notice.text = ""
		game.hud.update_player(session.world.snapshot(),player_id,wizard,dungeon.name,"E · Study the dungeon cache")
		var view_point: Vector3 = dungeon.reward_position + Vector3(3,0,3)
		if absf(game.archipelago.dungeon_surface_at(view_point)-float(dungeon.floor_y)) < 0.5:
			wizard.position = view_point
			var view_direction: Vector3 = dungeon.reward_position - view_point
			wizard.yaw = atan2(-view_direction.x,-view_direction.z)
			wizard.pitch = -0.18
			wizard._update_look()
		await _capture("dungeon-"+str(dungeon.island_id))
		var back: PackedVector3Array = game.archipelago.dungeon_route(dungeon_id,wizard.position,dungeon.exit_position)
		check(await _walk(back,dungeon.exit_position),"Wizard walks back to exit "+dungeon_id)
		game._action(player_id,"interact",{"kind":"dungeon_exit","id":dungeon_id})
		check(wizard.position.distance_to(dungeon.return_position)<2.0,"Exit returns to original island "+dungeon_id)
		var guard_ids: Array[String] = []
		for mob_id in session.world.mobs:
			if str(session.world.mobs[mob_id].get("dungeon_id","")) == dungeon_id:
				guard_ids.append(mob_id)
		check(guard_ids.size() > 0 and guard_ids.size() <= 2,"Dungeon has a bounded persistent encounter "+dungeon_id)
		if not guard_ids.is_empty():
			session.world.kill_mob(guard_ids[0],player_id)
			game.creature_manager.activate_dungeon(session.world,dungeon_id)
			check(not session.world.mobs[guard_ids[0]].alive,"Revisiting does not resurrect a defeated guardian "+dungeon_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp/world-tools"))
	var saved: Error = session.world.save_to("res://tmp/world-tools/world.json")
	var restored = load("res://scripts/data/world_state.gd").new("World tools test",7319,1)
	var restore_result: Dictionary = restored.load_from("res://tmp/world-tools/world.json")
	check(saved == OK and restore_result.get("ok",false),"World containing dungeon progress saves and reloads")
	if restore_result.get("ok",false):
		check(restored.players[player_id].claimed_caches == session.world.players[player_id].claimed_caches,"Dungeon reward claims survive disk reload")
		var guardians_match: bool = restored.mobs.size() == session.world.mobs.size()
		for mob_id in session.world.mobs:
			var original: Dictionary = session.world.mobs[mob_id]
			if not original.has("dungeon_id"): continue
			var loaded: Dictionary = restored.mobs.get(mob_id,{})
			for field in ["id","species","dungeon_id","island_id","alive","loot_id","rarity"]:
				guardians_match = guardians_match and loaded.get(field) == original.get(field)
			var saved_items: Dictionary = loaded.get("inventory",{})
			guardians_match = guardians_match and saved_items.size() == original.inventory.size()
			for item in original.inventory:
				guardians_match = guardians_match and int(saved_items.get(item,-1)) == int(original.inventory[item])
			# JSON numbers lose integer/float tags; Vector3 positions retain float precision.
			guardians_match = guardians_match and is_equal_approx(float(loaded.get("health",-1.0)),float(original.health))
			guardians_match = guardians_match and game._vec(loaded.get("position",[0,0,0])).is_equal_approx(game._vec(original.position))
		check(guardians_match,"Guardian identities, inventories and deaths survive disk reload")
	_finish()

func _walk(route: PackedVector3Array, destination: Vector3) -> bool:
	if route.is_empty(): return false
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
			if steps > 2500:
				print("WALK_STUCK at=",wizard.position," target=",waypoint)
				wizard.input_data = {}
				return false
	wizard.input_data = {}
	wizard.velocity = Vector3.ZERO
	return wizard.position.distance_to(destination)<2.0

func _capture(label: String) -> void:
	for frame in 3:
		await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+"/"+label+".png")

func _finish() -> void:
	print("WORLD_TOOLS_INTEGRATION assertions=",assertions," failures=",failures.size())
	var report := FileAccess.open(OUTPUT+"/integration.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"assertions":assertions,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started},"\t"))
	report.close()
	session.stop_session()
	quit(0 if failures.is_empty() else 1)
