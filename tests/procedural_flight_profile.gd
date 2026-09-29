extends SceneTree
## Rendered procedural streaming flight. Run with Godot --path . --script res://tests/procedural_flight_profile.gd.

const OUTPUT := "res://output/procedural/"
const SEED := 948321
const WARMUP_SECONDS := 5.0
const FLIGHT_SECONDS := 35.0
const SPEED := 120.0
const MAX_ACTORS := 96
const MAX_ACTIVE_ISLANDS := 24

var game
var session
var world
var wizard
var _seen_ids: Dictionary = {}
var _seen_far_ids: Dictionary = {}
var _samples: Array[Dictionary] = []
var _failures: Array[String] = []
var _max_active_islands := 0
var _max_actors := 0
var _max_nodes := 0
var _max_nav_graphs := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	session = root.get_node("Session")
	session.save_enabled = false
	session.identity_profile = "procedural_flight_profile"
	# Give Session a valid in-memory identity before start_host can inspect its disk profile.
	session._identity_token = Crypto.new().generate_random_bytes(32).hex_encode()
	session.local_player_id = session._identity_token.sha256_text().substr(0,24)
	var report := {
		"benchmark": "rendered_procedural_flight_v2",
		"created_at": Time.get_datetime_string_from_system(true),
		"seed": SEED,
		"generator_version": 2,
		"physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"warmup_target_s": WARMUP_SECONDS,
		"flight_target_s": FLIGHT_SECONDS,
		"fly_speed_mps": SPEED,
		"stream_profile_enabled": OS.get_environment("SPELLWAKE_PROFILE_STREAM") == "1",
		"save_enabled": session.save_enabled,
		"capture_pause_excluded_from_frame_gaps": true,
		"samples": _samples,
	}
	var started_us := Time.get_ticks_usec()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	report["scene_build_ms"] = float(Time.get_ticks_usec()-started_us)/1000.0
	started_us = Time.get_ticks_usec()
	game._host("procedural-flight-%d" % Time.get_ticks_usec(),SEED,"Flight Profiler",2)
	report["host_enter_ms"] = float(Time.get_ticks_usec()-started_us)/1000.0
	if not session.hosting or not game.in_game or game.local_wizard == null:
		_failures.append("Isolated v2 host or local wizard did not start")
		_finish(report)
		return
	world = game.archipelago
	wizard = game.local_wizard
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game._dev_action("fly_toggle",{"enabled":true})
	game._dev_action("fly_speed",{"speed":SPEED})
	if not wizard.dev_fly_enabled or not is_equal_approx(wizard.dev_fly_speed,SPEED):
		_failures.append("Host developer fly controls did not enable the requested speed")
		_finish(report)
		return
	var start_position: Vector3 = world.get_spawn_position()
	start_position.y = 45.0
	wizard.global_position = start_position
	wizard.yaw = -PI/2.0
	wizard.pitch = 0.0
	wizard.input_data["yaw"] = wizard.yaw
	wizard.input_data["pitch"] = wizard.pitch
	wizard.camera.current = true
	session.world.update_player_position(session.local_player_id,start_position,true)
	report["start_position"] = _vec(start_position)
	report["initial_boats"] = game.boats.size()
	report["initial_nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("PROCEDURAL_FLIGHT_START seed=",SEED," start=",start_position)
	await _wait_wall_seconds(WARMUP_SECONDS)
	report["warmup_screenshot_error"] = await _screenshot("flight_start.png")
	var gaps: Array[float] = []
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var largest_gaps: Array[Dictionary] = []
	var flight_start_us := Time.get_ticks_usec()
	var previous_us := 0
	var next_sample_s := 0.0
	var captured_far := false
	# Host simulation copies the previous input look back into Wizard each tick.
	# Seed both values again after warmup and ignore real mouse-motion aim events.
	game.set_process_unhandled_input(false)
	wizard.yaw = -PI/2.0
	wizard.pitch = 0.0
	wizard.input_data["yaw"] = wizard.yaw
	wizard.input_data["pitch"] = wizard.pitch
	Input.action_press("forward")
	while float(Time.get_ticks_usec()-flight_start_us)/1000000.0 < FLIGHT_SECONDS:
		await process_frame
		var now_us := Time.get_ticks_usec()
		var elapsed_s := float(now_us-flight_start_us)/1000000.0
		if previous_us != 0:
			var gap_ms := float(now_us-previous_us)/1000.0
			gaps.append(gap_ms)
			_insert_largest(largest_gaps,{"t_s":snappedf(elapsed_s,0.001),"gap_ms":gap_ms},20)
		previous_us = now_us
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		if elapsed_s >= next_sample_s:
			_sample(elapsed_s,start_position)
			next_sample_s += 1.0
			if not captured_far and wizard.global_position.x-start_position.x > 3000.0:
				captured_far = true
				report["far_screenshot_error"] = await _screenshot("flight_far.png")
				# PNG encoding is benchmark output work, not a gameplay frame.
				previous_us = 0
	Input.action_release("forward")
	await process_frame
	_sample(float(Time.get_ticks_usec()-flight_start_us)/1000000.0,start_position)
	report["end_screenshot_error"] = await _screenshot("flight_end.png")
	report["flight_actual_s"] = float(Time.get_ticks_usec()-flight_start_us)/1000000.0
	report["end_position"] = _vec(wizard.global_position)
	report["east_distance_m"] = wizard.global_position.x-start_position.x
	report["horizontal_distance_m"] = Vector2(wizard.global_position.x-start_position.x,wizard.global_position.z-start_position.z).length()
	report["frame_gaps_ms"] = _stats(gaps)
	report["process_monitor_ms"] = _stats(process_ms)
	report["physics_monitor_ms"] = _stats(physics_ms)
	report["largest_gaps"] = largest_gaps
	report["unique_procedural_ids_seen"] = _seen_ids.size()
	report["unique_far_procedural_ids_seen"] = _seen_far_ids.size()
	report["max_active_procedural_meshes"] = _max_active_islands
	report["max_creature_actors"] = _max_actors
	report["max_nodes"] = _max_nodes
	report["max_nav_graphs"] = _max_nav_graphs
	report["stream_phase_cost_ms"] = null # No phase timer is exposed by Archipelago.
	if game.boats.is_empty(): _failures.append("Harbour boat disappeared during flight")
	if float(report.east_distance_m) <= 3000.0: _failures.append("Flight did not reach >3 km east")
	if _seen_far_ids.size() < 2: _failures.append("Fewer than two procedural islands loaded beyond 3 km")
	var far_observations := 0
	for sample in _samples:
		if float(sample.east_distance_m)>3000.0 and int(sample.active_procedural_islands)>0:
			far_observations += 1
	if far_observations < 3: _failures.append("Procedural islands were not observed repeatedly beyond 3 km")
	if _max_active_islands > MAX_ACTIVE_ISLANDS+world._dungeon_nodes.size():
		_failures.append("Active island mesh cap exceeded")
	if _max_actors > MAX_ACTORS: _failures.append("Creature actor cap exceeded")
	_check_node_maps()
	_finish(report)

func _wait_wall_seconds(seconds: float) -> void:
	var began_us := Time.get_ticks_usec()
	while float(Time.get_ticks_usec()-began_us)/1000000.0 < seconds:
		await process_frame

func _sample(elapsed_s: float, start_position: Vector3) -> void:
	var active_ids: Array[String] = []
	var new_ids: Array[String] = []
	for island in world.island_records:
		if not island.get("procedural",false): continue
		var id := str(island.id)
		active_ids.append(id)
		if not _seen_ids.has(id):
			_seen_ids[id] = true
			new_ids.append(id)
		# The boat keeps harbour islands resident; count only islands in the remote flight corridor.
		if wizard.global_position.x-start_position.x>3000.0 and island.center.x-start_position.x>2000.0:
			_seen_far_ids[id] = true
	var proxy_instances := 0
	for batch in world._proxy_batches.values():
		if is_instance_valid(batch) and batch.multimesh:
			proxy_instances += batch.multimesh.instance_count
	var pending_phase := ""
	if not world._pending_stream.is_empty():
		pending_phase = str(world._pending_stream.get("phase",""))
	var actor_count: int = game.creature_manager.actors.size()
	var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var pending_surface := 0
	if not world._pending_stream.is_empty() and is_instance_valid(world._pending_stream.get("surface_node",null)):
		pending_surface = 1
	var active_count: int = world._stream_nodes.size()+pending_surface
	_max_active_islands = maxi(_max_active_islands,active_count)
	_max_actors = maxi(_max_actors,actor_count)
	_max_nodes = maxi(_max_nodes,node_count)
	_max_nav_graphs = maxi(_max_nav_graphs,world.navigation_graphs.size())
	_samples.append({
		"t_s":snappedf(elapsed_s,0.001),
		"position":_vec(wizard.global_position),
		"ground_height_m":world.sample_ground_height(wizard.global_position.x,wizard.global_position.z),
		"east_distance_m":wizard.global_position.x-start_position.x,
		"active_procedural_islands":active_count,
		"completed_procedural_islands":world._stream_nodes.size(),
		"active_ids":active_ids,
		"new_ids":new_ids,
		"horizon_proxy_instances":proxy_instances,
		"pending_stream_phase":pending_phase,
		"nav_graphs":world.navigation_graphs.size(),
		"terrain_height_images":world._island_images.size(),
		"terrain_origins":world._island_origins.size(),
		"nodes":node_count,
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"creature_actors":actor_count,
		"process_monitor_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
		"physics_monitor_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
	})

func _check_node_maps() -> void:
	var active: Dictionary = {}
	for island in world.island_records:
		if island.get("procedural",false): active[str(island.id)] = true
	if not world._pending_stream.is_empty():
		active[str(world._pending_stream.island.id)] = true
	for id in world._stream_nodes:
		if not active.has(str(id)):
			_failures.append("Stale streamed node map: %s" % id)
	for id in world.navigation_graphs:
		if str(id).begins_with("proc_") and not active.has(str(id)):
			_failures.append("Stale procedural navigation graph: %s" % id)
	for id in world._path_overlay_nodes:
		if str(id).begins_with("proc_") and not active.has(str(id)):
			_failures.append("Stale procedural path overlay: %s" % id)
	for id in world._island_images:
		if str(id).begins_with("proc_") and not active.has(str(id)):
			_failures.append("Stale procedural height image: %s" % id)
	for id in world._island_origins:
		if str(id).begins_with("proc_") and not active.has(str(id)):
			_failures.append("Stale procedural height origin: %s" % id)

func _screenshot(filename: String) -> int:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image().save_png(OUTPUT+filename)

func _insert_largest(entries: Array[Dictionary], entry: Dictionary, cap: int) -> void:
	entries.append(entry)
	entries.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.gap_ms)>float(b.gap_ms))
	if entries.size()>cap: entries.resize(cap)

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	var total := 0.0
	var over_33 := 0
	var over_50 := 0
	var over_100 := 0
	for value in values:
		total += value
		if value>33.0: over_33 += 1
		if value>50.0: over_50 += 1
		if value>100.0: over_100 += 1
	return {"samples":values.size(),"mean":total/values.size(),"median":_percentile(values,0.5),"p95":_percentile(values,0.95),"p99":_percentile(values,0.99),"max":values.back(),"over_33ms":over_33,"over_50ms":over_50,"over_100ms":over_100}

func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(ceili(fraction*values.size())-1,0,values.size()-1)]

func _vec(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]

func _finish(report: Dictionary) -> void:
	Input.action_release("forward")
	report["failures"] = _failures
	report["passed"] = _failures.is_empty()
	var path := OUTPUT+"procedural_flight_profile.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		push_error("Could not write procedural flight report: %s" % path)
		if session: session.stop_session()
		quit(2)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PROCEDURAL_FLIGHT_COMPLETE ",path," passed=",report.passed," failures=",_failures)
	if session: session.stop_session()
	quit(0 if _failures.is_empty() else 1)
