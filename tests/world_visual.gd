extends SceneTree
## Standalone rendered integration check of Terrain3D, LOD water, foliage and sky.
const WorldScript=preload("res://scripts/world/archipelago.gd")
const OceanScript=preload("res://scripts/world/ocean.gd")
const SkyScript=preload("res://scripts/world/sky.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene:=Node3D.new()
	root.add_child(scene)
	var camera:=Camera3D.new()
	camera.position=Vector3(30,13,48)
	camera.far=15000
	camera.fov=75
	scene.add_child(camera)
	camera.look_at(Vector3(-25,17,-75))
	camera.current=true
	var sky=SkyScript.new()
	scene.add_child(sky)
	var world=WorldScript.new()
	scene.add_child(world)
	world.build()
	var ocean=OceanScript.new()
	scene.add_child(ocean)
	ocean.set_shore_data(world.shore_texture,world.MAP_ORIGIN,Vector2.ONE*world.MAP_SIZE)
	ocean.set_simulation_time(16.4)
	for frame in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.dream-loop/world-visual.png")
	print("WORLD_SCREENSHOT=.dream-loop/world-visual.png")
	print("WORLD_FPS=",Engine.get_frames_per_second())
	print("PROCESS_MS=",Performance.get_monitor(Performance.TIME_PROCESS)*1000)
	print("PHYSICS_MS=",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
	print("DRAW_CALLS=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("PRIMITIVES=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	quit()
