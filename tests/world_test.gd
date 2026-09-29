extends SceneTree

const OceanScript=preload("res://scripts/world/ocean.gd")
const WorldScript=preload("res://scripts/world/archipelago.gd")
const DungeonLayout=preload("res://scripts/world/dungeon_layout.gd")
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
	# Preserve the original authored world contract for pre-v2 saved games.
	world.configure(7319,1)
	var started:=Time.get_ticks_msec()
	world.build()
	print("WORLD_GENERATION_MS=",Time.get_ticks_msec()-started)
	var legacy_count := 0
	for island in world.island_records:
		if not island.get("procedural",false):
			legacy_count += 1
	check(legacy_count==9,"Legacy island manifest changed")
	check(world.waterfall_volumes.size()>=3,"Every legacy sky island requires a waterfall")
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
		check(world._path_overlay_nodes.has(island.id),"Visible route overlay missing on "+island.id)
		for path in island.paths:
			for i in range(path.size()-1):
				var a:Vector3=path[i]
				var b:Vector3=path[i+1]
				var distance_value:=Vector2(a.x-b.x,a.z-b.z).length()
				if distance_value>0.3:
					check(absf(a.y-b.y)/distance_value<=0.71,"Route grade too steep on "+island.id)
	var harbour: Dictionary = world.island_records[0]
	var original: PackedVector3Array = harbour.paths[0].duplicate()
	var middle := int(original.size()/2)
	var block_site: Vector3 = original[middle]
	var first_revision: int = world.navigation_graphs[harbour.id].revision
	check(world.set_path_obstruction(harbour.id,block_site,2.0,true),"Walkable POI route failed to reroute around local obstruction")
	check(world.navigation_graphs[harbour.id].revision==first_revision+1,"Route revision did not advance")
	check(harbour.paths.size()>=harbour.pois.size()-1,"Live obstruction disconnected POIs")
	for path in harbour.paths:
		check(world._path_is_safe(path,world.navigation_graphs[harbour.id].blocked),"Live path crosses obstruction or unsafe grade")
	check(not world.route_is_clear(harbour.id,block_site+Vector3.LEFT*4,block_site+Vector3.RIGHT*4),"Dynamic path obstruction not registered")
	var before_rejection: PackedVector3Array = harbour.paths[0].duplicate()
	check(not world.set_path_obstruction(harbour.id,harbour.pois[0].position,30.0,true),"Unreachable POI obstruction should be rejected")
	check(harbour.paths[0]==before_rejection,"Rejected obstruction changed reachable route")
	check(world.set_path_obstruction(harbour.id,block_site,2.0,false),"Removing local obstruction failed")
	check(world.route_is_clear(harbour.id,block_site+Vector3.LEFT*4,block_site+Vector3.RIGHT*4),"Removed path obstruction remains blocked")
	check(world.dungeons.size()>=5,"Expected all legacy surface dungeons")
	var legacy_far: Dictionary = {}
	for sector_x in range(8,18):
		legacy_far=world.sector_manifest(sector_x,0)
		if not legacy_far.is_empty() and not legacy_far.sky:
			break
	check(not legacy_far.is_empty(),"Legacy save cannot discover new outer islands")
	if not legacy_far.is_empty():
		var legacy_additions: Dictionary = world.ensure_at(legacy_far.center)
		check(legacy_additions.added_islands.size()==1 and world.sample_ground_height(legacy_far.center.x,legacy_far.center.z)>0.0,"Legacy outer island has no usable ground")
	var root_layout: Dictionary = world.get_dungeon("rootwatch/dungeon")
	for dungeon_id in world.dungeons:
		var layout: Dictionary = world.dungeons[dungeon_id]
		check(layout.rooms.size()>=5,"Dungeon has too few rooms: "+dungeon_id)
		check(layout.extra_edges>=1,"Dungeon room graph has no loop: "+dungeon_id)
		check(layout.reachable_tiles==layout.open_cells.size(),"Dungeon has disconnected floor cells: "+dungeon_id)
		check(not world.dungeon_route(dungeon_id,layout.start_position,layout.reward_position).is_empty(),"Dungeon reward unreachable: "+dungeon_id)
		check(world.dungeon_at(layout.start_position)==dungeon_id,"Dungeon lookup failed: "+dungeon_id)
		check(absf(world.sample_surface_at(layout.start_position)-layout.floor_y)<0.01,"Interior floor sampling failed: "+dungeon_id)
	var replay: Dictionary = DungeonLayout.generate(7319,"rootwatch/dungeon",8,root_layout.origin,root_layout.biome)
	check(replay.open_cells==root_layout.open_cells,"Dungeon layout is not deterministic")
	var built_dungeon: Node3D = world.ensure_dungeon_built("rootwatch/dungeon")
	check(built_dungeon!=null,"Dungeon geometry did not build")
	await physics_frame
	if built_dungeon:
		var floor_ray := PhysicsRayQueryParameters3D.create(root_layout.start_position+Vector3.UP*2,root_layout.start_position-Vector3.UP*3)
		var floor_hit := world.get_world_3d().direct_space_state.intersect_ray(floor_ray)
		check(not floor_hit.is_empty(),"Dungeon floor has no collision")
		if not floor_hit.is_empty():
			check(floor_hit.normal.y>0.7,"Dungeon floor collision faces down")
	if world.terrain:
		print("TERRAIN_NATIVE_CLASS=",world.terrain.get_class())
		print("TERRAIN_REGIONS=",world.terrain.get("data").call("get_regions_active").size())
	print("WORLD_TEST_FAILURES=",failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
