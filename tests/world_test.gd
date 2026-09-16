extends SceneTree

const OceanScript=preload("res://scripts/world/ocean.gd")
const WorldScript=preload("res://scripts/world/archipelago.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var ocean=OceanScript.new()
	# Validate inversion against forward-displaced wave samples, not a mirrored
	# scalar height formula: this catches wrong world XZ buoyancy queries.
	for time in [0.0,17.8,132.6]:
		for index in 70:
			var q:=Vector2(index*1.78-50.0,index*-2.31+28.0)
			var displacement: Vector3=ocean._displacement(q,time)
			var actual:=Vector3(q.x+displacement.x,0,q.y+displacement.z)
			check(absf(ocean.sample_height(actual,time)-displacement.y)<0.001,"Inverse wave surface disagrees with rendered displacement")
			check(absf(ocean.sample_normal(actual,time).length()-1.0)<0.001,"Water normal is not normalized")
	ocean.free()
	check(ClassDB.class_exists("Terrain3D"),"Terrain3D native extension did not load")
	var world=WorldScript.new()
	root.add_child(world)
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(0,6,0)
	camera.current=true
	world.configure(7319)
	var started:=Time.get_ticks_msec()
	world.build()
	print("WORLD_GENERATION_MS=",Time.get_ticks_msec()-started)
	check(world.island_records.size()==9,"Unexpected world manifest count")
	check(world.waterfall_volumes.size()==3,"Every sky island requires a waterfall")
	check(world.is_safe_zone(world.get_spawn_position()),"Starter spawn must be protected")
	check(not world.is_safe_zone(Vector3(260,0,-100)),"Open sea cannot be protected")
	for waterfall in world.waterfall_volumes:
		check(waterfall.bottom<=0.0,"Waterfall must reach accessible ocean approach")
		check(not world.waterfall_at(waterfall.center).is_empty(),"Waterfall collision volume gap")
		check(waterfall.exit.y>=waterfall.top-2.5,"Waterfall exit below upper island")
	for frame in 3:
		await physics_frame
	for waterfall in world.waterfall_volumes:
		var exit_point: Vector3=waterfall.exit
		var query:=PhysicsRayQueryParameters3D.create(exit_point+Vector3.UP*8,exit_point-Vector3.UP*8)
		var hit:=world.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(),"Sky waterfall exit must have actual physics support: "+waterfall.island_id)
		if not hit.is_empty():
			check(hit.normal.y>0.70,"Sky exit floor must face up: "+waterfall.island_id)
	for island in world.island_records:
		check(island.paths.size()>=island.pois.size()-1,"POI graph is disconnected")
		for path in island.paths:
			for i in range(path.size()-1):
				var a:Vector3=path[i]
				var b:Vector3=path[i+1]
				var distance_value:=Vector2(a.x-b.x,a.z-b.z).length()
				if distance_value>0.3:
					check(absf(a.y-b.y)/distance_value<=0.71,"Route grade too steep on "+island.id)
	world.set_path_obstruction("hearthharbour",Vector3(-40,8,-47),3.0,true)
	check(not world.route_is_clear("hearthharbour",Vector3(-45,8,-47),Vector3(-35,8,-47)),"Dynamic path obstruction not registered")
	world.set_path_obstruction("hearthharbour",Vector3(-40,8,-47),3.0,false)
	check(world.route_is_clear("hearthharbour",Vector3(-45,8,-47),Vector3(-35,8,-47)),"Removed path obstruction remains blocked")
	if world.terrain:
		print("TERRAIN_NATIVE_CLASS=",world.terrain.get_class())
		print("TERRAIN_REGIONS=",world.terrain.get("data").call("get_regions_active").size())
	print("WORLD_TEST_FAILURES=",failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
