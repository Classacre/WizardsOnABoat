extends SceneTree
## Rendered, save-free smoke for deferred projectile prewarm followed by --quickstart hosting.

const OUTPUT := "res://output/performance/quickstart-smoke.png"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var session: Variant = root.get_node("Session")
	session.save_enabled = false
	session.identity_profile = "performance_quickstart"
	session._identity_token = Crypto.new().generate_random_bytes(32).hex_encode()
	session.local_player_id = session._identity_token.sha256_text().substr(0, 24)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var frames := 0
	while frames < 180 and not (game._projectile_prewarmed and session.hosting and game.in_game):
		await process_frame
		frames += 1
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var warmup_nodes := 0
	for child in game.preview_camera.get_children():
		if child is MeshInstance3D:
			warmup_nodes += 1
	var image_error := root.get_texture().get_image().save_png(OUTPUT)
	var result := {
		"prewarmed": game._projectile_prewarmed,
		"hosting": session.hosting,
		"in_game": game.in_game,
		"local_wizard": game.local_wizard != null,
		"boats": game.boats.size(),
		"warmup_nodes_left": warmup_nodes,
		"screenshot_error": image_error,
		"frames_until_ready": frames,
	}
	var passed: bool = result.prewarmed and result.hosting and result.in_game and result.local_wizard and result.boats > 0 and warmup_nodes == 0 and image_error == OK
	print("PERF_QUICKSTART ", JSON.stringify(result), " passed=", passed)
	session.stop_session()
	quit(0 if passed else 1)
