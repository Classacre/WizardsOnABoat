extends SceneTree
## Run two headless processes with --probe-host and --probe-client.
## Optional --probe-port=NNN, --probe-duration=N, --probe-profile=ID.

var session: Node
var elapsed := 0.0
var duration := 8.0
var host := false
var registered := false
var received_remote_input := false
var received_simulation := false
var received_cast := false
var received_staff_cast := false
var forbidden_cast_received := false
var updates := 0
var next_input := 0.0
var port := 24671
var profile := "probe_client"
var expected_players := 2
var test_six_ships := false
var peak_players := 0
var peak_ships := 0
var staff_id := ""
var cast_iteration := 0
var expect_refused := false
var refusal_received := false
var seventh_ship_rejected := false
var malformed_action_received := false

func _initialize() -> void:
	Engine.max_fps = 30
	for arg in OS.get_cmdline_user_args():
		if arg == "--probe-host":
			host = true
		if arg.begins_with("--probe-port="):
			port = int(arg.split("=")[1])
		if arg.begins_with("--probe-duration="):
			duration = float(arg.split("=")[1])
		if arg.begins_with("--probe-profile="):
			profile = arg.split("=")[1]
		if arg.begins_with("--probe-expect="):
			expected_players = int(arg.split("=")[1])
		if arg == "--probe-six-ships":
			test_six_ships = true
		if arg == "--probe-refused":
			expect_refused = true
	call_deferred("_begin")

func _begin() -> void:
	session = root.get_node_or_null("Session")
	if session == null:
		session = load("res://scripts/net/session.gd").new()
		session.name = "Session"
		root.add_child(session)
	session.identity_profile = "probe_host" if host else profile
	session.display_name = "Host Probe" if host else profile
	session.save_enabled = false
	session.state_changed.connect(_state)
	session.simulation_received.connect(_simulation)
	session.player_joined.connect(_joined)
	session.input_received.connect(_input)
	session.cast_requested.connect(_cast)
	session.staff_cast_requested.connect(_staff_cast)
	session.action_requested.connect(_action)
	session.connection_status.connect(_status)
	var error: Error = session.start_host("network-probe", 812, port) if host else session.join_host("127.0.0.1", port)
	if error != OK:
		quit(2)
	elif expect_refused:
		var remote: ENetPacketPeer = session._peer.get_peer(1)
		if remote != null:
			remote.set_timeout(2, 1000, 4000)

func _process(delta: float) -> bool:
	if session == null:
		return false
	elapsed += delta
	if host:
		peak_players = maxi(peak_players, session.world.online_count())
		peak_ships = maxi(peak_ships, session.world.active_ship_count())
		session.broadcast_simulation({"probe_tick": int(elapsed * 10.0)})
	elif registered and elapsed >= next_input:
		next_input = elapsed + 0.4
		session.submit_input({"move": Vector2(0.5, 0.0), "yaw": 0.3, "jump": false, "player_id": "spoofed"})
		cast_iteration += 1
		if cast_iteration % 2 == 0 and not staff_id.is_empty():
			session.request_staff_cast(staff_id, Vector3(0.0, 3.5, 0.0), Vector3.FORWARD)
		else:
			session.request_cast(["projectile", "wind"], Vector3(0.0, 3.5, 0.0), Vector3.FORWARD)
		# Locked glyph and invalid geometry must never reach host simulation.
		session.request_cast(["projectile", "heal"], Vector3.ZERO, Vector3.FORWARD)
		session.request_cast(["projectile", "wind"], Vector3(99999, 0, 0), Vector3.FORWARD)
		session.request_action("save_spell", {"name": "malformed", "recipe": "not an array"})
	if elapsed >= duration:
		if expect_refused:
			var refused: bool = not registered and updates == 0 and refusal_received
			print("NETWORK_CAPACITY_REFUSAL: ", "PASS" if refused else "FAIL", " registered=", registered, " snapshots=", updates, " refused=", refusal_received)
			quit(0 if refused else 1)
			return false
		if host:
			var ok: bool = registered and received_remote_input and received_cast and received_staff_cast and not forbidden_cast_received and not malformed_action_received and session.world.invariant_errors().is_empty() and peak_players >= expected_players and (not test_six_ships or peak_ships == 6 and seventh_ship_rejected)
			print("NETWORK_HOST_PROBE: ", "PASS" if ok else "FAIL", " registration=", registered, " input=", received_remote_input, " cast=", received_cast, " staff=", received_staff_cast, " forbidden=", forbidden_cast_received, " peak_players=", peak_players, " peak_ships=", peak_ships, " seventh_rejected=", seventh_ship_rejected)
			quit(0 if ok else 1)
		else:
			var ok: bool = registered and received_simulation and updates > 1
			print("NETWORK_CLIENT_PROBE: ", "PASS" if ok else "FAIL", " registration=", registered, " snapshots=", updates, " simulation=", received_simulation)
			quit(0 if ok else 1)
	return false

func _joined(player_id: String, peer_id: int) -> void:
	if host and peer_id != 1:
		registered = true
		session.world.claim_apprentice_cache(player_id)
		for item_id in session.world.players[player_id].equipment:
			if session.world.items.has(item_id):
				session.world.teach_staff(player_id, item_id, "Gale")
		if test_six_ships and session.world.online_count() == 18 and session.world.active_ship_count() == 5:
			session.world.create_crew(player_id, "Sixth Probe Crew", Time.get_unix_time_from_system())
			seventh_ship_rejected = not session.world.create_crew(session.local_player_id, "Forbidden Seventh", Time.get_unix_time_from_system()).ok

func _state(snapshot: Dictionary) -> void:
	updates += 1
	if not host and snapshot.get("players", {}).has(session.local_player_id):
		registered = true
		for item_id in snapshot.players[session.local_player_id].equipment:
			if snapshot.get("items", {}).has(item_id):
				staff_id = item_id

func _simulation(snapshot: Dictionary) -> void:
	received_simulation = snapshot.has("probe_tick")

func _input(peer_id: int, data: Dictionary) -> void:
	if peer_id != 1 and data.get("player_id", "") != "spoofed" and data.get("move") == Vector2(0.5, 0.0):
		received_remote_input = true

func _cast(_player_id: String, recipe: Array, origin: Vector3, _direction: Vector3) -> void:
	if recipe.has("heal") or origin.length() > 100:
		forbidden_cast_received = true
	else:
		received_cast = true

func _staff_cast(_player_id: String, recipe: Array, _origin: Vector3, _direction: Vector3, modifiers: Dictionary) -> void:
	if recipe != ["projectile", "wind", "push"]:
		forbidden_cast_received = true
		return
	for key in ["power_multiplier", "impulse_multiplier", "range_multiplier", "speed_multiplier"]:
		if float(modifiers.get(key, 1.0)) > 1.0:
			received_staff_cast = true

func _status(message: String) -> void:
	print("PROBE_STATUS: " + message)
	if message.begins_with("Connection failed") or message.begins_with("Join refused"):
		refusal_received = true

func _action(_player_id: String, action: String, data: Dictionary) -> void:
	if action == "save_spell" and not data.get("recipe") is Array:
		malformed_action_received = true
