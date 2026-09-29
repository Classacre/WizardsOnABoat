extends SceneTree
## Rendered, save-free gameplay benchmark. Run with Godot --path . --script res://tests/performance_profile.gd.

const OUTPUT := "res://output/performance/"
const PHASE_SECONDS := 9.0
const WARMUP_SECONDS := 6.0

var game
var camera: Camera3D
var boat: Node3D
var _report: Dictionary = {}
var _last_tick_us := 0
var _isolated_saves := false
var _sailing := false
var _tag := ""
var _extended := false
var _quick := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var session: Variant = root.get_node("Session")
	_isolated_saves = OS.get_cmdline_user_args().has("--profile-save")
	_sailing = OS.get_cmdline_user_args().has("--profile-sailing")
	_extended = OS.get_cmdline_user_args().has("--profile-extended")
	_quick = OS.get_cmdline_user_args().has("--profile-quick")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-tag="):
			_tag = arg.trim_prefix("--profile-tag=").validate_filename()
	session.save_enabled = false
	session.identity_profile = "performance_profile"
	# Avoid even creating a benchmark identity file under the user's real save directory.
	session._identity_token = Crypto.new().generate_random_bytes(32).hex_encode()
	session.local_player_id = session._identity_token.sha256_text().substr(0, 24)
	_report = {
		"benchmark": "rendered_sailing_v2" if _sailing else "rendered_gameplay_v1",
		"created_at": Time.get_datetime_string_from_system(true),
		"godot": Engine.get_version_info().string,
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"viewport": [root.size.x, root.size.y],
		"save_enabled": session.save_enabled,
		"isolated_saves": _isolated_saves,
		"phases": [],
	}
	var start_us := Time.get_ticks_usec()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	_report["scene_build_ms"] = (Time.get_ticks_usec() - start_us) / 1000.0
	start_us = Time.get_ticks_usec()
	game._host("performance-%d" % Time.get_ticks_usec(), 7319, "Profiler", 1)
	_report["host_enter_ms"] = (Time.get_ticks_usec() - start_us) / 1000.0
	if not session.hosting or game.boats.is_empty():
		push_error("Benchmark could not start isolated host/boat")
		quit(1)
		return
	if _isolated_saves:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp/performance/"))
		session._save_path = "res://tmp/performance/sandbox-world.json"
		session.save_enabled = true
		_report["save_path"] = session._save_path
		_report["save_enabled"] = session.save_enabled
	game.hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera = game.preview_camera
	camera.current = true
	boat = game.boats.values()[0]
	_report["initial_mobs"] = session.world.mobs.size()
	_report["initial_creature_actors"] = game.creature_manager.actors.size()
	_report["initial_nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	_report["initial_resource_count"] = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	print("PERF_START build_ms=", _report.scene_build_ms, " host_ms=", _report.host_enter_ms, " mobs=", _report.initial_mobs)
	await _run_phase("warmup_harbour", WARMUP_SECONDS, "harbour", false)
	await _run_phase("harbour_boat", PHASE_SECONDS, "boat", true)
	if not _quick:
		await _run_phase("sea_crossing", PHASE_SECONDS, "crossing", true)
		await _run_phase("rootwatch_creatures", PHASE_SECONDS, "island", true)
	if _extended and not _quick:
		await _run_phase("steady_harbour_boat", PHASE_SECONDS, "boat", false)
		await _run_phase("steady_sea_crossing", PHASE_SECONDS, "crossing", false)
		await _run_phase("steady_rootwatch_creatures", PHASE_SECONDS, "island", false)
	if _sailing:
		_report["spell_visual_assertions"] = await _verify_spell_visuals()
	_report["final_mobs"] = session.world.mobs.size()
	_report["final_creature_actors"] = game.creature_manager.actors.size()
	var path := OUTPUT + ("isolated_autosave_v2.json" if _sailing and _isolated_saves else "sailing_v2.json" if _sailing else "isolated_autosave.json" if _isolated_saves else "baseline.json")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-output="):
			path = arg.trim_prefix("--profile-output=")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write profile: %s" % path)
		quit(2)
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	print("PERF_COMPLETE ", path)
	session.stop_session()
	quit(0 if not _sailing or _report.spell_visual_assertions.passed else 3)

func _run_phase(label: String, seconds: float, mode: String, capture: bool) -> void:
	if mode == "boat" and _sailing:
		_configure_sailing()
	var gaps: Array[float] = []
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var primitives: Array[float] = []
	var frame_trace: Array[Dictionary] = []
	var save_events: Array[Dictionary] = []
	var previous_save_elapsed: float = root.get_node("Session").get("_save_elapsed")
	var boat_start: Vector3 = boat.global_position
	var next_spell_s := 1.0
	var spell_count := 0
	var spell_events: Array[Dictionary] = []
	var frame_start_us := Time.get_ticks_usec()
	_last_tick_us = 0
	var elapsed := 0.0
	var first_frame_latency_ms := 0.0
	while elapsed < seconds:
		await process_frame
		var now_us := Time.get_ticks_usec()
		if _last_tick_us == 0:
			first_frame_latency_ms = float(now_us - frame_start_us) / 1000.0
		if _last_tick_us != 0:
			var gap_ms := float(now_us - _last_tick_us) / 1000.0
			gaps.append(gap_ms)
			elapsed += gap_ms / 1000.0
		_last_tick_us = now_us
		_set_camera(mode, elapsed / seconds)
		if _sailing and mode == "island" and elapsed >= next_spell_s:
			var island: Vector3 = game.archipelago.island_records[1].center
			var spell_start_us := Time.get_ticks_usec()
			game._spawn_projectile(root.get_node("Session").get("local_player_id"), ["projectile", "wind"], island + Vector3(0, 28, 0), Vector3.DOWN, 32.0, 1.7)
			spell_events.append({"t_s": snappedf(elapsed, 0.001), "spawn_ms": float(Time.get_ticks_usec() - spell_start_us) / 1000.0})
			spell_count += 1
			next_spell_s += 1.5
		var cpu_process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var cpu_physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var save_elapsed: float = root.get_node("Session").get("_save_elapsed")
		if save_elapsed + 0.5 < previous_save_elapsed:
			save_events.append({"t_s": snappedf(elapsed, 0.001), "gap_ms": gaps.back() if not gaps.is_empty() else 0.0, "process_ms": cpu_process_ms})
		previous_save_elapsed = save_elapsed
		process_ms.append(cpu_process_ms)
		physics_ms.append(cpu_physics_ms)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		if gaps.size() > 0:
			frame_trace.append({"t_s": snappedf(elapsed, 0.001), "gap_ms": gaps.back(), "process_ms": cpu_process_ms, "physics_ms": cpu_physics_ms})
	var phase := {
		"name": label,
		"duration_s": (Time.get_ticks_usec() - frame_start_us) / 1000000.0,
		"first_frame_latency_ms": first_frame_latency_ms,
		"save_events": save_events,
		"boat_distance_m": boat_start.distance_to(boat.global_position),
		"spells_spawned": spell_count,
		"spell_events": spell_events,
		"frame_gaps_ms": _stats(gaps),
		"frame_trace": frame_trace,
		"process_ms": _stats(process_ms),
		"physics_ms": _stats(physics_ms),
		"draw_calls": _stats(draw_calls),
		"primitives": _stats(primitives),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"objects_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"mobs": root.get_node("Session").get("world").mobs.size(),
		"creature_actors": game.creature_manager.actors.size(),
	}
	_report.phases.append(phase)
	print("PERF_PHASE ", label, " gaps=", JSON.stringify(phase.frame_gaps_ms), " process=", JSON.stringify(phase.process_ms), " physics=", JSON.stringify(phase.physics_ms), " boat_m=", phase.boat_distance_m, " saves=", JSON.stringify(save_events))
	if mode == "boat" and _sailing:
		Input.action_release("forward")
	if capture:
		await RenderingServer.frame_post_draw
		var suffix := "_" + _tag if not _tag.is_empty() else "_autosave_v2" if _sailing and _isolated_saves else "_v2" if _sailing else "_autosave" if _isolated_saves else ""
		var png_path := OUTPUT + label + suffix + ".png"
		var error := root.get_texture().get_image().save_png(png_path)
		print("PERF_CAPTURE ", png_path, " error=", error)

func _configure_sailing() -> void:
	var session: Variant = root.get_node("Session")
	boat.global_position = Vector3(5, 0, 60)
	boat.heading = -0.55
	boat.pilot_id = session.local_player_id
	game.local_wizard.helm_id = boat.ship_id
	game.local_wizard.global_position = boat.to_global(Vector3(-1.6, 2.0, 2.5))
	session.world.update_ship_position(boat.ship_id, boat.global_position, true)
	Input.action_press("forward")
	print("PERF_HELM allowed=", session.world.can_pilot(session.local_player_id, boat.ship_id), " ship=", boat.ship_id)

func _verify_spell_visuals() -> Dictionary:
	var session: Variant = root.get_node("Session")
	var before: int = game.projectiles.size()
	game._cast(session.local_player_id, ["projectile", "wind", "split"], Vector3.ZERO, Vector3.UP)
	var split_count: int = game.projectiles.size() - before
	var shared_meshes := split_count == 3
	var three_rings := split_count == 3
	var rotated := false
	if split_count == 3:
		var first: Dictionary = game.projectiles[before]
		for index in range(before, before + 3):
			var shot: Dictionary = game.projectiles[index]
			shared_meshes = shared_meshes and shot.node.mesh == first.node.mesh
			three_rings = three_rings and shot.rings.size() == 3
			if shot.rings.size() == 3:
				for ring_index in 3:
					shared_meshes = shared_meshes and shot.rings[ring_index].mesh == first.rings[ring_index].mesh
		for frame in 4:
			await physics_frame
		rotated = first.rings[0].rotation.z > 0.0
	var ember_before: int = game.projectiles.size()
	game._spawn_projectile(session.local_player_id, ["projectile", "spark"], Vector3(0, 100, 0), Vector3.UP, 32.0, 1.7)
	var ember_created: bool = game.projectiles.size() == ember_before + 1
	var ember_orange := false
	if ember_created:
		var ember: Dictionary = game.projectiles.back()
		ember_orange = ember.node.mesh.material.albedo_color == Color("ffb86a")
	var result := {"passed": split_count == 3 and shared_meshes and three_rings and rotated and ember_created and ember_orange and game._projectile_prewarmed,
		"prewarmed": game._projectile_prewarmed, "split_count": split_count,
		"shared_meshes": shared_meshes, "three_rings": three_rings,
		"rings_rotated": rotated, "ember_orange": ember_orange}
	print("PERF_SPELL_ASSERT ", JSON.stringify(result))
	return result

func _set_camera(mode: String, progress: float) -> void:
	match mode:
		"harbour":
			camera.position = Vector3(6.4, 6.4, 73.0)
			camera.look_at(Vector3(6.4, 4.0, 58.0))
		"boat":
			var center: Vector3 = boat.global_position
			var orbit := -1.0 + progress * 0.6
			camera.global_position = center + Vector3(sin(orbit) * 16.0, 8.0, cos(orbit) * 16.0)
			camera.look_at(center + Vector3(0, 2.0, 0))
		"crossing":
			var from := boat.global_position
			var to := Vector3(165, 0, -168)
			var center: Vector3 = from.lerp(to, progress)
			camera.global_position = center + Vector3(12, 10, 17)
			camera.look_at(center + Vector3(-8, 1, -13))
		"island":
			var island: Vector3 = game.archipelago.island_records[1].center
			var angle := progress * TAU * 0.5
			camera.global_position = island + Vector3(cos(angle) * 46.0, 22.0, sin(angle) * 46.0)
			camera.look_at(island + Vector3(0, 7, 0))

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	values.sort()
	var total := 0.0
	var over_33 := 0
	var over_50 := 0
	var over_100 := 0
	for value in values:
		total += value
		if value > 33.0: over_33 += 1
		if value > 50.0: over_50 += 1
		if value > 100.0: over_100 += 1
	return {
		"samples": values.size(), "mean": total / values.size(),
		"median": _percentile(values, 0.5), "p95": _percentile(values, 0.95),
		"p99": _percentile(values, 0.99), "worst": values.back(),
		"over_33ms": over_33, "over_50ms": over_50, "over_100ms": over_100,
	}

func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(ceili(fraction * values.size()) - 1, 0, values.size() - 1)]
