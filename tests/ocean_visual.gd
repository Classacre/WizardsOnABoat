extends SceneTree
## Render-only review at several world coordinates; never opens a player save.

const OUTPUT := "res://output/procedural/"
var output := OUTPUT

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--water-output="): output=arg.trim_prefix("--water-output=").trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output+".gdignore",FileAccess.WRITE).close()
	var scene := Node3D.new()
	root.add_child(scene)
	var sky = load("res://scripts/world/sky.gd").new()
	scene.add_child(sky)
	var ocean = load("res://scripts/world/ocean.gd").new()
	ocean.configure(948321)
	scene.add_child(ocean)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current=true
	camera.far=2200.0
	camera.fov=65.0
	var mismatched_tiles := 0
	var mesh_count := 0
	for child in ocean.get_children():
		if child is MeshInstance3D:
			mesh_count+=1
			var material := child.get_surface_override_material(0) as ShaderMaterial
			if material != ocean.water_material or material == null or material.shader.resource_path != "res://shaders/ocean.gdshader":
				mismatched_tiles+=1
	var report := {"shader_path":ocean.water_material.shader.resource_path,"shader_code_hash":ocean.water_material.shader.code.hash(),"water_meshes":mesh_count,"mismatched_materials":mismatched_tiles,"wave_components":ocean._waves.size(),"viewport":str(root.size)}
	report["gpu"]=RenderingServer.get_video_adapter_name()
	print("OCEAN_SHADER_LOADED ",JSON.stringify(report))
	var frames := [
		{"name":"ocean-near","position":Vector3(10,5,30),"time":12.3},
		{"name":"ocean-sea-level","position":Vector3(10,2.4,30),"time":12.3},
		{"name":"ocean-overview","position":Vector3(10,60,30),"time":12.3,"look":Vector3(10,-50,-70)},
		{"name":"ocean-far","position":Vector3(7400,5,-2400),"time":12.3},
		{"name":"ocean-later","position":Vector3(7400,5,-2400),"time":29.8},
	]
	for shot in frames:
		camera.position=shot.position
		camera.look_at(camera.position+shot.get("look",Vector3(10,-4,-70)))
		ocean.set_simulation_time(shot.time)
		for frame in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+str(shot.name)+".png")
	var gaps: Array[float] = []
	var previous := 0
	var began := Time.get_ticks_usec()
	for frame in 480:
		ocean.set_simulation_time(30.0+float(Time.get_ticks_usec()-began)/1000000.0)
		await process_frame
		var now := Time.get_ticks_usec()
		if previous>0: gaps.append(float(now-previous)/1000.0)
		previous=now
	gaps.sort()
	report["animated_frame_gaps_ms"]={"samples":gaps.size(),"median":gaps[int(gaps.size()*0.5)],"p95":gaps[int(gaps.size()*0.95)],"max":gaps.back()}
	FileAccess.open(output+"render-check.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("OCEAN_VISUAL_CAPTURED=",frames.size()," ",JSON.stringify(report))
	quit(0 if mismatched_tiles==0 else 1)
