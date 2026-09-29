extends SceneTree
## Save-slot and seed UI tests. All files stay under ignored res://output/performance.

const WorldModel = preload("res://scripts/data/world_state.gd")
const HUD = preload("res://scripts/ui/sea_hud.gd")
const TEST_DIRECTORY := "res://output/performance/seed-slots"

var failures: Array[String] = []
var checks := 0
var save_path := ""
var test_directory := ""

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _find_button(node: Node, caption: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text.contains(caption):
			return child
		var found := _find_button(child,caption)
		if found != null:
			return found
	return null

func _contains_label(node: Node, value: String) -> bool:
	for child in node.get_children():
		if child is Label and child.text.contains(value):
			return true
		if _contains_label(child,value):
			return true
	return false

func _run() -> void:
	var session: Node = root.get_node("Session")
	session.save_enabled = false
	test_directory = TEST_DIRECTORY.path_join("run-" + str(Time.get_ticks_usec()))
	session.save_directory = test_directory
	session._identity_token = Crypto.new().generate_random_bytes(32).hex_encode()
	session.local_player_id = session._identity_token.sha256_text().substr(0,24)
	var hud = HUD.new()
	root.add_child(hud)
	await process_frame
	var requests: Array[Dictionary] = []
	hud.host_requested.connect(func(world_name: String,seed_value: int,wizard_name: String):
		requests.append({"world":world_name,"seed":seed_value,"wizard":wizard_name}))
	hud._seed_input.text = "not a seed"
	hud._request_host("Wayfarer")
	_check(requests.is_empty() and hud.status.text.contains("whole-number"),"Invalid seed is rejected before hosting")
	hud._seed_input.text = "2147483648"
	hud._request_host("Wayfarer")
	_check(requests.is_empty() and hud.status.text.contains("between"),"Out-of-range seed is rejected")
	hud._world_input.text = "  Replicated Sea  "
	hud._seed_input.text = " -42 "
	hud._request_host("Wayfarer")
	_check(requests.size() == 1 and requests[0].world == "Replicated Sea" and requests[0].seed == -42,"Signed seed and trimmed world name reach unchanged host signal")
	var random_button := _find_button(hud.main_menu,"Randomize seed")
	_check(random_button != null,"Randomize seed control exists")
	if random_button != null:
		random_button.pressed.emit()
		_check(hud._parse_seed(hud._seed_input.text).ok,"Randomize creates a valid integer seed")
	var saved_choices := VBoxContainer.new()
	hud.root.add_child(saved_choices)
	hud._add_saved_world_picker(saved_choices,[{"name":"Old Sea","seed":982,"generator_version":1}])
	var continue_button := _find_button(saved_choices,"Continue Old Sea")
	_check(continue_button != null,"Saved-world picker lists seed and version")
	if continue_button != null:
		continue_button.pressed.emit()
		_check(hud._world_input.text == "Old Sea" and hud._seed_input.text == "982","Continue fills the saved name and seed")
	hud._snapshot = {"seed":982,"generator_version":1}
	hud.open_pause()
	_check(_contains_label(hud.modal_body,"SEED · 982 · GENERATOR v1"),"Pause shows active seed and generator version")
	hud.close_panel()
	hud.open_dev([],[],false,true)
	_check(_contains_label(hud.modal_body,"SEED · 982 · GENERATOR v1"),"Developer menu shows active seed and generator version")
	hud.close_panel()
	hud.queue_free()
	await process_frame

	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_directory))
	_check(directory_error == OK,"Isolated test save directory is available")
	if directory_error != OK:
		_finish(session)
		return
	var world_name := "seed-slot-test-" + str(Time.get_ticks_usec())
	save_path = test_directory.path_join(world_name.sha256_text().substr(0,24) + ".json")
	var world = WorldModel.new(world_name,7319,2)
	_check(world.connect_player("seed_player").ok,"Test world has persistent player progress")
	world.players.seed_player.inventory.gold = 77
	_check(world.save_to(save_path) == OK,"Isolated world save succeeds")
	var original_bytes := FileAccess.get_file_as_bytes(save_path)
	var listed: Array[Dictionary] = session.saved_worlds()
	_check(listed.size() == 1 and listed[0].name == world_name and listed[0].seed == 7319 and listed[0].generator_version == 2,"Save picker discovers name, seed, and generator version")
	var mismatch = WorldModel.new(world_name,42)
	var mismatch_result: Dictionary = mismatch.load_from(save_path,42)
	_check(not mismatch_result.ok and mismatch.players.is_empty() and mismatch.seed_value == 42,"Seed mismatch leaves model unmodified")
	var messages: Array[String] = []
	session.connection_status.connect(func(message: String): messages.append(message))
	session.save_enabled = true
	var port := randi_range(25000,35000)
	var mismatch_error: Error = session.start_host(world_name,42,port)
	_check(mismatch_error == ERR_INVALID_DATA and session.world == null and not session.hosting,"Session refuses same-name save with different seed")
	_check(not messages.is_empty() and messages.back().contains("seed 7319"),"Mismatch message identifies the saved seed")
	_check(FileAccess.get_file_as_bytes(save_path) == original_bytes,"Rejected host attempt does not rewrite save")
	var matching_error: Error = session.start_host(world_name,7319,port)
	_check(matching_error == OK and session.world.seed_value == 7319 and session.world.generator_version == 2,"Matching name and seed continue v2 world")
	_check(int(session.world.players.seed_player.inventory.gold) == 77,"Existing progression remains available")
	session.stop_session()
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	legacy.erase("generator_version")
	var file := FileAccess.open(save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var legacy_world = WorldModel.new(world_name,7319)
	_check(legacy_world.load_from(save_path,7319).ok and legacy_world.generator_version == 1,"Legacy save without metadata keeps generator v1")
	legacy["generator_version"] = 999
	file = FileAccess.open(save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var future_world = WorldModel.new(world_name,7319)
	_check(not future_world.load_from(save_path,7319).ok and future_world.players.is_empty(),"Future generator save is rejected without replacement")
	_finish(session)

func _finish(session: Node) -> void:
	session.stop_session()
	if not save_path.is_empty() and FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if not test_directory.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory))
	print("SEED_SLOTS_TEST checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
