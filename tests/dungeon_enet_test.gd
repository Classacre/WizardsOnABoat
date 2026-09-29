extends SceneTree
## Two headless, full-main peers. Start the host first, then the client after
## the host prints its listening-port PASS; both need the same --dungeon-port.
## Godot: --headless --path . --script res://tests/dungeon_enet_test.gd --
##        --dungeon-host --dungeon-port=24731   (omit --dungeon-host for client)
## Add --procedural-world to both peers for a far generator-v2 island and reconnect.
## Both peers use disposable in-memory identities and never read or write saves.

const LEGACY_DUNGEON_ID := "rootwatch/dungeon"
const LEGACY_WORLD_ID := "dungeon-enet-disposable"
const LEGACY_SEED := 7319
const PROCEDURAL_WORLD_ID := "procedural-enet-disposable"
const PROCEDURAL_SEED := 948321

var game: Node3D
var session: Node
var is_host := false
var procedural_world := false
var port := 24731
var failures: Array[String] = []
var checks := 0
var started_ms := Time.get_ticks_msec()
var finished := false
var remote_id := ""
var actions: Dictionary = {}
var dungeon_id := LEGACY_DUNGEON_ID
var manifest: Dictionary = {}

func _initialize() -> void:
	Engine.max_fps = 60
	for arg in OS.get_cmdline_user_args():
		if arg == "--dungeon-host": is_host = true
		if arg == "--procedural-world": procedural_world = true
		if arg.begins_with("--dungeon-port="): port = int(arg.trim_prefix("--dungeon-port="))
	call_deferred("_begin")

func _process(_delta: float) -> bool:
	var timeout_ms := 120000 if procedural_world else 90000
	if not finished and Time.get_ticks_msec() - started_ms > timeout_ms:
		_check(false,"Timed out after %d seconds" % int(timeout_ms/1000))
		_finish()
	return false

func _check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + ("HOST " if is_host else "CLIENT ") + message)
	if not condition:
		failures.append(message)

func _begin() -> void:
	session = root.get_node("Session")
	session.save_enabled = false
	session.identity_profile = "dungeon_enet_disposable"
	session._identity_token = Crypto.new().generate_random_bytes(32).hex_encode()
	session.local_player_id = session._identity_token.sha256_text().substr(0,24)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	if not game.has_method("_host"):
		_check(false,"Main scene script did not compile")
		_finish()
		return
	if is_host:
		await _run_host()
	else:
		await _run_client()
	_finish()

func _wait_for(predicate: Callable, timeout_ms := 12000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return false

func _player_position(snapshot: Dictionary, id: String) -> Vector3:
	var players: Dictionary = snapshot.get("players",{})
	if not players.has(id): return Vector3.INF
	var coordinates: Array = players[id].get("position",[])
	if coordinates.size() != 3: return Vector3.INF
	return Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))

func _my_position() -> Vector3:
	return _player_position(session.latest_snapshot,session.local_player_id)

func _at(position: Vector3, target: Vector3, radius: float) -> bool:
	return position.is_finite() and position.distance_to(target) <= radius

func _select_far_manifest() -> Dictionary:
	for sector_x in range(7,18):
		for sector_z in range(-3,4):
			var candidate: Dictionary = game.archipelago.sector_manifest(sector_x,sector_z)
			if not candidate.is_empty() and not candidate.sky and candidate.center.length() > 3000.0:
				return candidate
	return {}

func _configure_dungeon() -> bool:
	if not procedural_world:
		return true
	manifest = _select_far_manifest()
	_check(not manifest.is_empty(),"Seed independently selects a ground island beyond 3 km")
	if manifest.is_empty(): return false
	dungeon_id = str(manifest.id) + "/dungeon"
	return true

func _has_far_surface() -> bool:
	for island in game.archipelago.island_records:
		if str(island.id) == str(manifest.id):
			return island.get("procedural",false) and island.center.is_equal_approx(manifest.center)
	return false

func _has_far_collision(entrance: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(entrance+Vector3.UP*12.0,entrance+Vector3.DOWN*15.0,1)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and absf(float(hit.position.y)-game.archipelago.sample_surface_at(entrance)) < 5.0

func _remote_action(_player_id: String, action: String, data: Dictionary) -> void:
	if action == "interact":
		var kind := str(data.get("kind",""))
		actions[kind] = int(actions.get(kind,0)) + 1
		print("DUNGEON_ENET_HOST received action kind=",kind," count=",actions[kind])

func _place_remote(position: Vector3) -> void:
	var wizard: CharacterBody3D = game.wizards[remote_id]
	wizard.global_position = position
	wizard.velocity = Vector3.ZERO
	session.world.update_player_position(remote_id,position,false)
	session.publish_state()
	game._broadcast_simulation()

func _run_host() -> void:
	session.display_name = "Dungeon Host"
	var seed_value := PROCEDURAL_SEED if procedural_world else LEGACY_SEED
	var version := 2 if procedural_world else 1
	var world_id := PROCEDURAL_WORLD_ID if procedural_world else LEGACY_WORLD_ID
	var error: Error = session.start_host(world_id,seed_value,port,version)
	_check(error == OK,"Host starts on isolated UDP port %d" % port)
	if error != OK: return
	_check(session.world.seed_value == seed_value and game.archipelago.world_seed == seed_value and session.world.generator_version == version and game.archipelago.generator_version == version,"Host and scene use the requested seed and generator version")
	if not _configure_dungeon(): return
	# Mirror Main._host's world setup while preserving the custom test port.
	for player_id in session.world.players:
		var record: Dictionary = session.world.players[player_id]
		if Vector3(record.position[0],record.position[1],record.position[2]).length() < 3.0:
			session.world.update_player_position(player_id,game._safe_spawn(),true)
	for ship_id in session.world.ships:
		var ship: Dictionary = session.world.ships[ship_id]
		if not ship.has("runtime_placed"):
			var berth: Vector3 = game._berth_position(session.world.ships.keys().find(ship_id))
			session.world.update_ship_position(ship_id,berth,true)
			if game.boats.has(ship_id): game.boats[ship_id].position = berth
			ship["runtime_placed"] = true
	session.publish_state()
	game.creature_manager.seed_world(session.world)
	game._enter_game()
	session.action_requested.connect(_remote_action)
	if not await _wait_for(func(): return session.world.online_count() == 2 and game.wizards.size() == 2,30000):
		_check(false,"Remote wizard joins and is instantiated")
		return
	for id in session.world.players:
		if id != session.local_player_id: remote_id = id
	_check(not remote_id.is_empty(),"Remote player identity is registered")
	if remote_id.is_empty(): return
	if not await _wait_for(func(): return int(actions.get("dungeon",0)) >= 1):
		_check(false,"Remote outside entry request arrives")
		return
	for frame in 15: await process_frame
	_check(game.archipelago.dungeon_at(game.wizards[remote_id].global_position).is_empty(),"Host rejects remote dungeon entry from outside")
	if procedural_world:
		game._ensure_surface_for_position(manifest.center)
		_check(_has_far_surface(),"Host loads the independently derived far island")
		if not _has_far_surface(): return
	var dungeon: Dictionary = game.archipelago.get_dungeon(dungeon_id)
	_check(not dungeon.is_empty(),"Dungeon descriptor exists")
	if dungeon.is_empty(): return
	var entrance := Vector3.INF
	for poi in game.interactables:
		if poi.kind == "dungeon" and poi.id == dungeon_id: entrance = poi.position
	_check(entrance.is_finite(),"Exterior entrance exists")
	if not entrance.is_finite(): return
	_place_remote(entrance)
	if not await _wait_for(func(): return int(actions.get("dungeon",0)) >= 2 and game.archipelago.dungeon_at(game.wizards[remote_id].global_position) == dungeon_id):
		_check(false,"Remote legitimate entrance is accepted")
		return
	_check(game.archipelago._dungeon_nodes.has(dungeon_id) and is_instance_valid(game.archipelago._dungeon_nodes[dungeon_id]),"Host built physical dungeon before entry")
	var coins_before := int(session.world.players[remote_id].inventory.get("ancient_coin",0))
	if not await _wait_for(func(): return int(actions.get("dungeon_reward",0)) >= 1):
		_check(false,"Remote premature reward request arrives")
		return
	_check(int(session.world.players[remote_id].inventory.get("ancient_coin",0)) == coins_before,"Host rejects reward away from reliquary")
	_place_remote(dungeon.reward_position)
	if not await _wait_for(func(): return int(actions.get("dungeon_reward",0)) >= 2 and session.world.players[remote_id].claimed_caches.has(dungeon_id)):
		_check(false,"Remote reward request grants persistent cache")
		return
	_check(int(session.world.players[remote_id].inventory.get("ancient_coin",0)) == coins_before + 3,"Remote reward grants exactly three coins")
	_place_remote(dungeon.exit_position)
	if not await _wait_for(func(): return int(actions.get("dungeon_exit",0)) >= 1 and _at(game.wizards[remote_id].global_position,dungeon.return_position,2.0)):
		_check(false,"Remote exit returns to island")
		return
	_check(game.archipelago.dungeon_at(game.wizards[remote_id].global_position).is_empty(),"Host remote wizard is outside after exit")
	_check(session.world.invariant_errors().is_empty(),"Host world invariants hold")
	if procedural_world:
		if not await _wait_for(func(): return session.world.online_count() == 1,20000):
			_check(false,"Client disconnect reaches host")
			return
		if not await _wait_for(func(): return session.world.online_count() == 2 and game.wizards.has(remote_id),30000):
			_check(false,"Same client identity reconnects")
			return
		_check(session.world.players[remote_id].claimed_caches.has(dungeon_id) and int(session.world.players[remote_id].inventory.get("ancient_coin",0)) == coins_before + 3,"Host preserves far-dungeon reward across reconnect")
		_check(_at(_player_position(session.world.snapshot(),remote_id),dungeon.return_position,3.0),"Host restores remote wizard on the far island")
	# The procedural client closes only after checking its restored snapshot.
	# Waiting for that clean disconnect keeps the host alive through reconnect.
	if procedural_world:
		if not await _wait_for(func(): return session.world.online_count() == 1,20000):
			_check(false,"Client did not complete the restored snapshot check")
	else:
		if not await _wait_for(func(): return int(actions.get("compass",0)) >= 1):
			_check(false,"Client did not acknowledge the island return snapshot")

func _run_client() -> void:
	session.display_name = "Dungeon Client"
	var error: Error = session.join_host("127.0.0.1",port)
	_check(error == OK,"Client starts isolated connection")
	if error != OK: return
	if not await _wait_for(func(): return session.latest_snapshot.get("players",{}).has(session.local_player_id) and game.local_wizard != null,30000):
		_check(false,"Client receives its wizard and first snapshot")
		return
	var expected_seed := PROCEDURAL_SEED if procedural_world else LEGACY_SEED
	var expected_version := 2 if procedural_world else 1
	_check(int(session.latest_snapshot.get("seed",-1)) == expected_seed and int(session.latest_snapshot.get("generator_version",-1)) == expected_version and game.archipelago.world_seed == expected_seed and game.archipelago.generator_version == expected_version,"Client rebuilds the host seed and generator version")
	if not _configure_dungeon(): return
	if not procedural_world:
		_check(not game.archipelago.get_dungeon(dungeon_id).is_empty(),"Client dungeon descriptor exists")
	var before: Vector3 = game.local_wizard.global_position
	var loot_count: int = session.latest_snapshot.get("loot",{}).size()
	game._dev_action("teleport",{"id":"dungeon/"+dungeon_id})
	game._dev_action("spawn",{"id":"chest/salvage"})
	_check(game.local_wizard.global_position == before and session.latest_snapshot.get("loot",{}).size() == loot_count,"Client developer actions have no local effect")
	if not await _wait_for(func(): return session.is_session_active()):
		_check(false,"Client transport is connected before the first action")
		return
	await create_timer(0.25).timeout
	print("DUNGEON_ENET_CLIENT sending outside entry peer=",session.local_player_id," dungeon=",dungeon_id)
	session.request_action("interact",{"kind":"dungeon","id":dungeon_id})
	if not await _wait_for(func(): return not game.archipelago.get_dungeon(dungeon_id).is_empty()):
		_check(false,"Client receives the dungeon descriptor before entry")
		return
	var dungeon: Dictionary = game.archipelago.get_dungeon(dungeon_id)
	if not await _wait_for(func(): return _at(_my_position(),dungeon.entrance_position,6.0)):
		_check(false,"Host stages remote wizard at exterior entrance")
		return
	if procedural_world:
		_check(_has_far_surface(),"Client streams the same far island before actor arrival")
		_check(game._poi_nodes.has(dungeon_id),"Client registers the far dungeon POI before entry")
		await physics_frame
		_check(_has_far_collision(dungeon.entrance_position),"Client has physical far-island collision before entry")
	await create_timer(0.2).timeout
	session.request_action("interact",{"kind":"dungeon","id":dungeon_id})
	if not await _wait_for(func(): return game.archipelago.dungeon_at(_my_position()) == dungeon_id):
		_check(false,"Client receives interior position after accepted entry")
		return
	# Main._receive_state builds interiors before actor sync, so geometry is present on arrival.
	_check(game.archipelago._dungeon_nodes.has(dungeon_id) and is_instance_valid(game.archipelago._dungeon_nodes[dungeon_id]),"Client interior geometry exists on arrival")
	await create_timer(0.2).timeout
	session.request_action("interact",{"kind":"dungeon_reward","id":dungeon_id})
	if not await _wait_for(func(): return _at(_my_position(),dungeon.reward_position,2.0)):
		_check(false,"Client receives reliquary staging position")
		return
	await create_timer(0.2).timeout
	session.request_action("interact",{"kind":"dungeon_reward","id":dungeon_id})
	if not await _wait_for(func(): return session.latest_snapshot.players[session.local_player_id].claimed_caches.has(dungeon_id)):
		_check(false,"Client receives persistent reward snapshot")
		return
	if not await _wait_for(func(): return _at(_my_position(),dungeon.exit_position,2.0)):
		_check(false,"Client receives exit staging position")
		return
	await create_timer(0.2).timeout
	session.request_action("interact",{"kind":"dungeon_exit","id":dungeon_id})
	if not await _wait_for(func(): return _at(_my_position(),dungeon.return_position,2.0)):
		_check(false,"Client receives island return position")
		return
	_check(game.archipelago.dungeon_at(_my_position()).is_empty(),"Client sees remote-authoritative exit")
	if procedural_world:
		var original_id: String = session.local_player_id
		var coins_after := int(session.latest_snapshot.players[original_id].inventory.get("ancient_coin",0))
		session.stop_session()
		await create_timer(0.4).timeout
		var reconnect_error: Error = session.join_host("127.0.0.1",port)
		_check(reconnect_error == OK,"Client reconnects on the same isolated port")
		if reconnect_error != OK: return
		if not await _wait_for(func(): return session.is_session_active() and session.latest_snapshot.get("players",{}).has(original_id) and session.latest_snapshot.players[original_id].get("online",false),30000):
			_check(false,"Client receives its restored player after reconnect")
			return
		_check(session.local_player_id == original_id and session.latest_snapshot.players[original_id].claimed_caches.has(dungeon_id) and int(session.latest_snapshot.players[original_id].inventory.get("ancient_coin",0)) == coins_after,"Same in-memory identity retains the one-time reward")
		_check(_at(_my_position(),dungeon.return_position,3.0) and _has_far_surface(),"Client returns to the same physical far island")
	if not procedural_world:
		await create_timer(0.25).timeout
		session.request_action("interact",{"kind":"compass"})
		await create_timer(0.5).timeout

func _finish() -> void:
	if finished: return
	finished = true
	print("DUNGEON_ENET_%s checks=%d failures=%d" % ["HOST" if is_host else "CLIENT",checks,failures.size()])
	if session != null: session.stop_session()
	quit(0 if failures.is_empty() else 1)
