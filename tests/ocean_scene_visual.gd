extends SceneTree
## Real harbour, hull and shore materials; uses the menu scene without hosting or saves.

const OUTPUT := "res://output/water-review/scene/"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("Session").save_enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE).close()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.hud.hide()
	game.ocean.set_simulation_time(12.3)
	var boat: Node3D = game.preview_boat
	for frame in 120:
		boat.simulate(1.0/60.0)
	var camera: Camera3D = game.preview_camera
	camera.fov = 65.0
	var shots := [
		{"name":"harbour", "position":Vector3(105,32,105), "target":Vector3(0,4,0)},
		{"name":"hull-and-wake", "position":boat.position+Vector3(18,9,23), "target":boat.position+Vector3(0,1,4)},
	]
	var failures := 0
	for shot in shots:
		camera.position = shot.position
		camera.look_at(shot.target)
		game.ocean.set_ship_wakes([Vector4(boat.position.x,boat.position.z,boat.heading,7.0)])
		for frame in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(OUTPUT+shot.name+".png")
		if error != OK: failures += 1
		print("OCEAN_SCENE_CAPTURE ",shot.name," error=",error)
	print("OCEAN_SCENE_VISUAL failures=",failures," shader=",game.ocean.water_material.shader.code.hash())
	quit(0 if failures == 0 else 1)
