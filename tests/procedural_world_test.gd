extends SceneTree

const WorldScript = preload("res://scripts/world/archipelago.gd")
const IslandGenerator = preload("res://scripts/world/island_generator.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current=true
	var world: Node3D = WorldScript.new()
	root.add_child(world)
	world.configure(7319,2)
	world.build()
	check(world.generator_version==2,"New generation version was not selected")
	check(world.island_records[0].id=="hearthharbour","Authored starter moved")
	check(world.is_safe_zone(world.get_spawn_position()),"Starter safety changed")
	var biome_set: Dictionary = {}
	var manifest_count := 0
	var sky_count := 0
	var min_radius := INF
	var max_radius := 0.0
	for sx in range(-7,8):
		for sz in range(-7,8):
			var manifest: Dictionary = world.sector_manifest(sx,sz)
			if manifest.is_empty():
				continue
			manifest_count += 1
			sky_count += int(manifest.sky)
			biome_set[manifest.biome]=true
			min_radius=minf(min_radius,manifest.radius)
			max_radius=maxf(max_radius,manifest.radius)
			check(Vector2(manifest.center.x+72.0,manifest.center.z+77.0).length()>=260.0,"Procedural island overlaps protected starter")
	check(manifest_count>100 and sky_count>8 and biome_set.size()>=5 and max_radius-min_radius>30.0,"Seeded sectors lack density or visible biome/size diversity")
	var phase_times: Array[int] = []
	var phase_peaks: Dictionary = {}
	var streamed_count := 0
	for iteration in 300:
		var phase_name: String = str(world._pending_stream.get("phase","scan"))
		var phase_start := Time.get_ticks_msec()
		var phase_diff: Dictionary = world.advance_stream() if world.has_pending_stream() else world.stream_around([world.get_spawn_position()],1)
		var elapsed := Time.get_ticks_msec()-phase_start
		phase_times.append(elapsed)
		phase_peaks[phase_name]=maxi(int(phase_peaks.get(phase_name,0)),elapsed)
		if elapsed>30:
			print("PROCEDURAL_SLOW_PHASE=",phase_name," MS=",elapsed," ISLAND=",str(world._pending_stream.get("island",{}).get("id","completed")))
		streamed_count += phase_diff.added_islands.size()
		if not world.has_pending_stream() and phase_diff.added_islands.is_empty() and iteration>5:
			break
	phase_times.sort()
	check(not world.has_pending_stream(),"Staged starter-near streaming did not finish")
	check(streamed_count>=1,"Staged streaming never activated a nearby island")
	if not phase_times.is_empty():
		print("PROCEDURAL_STAGE_MS_MEDIAN=",phase_times[int(phase_times.size()/2)]," MAX=",phase_times[-1]," PEAKS=",phase_peaks)
	var starter: Dictionary = world.island_records[0]
	var starter_height: float = world._local_height(starter,starter.center.x+12.0,starter.center.z-5.0)
	var first: Dictionary = {}
	var far_samples: Array[Dictionary] = []
	for sx in range(8,18):
		for sz in range(-2,3):
			var candidate: Dictionary = world.sector_manifest(sx,sz)
			if not candidate.is_empty() and not candidate.sky:
				far_samples.append(candidate)
				if first.is_empty():
					first=candidate
		if far_samples.size()>=3:
			break
	check(not first.is_empty(),"No procedural surface island exists beyond 3 km")
	var load_times: Array[int] = []
	if not first.is_empty():
		var again: Dictionary = world.sector_manifest(first.sector.x,first.sector.y)
		check(first.center==again.center and first.radius==again.radius and first.biome==again.biome,"Sector manifest is not reproducible")
		var load_start := Time.get_ticks_msec()
		var changes: Dictionary = world.ensure_at(first.center)
		load_times.append(Time.get_ticks_msec()-load_start)
		check(changes.added_islands.size()==1 and changes.added_pois.size()>=2,"Far island did not stream its POIs")
		check(world.sample_ground_height(first.center.x,first.center.z)>5.0,"Far island has no land height")
		await physics_frame
		await physics_frame
		var from: Vector3 = first.center+Vector3.UP*80.0
		var to: Vector3 = first.center+Vector3.DOWN*45.0
		var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to))
		check(not hit.is_empty(),"Far island has no physical collision")
		if not hit.is_empty():
			check(hit.normal.y>0.6,"Far island collision is not walkable")
			check(absf(hit.position.y-world.sample_ground_height(first.center.x,first.center.z))<1.5,"Far island visual/collision height diverged")
		var island: Dictionary = changes.added_islands[0]
		check(island.paths.size()>=island.pois.size()-1,"Generated POIs are disconnected")
		for path in island.paths:
			for index in range(0,path.size(),maxi(1,int(path.size()/8))):
				var waypoint: Vector3 = path[index]
				var query := PhysicsRayQueryParameters3D.create(waypoint+Vector3.UP*8,waypoint-Vector3.UP*8)
				var support := world.get_world_3d().direct_space_state.intersect_ray(query)
				check(not support.is_empty(),"Procedural road waypoint lacks physical support")
				if not support.is_empty():
					check(support.normal.y>0.45 and absf(support.position.y-world.sample_ground_height(waypoint.x,waypoint.z))<1.5,"Procedural road collision diverged from sampled ground")
		var dungeon_id := str(island.id)+"/dungeon"
		var layout: Dictionary = world.get_dungeon(dungeon_id)
		check(not layout.is_empty() and layout.reachable_tiles==layout.open_cells.size(),"Far dungeon layout disconnected")
		var unloaded: Dictionary = world.stream_around([world.get_spawn_position()],0)
		check(unloaded.removed_island_ids.has(str(island.id)),"Far island did not unload")
		check(not world.navigation_graphs.has(island.id) and not world.dungeons.has(dungeon_id),"Unloaded island retained navigation/dungeon data")
		var reconnect: Dictionary = world.ensure_at(layout.start_position)
		check(reconnect.added_islands.size()==1,"Far interior reconnect did not rebuild source island")
		check(world.dungeon_at(layout.start_position)==dungeon_id,"Far interior reconnect failed dungeon lookup")
		check(world.ensure_dungeon_built(dungeon_id)!=null,"Far interior reconnect has no collision geometry")
		await physics_frame
		var return_route: PackedVector3Array = world.dungeon_route(dungeon_id,layout.reward_position,layout.start_position)
		check(not return_route.is_empty(),"Far dungeon has no walkable reward-to-exit route")
		for index in range(0,return_route.size(),maxi(1,int(return_route.size()/10))):
			var tile: Vector3 = return_route[index]
			var floor_query := PhysicsRayQueryParameters3D.create(tile+Vector3.UP*2.0,tile+Vector3.DOWN*3.0)
			var floor_hit := world.get_world_3d().direct_space_state.intersect_ray(floor_query)
			check(not floor_hit.is_empty(),"Far dungeon corridor lacks physical floor")
			if not floor_hit.is_empty():
				check(floor_hit.normal.y>0.7 and absf(floor_hit.position.y-layout.floor_y)<0.1,"Far dungeon floor is not level and upward-facing")
		world.stream_around([world.get_spawn_position()],0)
	for i in range(1,mini(3,far_samples.size())):
		var load_start := Time.get_ticks_msec()
		var additions: Dictionary = world.ensure_at(far_samples[i].center)
		load_times.append(Time.get_ticks_msec()-load_start)
		check(additions.added_islands.size()==1,"Additional far procedural island did not load")
		world.stream_around([world.get_spawn_position()],0)
	load_times.sort()
	if not load_times.is_empty():
		print("PROCEDURAL_LOAD_MS_MEDIAN=",load_times[int(load_times.size()/2)]," MAX=",load_times[-1])
	var travelled := 0
	for sx in range(8,30):
		var candidate: Dictionary = world.sector_manifest(sx,1)
		if candidate.is_empty() or candidate.sky:
			continue
		world.ensure_at(candidate.center)
		world.stream_around([candidate.center],0)
		await process_frame
		var active_procedural := 0
		for island in world.island_records:
			if island.get("procedural",false):
				active_procedural += 1
		check(active_procedural<=world.STREAM_MAX_ISLANDS and world._stream_nodes.size()<=world.STREAM_MAX_ISLANDS,"Streamed island memory grew without bound")
		check(world._island_images.size()<=world.STREAM_MAX_ISLANDS+2,"Unloaded island heightmaps were retained")
		travelled += 1
	check(travelled>=12,"Streaming traversal did not cover enough islands")
	var second: Node3D = WorldScript.new()
	root.add_child(second)
	second.configure(21991,2)
	second.build()
	var second_starter: Dictionary = second.island_records[0]
	check(second_starter.center==starter.center and second_starter.radius==starter.radius and second_starter.variation==starter.variation,"Starter shape changed with world seed")
	check(absf(second._local_height(second_starter,starter.center.x+12.0,starter.center.z-5.0)-starter_height)<0.0001,"Starter terrain changed with world seed")
	if not first.is_empty():
		var other: Dictionary = second.sector_manifest(first.sector.x,first.sector.y)
		check(other.is_empty() or other.center!=first.center or other.biome!=first.biome,"Different seeds produced identical far island")
	var active_count := 0
	for island in second.island_records:
		if island.get("procedural",false):
			active_count += 1
	check(active_count<=second.STREAM_MAX_ISLANDS,"Initial streaming exceeded active cap")
	var overlap_seed := -1
	for candidate_seed in range(1,200):
		var overlap_manifest: Dictionary = IslandGenerator.sector_manifest(candidate_seed,2,-1,-1)
		if not overlap_manifest.is_empty() and not overlap_manifest.sky:
			overlap_seed=candidate_seed
			break
	check(overlap_seed>=0,"Could not find a valid compressed dungeon origin overlap")
	if overlap_seed>=0:
		var overlap_world: Node3D = WorldScript.new()
		root.add_child(overlap_world)
		overlap_world.configure(overlap_seed,2)
		overlap_world.build()
		var compressed_start := Vector3(-130.0,1024.15,-130.0)
		check(Vector2(compressed_start.x+72.0,compressed_start.z+77.0).length()<77.0*1.2,"Overlap fixture did not project into starter bounds")
		var overlap_changes: Dictionary = overlap_world.ensure_at(compressed_start)
		check(overlap_changes.added_islands.size()==1 and overlap_world.dungeon_at(compressed_start)=="proc_-1_-1/dungeon","Interior reconnect was mistaken for overlapping exterior island")
		overlap_world.queue_free()
	print("PROCEDURAL_WORLD_FAILURES=",failures.size())
	world.queue_free()
	second.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
