extends SceneTree
## Integration smoke test: instantiate the real scene and exercise its public loop.
## No world save writes; assertions include physical traversal, not only domain calls.

var game: Node3D
var assertions := 0
var failures := 0
var observations: Array[String] = []
var elapsed := 0.0

func _initialize() -> void:
	Engine.max_fps = 120
	Engine.time_scale = 4.0
	call_deferred("_run")

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 720.0:
		push_error("Gameplay integration exceeded its bounded runtime.")
		quit(2)
	return false

func check(condition: bool, label: String, detail: String = "") -> void:
	assertions += 1
	if not condition:
		failures += 1
	var line := ("PASS " if condition else "FAIL ") + label + (" | " + detail if not detail.is_empty() else "")
	observations.append(line)
	print(line)

func _run() -> void:
	var session: Node = root.get_node("Session")
	session.save_enabled = false
	session.identity_profile = "gameplay_integration"
	session._identity_token = Crypto.new().generate_random_bytes(32).hex_encode()
	session.local_player_id = session._identity_token.sha256_text().substr(0, 24)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	if game.archipelago == null or game.ocean == null or not game.archipelago.built:
		check(false, "main scene world scripts compile and build successfully")
		_finish()
		return
	game._host("Integration sandbox", 7319, "Integration Wizard", 1)
	if not session.hosting or game.local_wizard == null:
		check(false, "actual main scene hosts and creates local first-person wizard")
		_finish()
		return
	var player_id: String = session.local_player_id
	var wizard: CharacterBody3D = game.local_wizard
	var crew_id: String = session.world.players[player_id].crew_id
	var ship_id: String = session.world.crews[crew_id].ship_id
	var boat: Node3D = game.boats[ship_id]
	check(game.in_game and wizard.camera != null, "actual main scene hosts and creates local first-person wizard")
	var record_position: Array = session.world.ships[ship_id].position
	var expected := Vector3(float(record_position[0]), float(record_position[1]), float(record_position[2]))
	check(boat.position.distance_to(expected) < 1.0, "new boat scene agrees with domain dock placement", "scene=%s domain=%s" % [boat.position, expected])
	await _advance(30)
	var spawn_floor: float = game.archipelago.sample_ground_height(wizard.position.x, wizard.position.z)
	check(wizard.position.y >= spawn_floor - 0.15, "spawn settles above real terrain", "wizard=%s ground=%.2f" % [wizard.position, spawn_floor])

	var starter: Dictionary = game.archipelago.island_records[0]
	var cache_position := Vector3.ZERO
	var shop_position := Vector3.ZERO
	for item in game.interactables:
		if item.kind == "cache": cache_position = item.position
		if item.kind == "shop": shop_position = item.position
	var route := PackedVector3Array()
	var spawn_poi := Vector3.ZERO
	for poi in starter.pois:
		if poi.kind == "spawn": spawn_poi = poi.position
	for path in starter.paths:
		if path[path.size() - 1].distance_to(spawn_poi) < 2.0:
			for index in range(path.size() - 1, -1, -1): route.append(path[index])
	for path in starter.paths:
		if path[path.size() - 1].distance_to(cache_position) < 2.0:
			for point in path: route.append(point)
	var walked := await _follow_route(route, cache_position)
	check(walked, "starter graded routes are physically walkable to initial glyph cache", "position=%s cache=%s" % [wizard.position, cache_position])
	# Continue unrelated checks even when a route fixture exposes an obstruction.
	wizard.position = cache_position + Vector3(0, 0.3, 2.2)
	session.world.update_player_position(player_id, wizard.position, true)
	game._action(player_id, "claim_cache", {})
	check(session.world.players[player_id].learned.has("wind") and not game.current_recipe.is_empty(), "nearby tutorial cache unlocks and selects a usable spell")

	wizard.position = shop_position + Vector3(0, 0, -1.0)
	session.world.update_player_position(player_id, wizard.position, true)
	var before_gold: int = int(session.world.players[player_id].inventory.gold)
	game._action(player_id, "buy", {"item": "healing_potion"})
	check(int(session.world.players[player_id].inventory.gold) == before_gold - 18, "actual shop action purchases item at NPC")
	var glyph_count: int = session.world.players[player_id].learned.size()
	game._action(player_id, "buy", {"item": "power"})
	check(session.world.players[player_id].learned.size() == glyph_count, "actual shop never sells spell knowledge")

	# Use clear water to isolate boarding from terrain and dock collisions.
	boat.position = Vector3(70, 0, 70)
	boat.heading = 0
	boat.speed = 0
	boat.wind_charge = 0
	wizard.helm_id = ""
	wizard.position = boat.position + Vector3(0, -0.95, 7.0)
	wizard.velocity = Vector3.ZERO
	wizard.yaw = 0
	Input.action_press("forward")
	Input.action_press("jump")
	var boarded := false
	var max_relative_height := -100.0
	for index in 100:
		await _advance(1)
		max_relative_height = maxf(max_relative_height, wizard.position.y - boat.position.y)
		if boat.deck_contains(wizard.position) and wizard.position.y - boat.position.y > 1.0:
			boarded = true
	_release_controls()
	# The authored sloop has an explicit port boarding ladder, rather than a jump exploit.
	wizard.position=boat.to_global(Vector3(-3.0,-0.6,1.7))
	var board_hint:Dictionary=game._nearest_interaction(wizard.position)
	game._action(player_id,"interact",{"kind":"board","ship_id":ship_id})
	check(board_hint.get("kind","")=="board" and boat.deck_contains(wizard.position), "a swimmer can discover and climb the port boarding ladder", "feet=%s" % boat.to_local(wizard.position))

	wizard.position = boat.to_global(Vector3(0, 1.18, 3.5))
	session.world.update_player_position(player_id, wizard.position, false)
	session.world.update_ship_position(ship_id, boat.position, false)
	game._action(player_id, "helm", {"ship_id": ship_id})
	check(boat.pilot_id == player_id and wizard.helm_id == ship_id, "actual helm interaction acquires owned ship")
	var previous := boat.position
	Input.action_press("forward")
	await _advance(40)
	_release_controls()
	check(boat.position.distance_to(previous) > 0.5, "WASD helm control moves the simulated boat")
	var sail_body: Node
	for child in boat.get_children():
		if child.has_meta("sail_ship_id"): sail_body = child
	var wind_before: float = boat.wind_charge
	game._apply_impact({"owner": player_id, "recipe": ["projectile", "wind", "push"], "direction": Vector3.FORWARD}, {"collider": sail_body})
	check(boat.wind_charge > wind_before, "wind impact on actual sail collider accelerates boat")

	session.world.players[player_id].inventory.hearthstone = 1
	game._action(player_id, "hearthstone", {})
	check(wizard.helm_id.is_empty() and boat.pilot_id.is_empty(), "hearthstone releases both ends of helm ownership", "wizard helm=%s boat pilot=%s" % [wizard.helm_id, boat.pilot_id])

	wizard.position = Vector3(70, 0, 70)
	session.world.update_player_position(player_id, wizard.position, false)
	session.world.kill_player(player_id, true)
	session.publish_state()
	check(not wizard.alive and session.world.players[player_id].inventory == {"spellbook": 1}, "death reaches actor and drops all gear except book")
	game._action(player_id, "respawn", {})
	check(wizard.alive and wizard.position.distance_to(boat.position) < 6.0, "actual respawn places wizard on surviving crew ship")
	boat.position = Vector3(70, 0, 70)
	boat.heading = 0
	boat.pilot_id = ""
	boat.wind_charge = 8.0
	wizard.helm_id = ""
	wizard.velocity = Vector3.ZERO
	wizard.position = boat.to_global(Vector3(0, 1.21, 1))
	await _advance(90)
	var deck_position: Vector3 = boat.to_local(wizard.position)
	check(boat.deck_contains(wizard.position) and Vector2(deck_position.x, deck_position.z - 1.0).length() < 2.0, "unpiloted standing wizard rides moving deck without sliding off", "relative=%s" % deck_position)

	for fall in game.archipelago.waterfall_volumes:
		wizard.helm_id = ""
		boat.pilot_id = ""
		wizard.position = Vector3(fall.center.x, -0.5, fall.center.z)
		wizard.velocity = Vector3.ZERO
		Input.action_press("jump")
		var top_reached := false
		for index in 300:
			await _advance(1)
			if wizard.position.y >= float(fall.top) - 1.0:
				top_reached = true
				break
		_release_controls()
		check(top_reached, "waterfall ascent reaches " + str(fall.island_id), "feet=%.2f top=%.2f" % [wizard.position.y, fall.top])
		if top_reached:
			var exit_position: Vector3 = fall.exit
			var exited := await _follow_route(PackedVector3Array([exit_position]), exit_position, 120, 1.6)
			await _advance(20)
			check(exited and wizard.is_on_floor() and game.archipelago.waterfall_at(wizard.position).is_empty(), "waterfall has stable walkable exit on " + str(fall.island_id), "feet=%s exit=%s grounded=%s" % [wizard.position, exit_position, wizard.is_on_floor()])
	_finish()

func _advance(frames: int) -> void:
	for index in frames:
		await physics_frame
		game._physics_process(1.0 / 15.0)

func _follow_route(route: PackedVector3Array, destination: Vector3, max_steps: int = 650, arrival_distance: float = 5.0) -> bool:
	var wizard: Node3D = game.local_wizard
	var steps := 0
	for waypoint in route:
		while Vector2(wizard.position.x - waypoint.x, wizard.position.z - waypoint.z).length() > minf(1.7, arrival_distance * 0.6):
			if wizard.position.distance_to(destination) < arrival_distance:
				_release_controls()
				return true
			var direction: Vector3 = waypoint - wizard.position
			wizard.yaw = atan2(-direction.x, -direction.z)
			Input.action_press("forward")
			Input.action_press("sprint")
			await _advance(1)
			steps += 1
			if steps >= max_steps:
				_release_controls()
				return false
	_release_controls()
	return wizard.position.distance_to(destination) < arrival_distance

func _release_controls() -> void:
	for action in ["forward", "back", "left", "right", "jump", "dive", "sprint"]:
		Input.action_release(action)

func _finish() -> void:
	_release_controls()
	print("GAMEPLAY_TEST: %d assertions, %d failures" % [assertions, failures])
	var report := "# Gameplay integration review\n\nReal main scene with actual actors and physics; headless, accelerated simulation, seed 7319.\n\n"
	for line in observations:
		report += "- " + line + "\n"
	report += "\n%d assertions; %d failures. Host test uses no persistent world saves.\n" % [assertions, failures]
	var file := FileAccess.open("res://.dream-loop/gameplay-review.md", FileAccess.WRITE)
	if file:
		file.store_string(report)
		file.close()
	root.get_node("Session").stop_session()
	quit(0 if failures == 0 and assertions >= 12 else 1)
