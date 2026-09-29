extends Node
## Player-hosted ENet session. Only peer 1 mutates the world model.
## Identity tokens are private bearer credentials; snapshots expose only hashes.

const WorldModel = preload("res://scripts/data/world_state.gd")
const Catalog = preload("res://scripts/data/game_catalog.gd")
const DEFAULT_PORT := 24567
const MAX_PACKET_INPUTS_PER_SECOND := 90

signal state_changed(snapshot: Dictionary)
signal cast_requested(player_id: String, recipe: Array, origin: Vector3, direction: Vector3)
signal staff_cast_requested(player_id: String, recipe: Array, origin: Vector3, direction: Vector3, modifiers: Dictionary)
signal input_received(peer_id: int, data: Dictionary)
signal action_requested(player_id: String, action: String, data: Dictionary)
signal player_joined(player_id: String, peer_id: int)
signal player_left(player_id: String, peer_id: int)
signal connection_status(message: String)
signal simulation_received(snapshot: Dictionary)

var world: RefCounted
var local_player_id := ""
var peer_player_ids: Dictionary = {}
var latest_snapshot: Dictionary = {}
var hosting := false
var display_name := "Wizard"
var identity_profile := "default"
var save_enabled := true
var save_directory := "user://worlds"
var _identity_token := ""
var _peer: ENetMultiplayerPeer
var _save_path := ""
var _publish_elapsed := 0.0
var _save_elapsed := 0.0
var _rate_windows: Dictionary = {}
var _last_cast: Dictionary = {}
var _last_action: Dictionary = {}
var _pending_registration: Dictionary = {}
var _connected_port := DEFAULT_PORT

func _ready() -> void:
	# Every gameplay message travels through the authoritative host. Disabling
	# peer relay also avoids sending peer-list churn into disconnecting channels.
	if multiplayer is SceneMultiplayer:
		multiplayer.server_relay = false
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.peer_connected.connect(_peer_connected)

func _ensure_identity() -> void:
	if not _identity_token.is_empty():
		return
	var config := ConfigFile.new()
	var path := "user://identity_%s.cfg" % identity_profile.validate_filename()
	if config.load(path) == OK:
		_identity_token = str(config.get_value("identity", "token", ""))
	if _identity_token.length() != 64 or not _identity_token.is_valid_hex_number(false):
		_identity_token = Crypto.new().generate_random_bytes(32).hex_encode()
		config.set_value("identity", "token", _identity_token)
		config.save(path)
	local_player_id = _identity_token.sha256_text().substr(0, 24)

func saved_worlds() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(save_directory)
	if directory == null:
		return result
	for filename in directory.get_files():
		if not filename.ends_with(".json"):
			continue
		var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_directory.path_join(filename)))
		if not record is Dictionary or record.get("version",-1) != WorldModel.VERSION:
			continue
		var world_name := str(record.get("world_id",""))
		var seed: Variant = record.get("seed")
		if world_name.is_empty() or not (seed is int or seed is float) or filename != world_name.sha256_text().substr(0,24) + ".json":
			continue
		result.append({"name":world_name,"seed":int(seed),"generator_version":int(record.get("generator_version",1))})
	result.sort_custom(func(a: Dictionary,b: Dictionary): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return result

func start_host(world_id: String = "harbour", world_seed: int = 72841, port: int = DEFAULT_PORT, generator_version: int = WorldModel.CURRENT_GENERATOR_VERSION) -> Error:
	if generator_version < 1 or generator_version > WorldModel.CURRENT_GENERATOR_VERSION:
		connection_status.emit("Unsupported world generator version %d." % generator_version)
		return ERR_INVALID_PARAMETER
	stop_session()
	_ensure_identity()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, WorldModel.MAX_PLAYERS - 1)
	if error != OK:
		connection_status.emit("Could not host on UDP port %d (error %d)." % [port, error])
		return error
	multiplayer.multiplayer_peer = _peer
	hosting = true
	world = WorldModel.new(world_id, world_seed, generator_version)
	_save_path = save_directory.path_join("%s.json" % world_id.sha256_text().substr(0, 24))
	if save_enabled and FileAccess.file_exists(_save_path):
		var loaded: Dictionary = world.load_from(_save_path, world_seed)
		if not loaded.ok:
			var message := "Save was not loaded: " + str(loaded.error)
			# Never replace a damaged or incompatible save with a fresh empty world.
			hosting = false
			stop_session()
			connection_status.emit(message)
			return ERR_INVALID_DATA
	var result: Dictionary = world.connect_player(local_player_id, display_name)
	if not result.ok:
		connection_status.emit(str(result.error))
		stop_session()
		return ERR_CANT_CREATE
	peer_player_ids[1] = local_player_id
	player_joined.emit(local_player_id, 1)
	publish_state()
	connection_status.emit("Hosting %s · seed %d · generator v%d · UDP %d · up to 18 wizards / 6 ships" % [world_id,world.seed_value,world.generator_version,port])
	return OK

func join_host(address: String, port: int = DEFAULT_PORT) -> Error:
	stop_session()
	_ensure_identity()
	_connected_port = port
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address.strip_edges(), port)
	if error != OK:
		connection_status.emit("Connection could not start (error %d)." % error)
		return error
	multiplayer.multiplayer_peer = _peer
	connection_status.emit("Connecting to %s:%d…" % [address, port])
	return OK

func stop_session() -> void:
	if hosting and world != null and save_enabled and not _save_path.is_empty():
		world.save_to(_save_path)
	hosting = false
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	world = null
	peer_player_ids.clear()
	latest_snapshot.clear()
	_rate_windows.clear()
	_last_cast.clear()
	_last_action.clear()
	_pending_registration.clear()
	_publish_elapsed = 0.0
	_save_elapsed = 0.0

func is_session_active() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _process(delta: float) -> void:
	if not hosting or world == null:
		return
	var now := Time.get_unix_time_from_system()
	for peer_id in _pending_registration.keys():
		if now - float(_pending_registration[peer_id]) > 10.0:
			_pending_registration.erase(peer_id)
			_peer.disconnect_peer(int(peer_id))
	world.tick(now)
	_publish_elapsed += delta
	_save_elapsed += delta
	if _publish_elapsed >= 0.5:
		_publish_elapsed = 0.0
		publish_state()
	if save_enabled and _save_elapsed >= 15.0:
		_save_elapsed = 0.0
		var error: Error = world.save_to(_save_path)
		if error != OK:
			connection_status.emit("World save failed (error %d)." % error)

func publish_state(extra: Dictionary = {}) -> void:
	if not hosting or world == null:
		return
	latest_snapshot = world.snapshot()
	if not extra.is_empty():
		latest_snapshot["simulation"] = extra
	state_changed.emit(latest_snapshot)
	for peer_id in _ready_remote_peers():
		_receive_state.rpc_id(peer_id, latest_snapshot)

func broadcast_simulation(snapshot: Dictionary) -> void:
	if hosting:
		for peer_id in _ready_remote_peers():
			_receive_simulation.rpc_id(peer_id, snapshot)

func _ready_remote_peers() -> Array:
	var ready: Array = []
	if _peer == null:
		return ready
	var transport_peers := multiplayer.get_peers()
	for peer_id in peer_player_ids:
		if peer_id == 1 or not transport_peers.has(peer_id):
			continue
		var packet_peer := _peer.get_peer(peer_id)
		if packet_peer != null and packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED and packet_peer.get_channels() > 0:
			ready.append(peer_id)
	return ready

func _peer_connected(peer_id: int) -> void:
	if hosting:
		_pending_registration[peer_id] = Time.get_unix_time_from_system()

func _connected_to_server() -> void:
	_register_peer.rpc_id(1, _identity_token, display_name)

func _connection_failed() -> void:
	connection_status.emit("Connection failed. The world may be full; check the host address and UDP port %d." % _connected_port)
	stop_session()

func _server_disconnected() -> void:
	connection_status.emit("The host has left; world progress remains on the host's computer.")
	stop_session()

func _peer_disconnected(peer_id: int) -> void:
	_pending_registration.erase(peer_id)
	_rate_windows.erase(peer_id)
	if not hosting or not peer_player_ids.has(peer_id):
		return
	var player_id: String = peer_player_ids[peer_id]
	world.disconnect_player(player_id, Time.get_unix_time_from_system())
	peer_player_ids.erase(peer_id)
	_last_cast.erase(player_id)
	_last_action.erase(player_id)
	player_left.emit(player_id, peer_id)
	# ENet may still be clearing other peers from this poll's disconnect batch.
	publish_state.call_deferred()

@rpc("any_peer", "call_remote", "reliable")
func _register_peer(token: String, player_name: String) -> void:
	if not hosting or world == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or peer_player_ids.has(sender) or not _pending_registration.has(sender):
		return
	_pending_registration.erase(sender)
	if token.length() != 64 or not token.is_valid_hex_number(false) or player_name.length() > 96:
		_registration_result.rpc_id(sender, false, "Invalid identity.")
		_peer.disconnect_peer(sender)
		return
	var player_id := token.sha256_text().substr(0, 24)
	var result: Dictionary = world.connect_player(player_id, player_name)
	if not result.ok:
		_registration_result.rpc_id(sender, false, str(result.error))
		# A rejected client cannot occupy a transport slot indefinitely.
		get_tree().create_timer(0.5).timeout.connect(func():
			if hosting and _peer != null and not peer_player_ids.has(sender) and multiplayer.get_peers().has(sender):
				_peer.disconnect_peer(sender)
		)
		return
	peer_player_ids[sender] = player_id
	_registration_result.rpc_id(sender, true, player_id)
	player_joined.emit(player_id, sender)
	publish_state()

@rpc("authority", "call_remote", "reliable")
func _registration_result(accepted: bool, message: String) -> void:
	if accepted:
		local_player_id = message
		connection_status.emit("Joined the crew. Progress is saved in this world.")
	else:
		connection_status.emit("Join refused: " + message)
		stop_session()

@rpc("authority", "call_remote", "reliable")
func _receive_state(snapshot: Dictionary) -> void:
	latest_snapshot = snapshot
	state_changed.emit(snapshot)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_simulation(snapshot: Dictionary) -> void:
	simulation_received.emit(snapshot)

func submit_input(data: Dictionary) -> void:
	if not is_session_active():
		return
	if hosting:
		_accept_input(1, data)
	else:
		_input_rpc.rpc_id(1, data)

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _input_rpc(data: Dictionary) -> void:
	if hosting:
		_accept_input(multiplayer.get_remote_sender_id(), data)

func _accept_input(peer_id: int, data: Dictionary) -> void:
	if not peer_player_ids.has(peer_id) or data.size() > 20 or not _input_rate_allowed(peer_id):
		return
	var clean: Dictionary = {}
	for key in ["move", "look"]:
		if data.get(key) is Vector2 and data[key].is_finite():
			clean[key] = data[key].limit_length(1.0) if key == "move" else data[key].clamp(Vector2(-180.0, -180.0), Vector2(180.0, 180.0))
	for key in ["move_x", "move_y", "steering", "throttle"]:
		if _finite_number(data.get(key)):
			clean[key] = clampf(float(data[key]), -1.0, 1.0)
	for key in ["yaw", "pitch"]:
		if _finite_number(data.get(key)):
			clean[key] = clampf(float(data[key]), -TAU, TAU)
	for key in ["jump", "sprint", "ascend", "descend", "interact"]:
		if data.get(key) is bool:
			clean[key] = data[key]
	if data.get("sequence") is int:
		clean["sequence"] = data.sequence
	clean["player_id"] = peer_player_ids[peer_id]
	input_received.emit(peer_id, clean)

func _input_rate_allowed(peer_id: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if not _rate_windows.has(peer_id) or now - float(_rate_windows[peer_id].start) >= 1.0:
		_rate_windows[peer_id] = {"start": now, "count": 0}
	_rate_windows[peer_id].count += 1
	return _rate_windows[peer_id].count <= MAX_PACKET_INPUTS_PER_SECOND

func request_cast(recipe: Array, origin: Vector3, direction: Vector3) -> void:
	if not is_session_active():
		return
	if hosting:
		_accept_cast(1, recipe, origin, direction)
	else:
		_cast_rpc.rpc_id(1, recipe, origin, direction)

@rpc("any_peer", "call_remote", "reliable")
func _cast_rpc(recipe: Array, origin: Vector3, direction: Vector3) -> void:
	if hosting:
		_accept_cast(multiplayer.get_remote_sender_id(), recipe, origin, direction)

func _accept_cast(peer_id: int, recipe: Array, origin: Vector3, direction: Vector3) -> void:
	if not peer_player_ids.has(peer_id) or not origin.is_finite() or not direction.is_finite():
		return
	var player_id: String = peer_player_ids[peer_id]
	var player: Dictionary = world.players[player_id]
	if not player.alive or not Catalog.valid_recipe(recipe, player.learned):
		return
	var position := Vector3(float(player.position[0]), float(player.position[1]), float(player.position[2]))
	if position.distance_to(origin) > 4.0 or direction.length_squared() < 0.01 or direction.length_squared() > 4.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_cast.get(player_id, -1000.0)) < 0.28:
		return
	_last_cast[player_id] = now
	cast_requested.emit(player_id, recipe.duplicate(), origin, direction.normalized())

func request_staff_cast(staff_id: String, origin: Vector3, direction: Vector3) -> void:
	if not is_session_active():
		return
	if hosting:
		_accept_staff_cast(1, staff_id, origin, direction)
	else:
		_staff_cast_rpc.rpc_id(1, staff_id, origin, direction)

@rpc("any_peer", "call_remote", "reliable")
func _staff_cast_rpc(staff_id: String, origin: Vector3, direction: Vector3) -> void:
	if hosting:
		_accept_staff_cast(multiplayer.get_remote_sender_id(), staff_id, origin, direction)

func _accept_staff_cast(peer_id: int, staff_id: String, origin: Vector3, direction: Vector3) -> void:
	if not peer_player_ids.has(peer_id) or staff_id.length() > 96 or not origin.is_finite() or not direction.is_finite():
		return
	var player_id: String = peer_player_ids[peer_id]
	var profile: Dictionary = world.staff_cast_profile(player_id, staff_id)
	if not profile.ok:
		return
	var player: Dictionary = world.players[player_id]
	var position := Vector3(float(player.position[0]), float(player.position[1]), float(player.position[2]))
	if position.distance_to(origin) > 4.0 or direction.length_squared() < 0.01 or direction.length_squared() > 4.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_cast.get(player_id, -1000.0)) < 0.28:
		return
	_last_cast[player_id] = now
	staff_cast_requested.emit(player_id, profile.recipe, origin, direction.normalized(), profile)

func request_action(action: String, data: Dictionary = {}) -> void:
	if not is_session_active():
		return
	if hosting:
		_accept_action(1, action, data)
	else:
		_action_rpc.rpc_id(1, action, data)

@rpc("any_peer", "call_remote", "reliable")
func _action_rpc(action: String, data: Dictionary) -> void:
	if hosting:
		_accept_action(multiplayer.get_remote_sender_id(), action, data)

func _accept_action(peer_id: int, action: String, data: Dictionary) -> void:
	if not peer_player_ids.has(peer_id) or data.size() > 8:
		return
	if not ["interact", "helm", "hijack", "loot", "respawn", "buy", "sell", "save_spell", "hearthstone", "claim_cache", "create_crew", "join_crew", "teach_staff"].has(action):
		return
	if action == "save_spell" and (not data.get("recipe") is Array or not data.get("name") is String):
		return
	for value in data.values():
		if value is String:
			if value.length() > 96:
				return
		elif value is Array:
			if value.size() > 8:
				return
			for element in value:
				if not element is String or element.length() > 48:
					return
		elif value is Vector3:
			if not value.is_finite():
				return
		elif value is float or value is int:
			if not _finite_number(value) or absf(float(value)) > 1000000.0:
				return
		elif not value is bool:
			return
	var player_id: String = peer_player_ids[peer_id]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_action.get(player_id, -1000.0)) < 0.1:
		return
	_last_action[player_id] = now
	# Context checks (distance, shop identity, helm availability) belong to host simulation.
	action_requested.emit(player_id, action, data.duplicate(true))

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _exit_tree() -> void:
	stop_session()
