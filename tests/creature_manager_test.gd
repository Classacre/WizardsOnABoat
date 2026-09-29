extends SceneTree

const Manager = preload("res://scripts/actors/creature_manager.gd")
const State = preload("res://scripts/data/world_state.gd")
var failures: Array[String] = []

class TestIslands extends Node3D:
	var blocked := false
	var island_records: Array[Dictionary] = [
		{"id":"test_basalt","center":Vector3.ZERO,"radius":25.0,"biome":"Basalt Heath","sky":false,"safe":false,"paths":[PackedVector3Array([Vector3(-4,4,0),Vector3(0,4,0),Vector3(4,4,0),Vector3(8,4,0),Vector3(12,4,0)])]},
		{"id":"test_sky","center":Vector3(60,40,0),"radius":15.0,"biome":"Cloud Meadow","sky":true,"safe":false,"paths":[]},
		{"id":"safe_basalt","center":Vector3(-120,0,0),"radius":20.0,"biome":"Basalt Heath","sky":false,"safe":true,"paths":[]},
	]
	var navigation_graphs := {"test_basalt":{"revision":0,"blocked":[]}}
	func get_dungeon(_id: String) -> Dictionary:
		return {}
	func sample_surface_at(p: Vector3) -> float:
		return 40.0 if p.y>25 else 4.0
	func sample_ground_height(_x: float,_z: float) -> float:
		return 4.0
	func is_safe_zone(p: Vector3) -> bool:
		return p.x < -100.0
	func route_is_clear(_id: String,_from: Vector3,_to: Vector3) -> bool:
		return not blocked

class TestSeaIslands extends Node3D:
	var island_records: Array[Dictionary] = [
		{"id":"needle_cay","center":Vector3(0,0,0),"radius":30.0,"biome":"Open Water","sky":false,"safe":false},
		{"id":"rootwatch","center":Vector3(120,0,0),"radius":30.0,"biome":"Open Water","sky":false,"safe":false},
		{"id":"tide_vault","center":Vector3(240,0,0),"radius":30.0,"biome":"Open Water","sky":false,"safe":false},
	]
	var navigation_graphs := {}
	func sample_ground_height(_x: float,_z: float) -> float:
		return -12.0
	func is_safe_zone(_p: Vector3) -> bool:
		return false

class TestOcean extends Node3D:
	func sample_height(_p: Vector3) -> float:
		return 0.0

class TestStormglass extends Node3D:
	var island_records: Array[Dictionary] = [
		{"id":"stormglass","center":Vector3(0,40,0),"radius":20.0,"biome":"Stormglass Reef","sky":true,"safe":false},
	]
	var navigation_graphs := {}
	func sample_surface_at(_p: Vector3) -> float:
		return 40.0
	func is_safe_zone(_p: Vector3) -> bool:
		return false

class TestStreamingIslands extends Node3D:
	var world_seed := 4141
	var island_records: Array[Dictionary] = [
		{"id":"near_basalt","center":Vector3.ZERO,"radius":35.0,"biome":"Basalt Heath","sky":false,"safe":false,"paths":[PackedVector3Array([Vector3(0,4,0),Vector3(6,4,0),Vector3(12,4,0)])]},
		{"id":"far_basalt","center":Vector3(1400,0,0),"radius":35.0,"biome":"Basalt Heath","sky":false,"safe":false,"paths":[PackedVector3Array([Vector3(1400,4,0),Vector3(1406,4,0),Vector3(1412,4,0)])]},
	]
	var navigation_graphs := {"near_basalt":{"revision":0,"blocked":[]},"far_basalt":{"revision":0,"blocked":[]}}
	func stream_around(_anchors: Array[Vector3],_max_new: int = 1) -> Dictionary:
		return {}
	func sample_surface_at(_p: Vector3) -> float:
		return 4.0
	func is_safe_zone(_p: Vector3) -> bool:
		return false
	func route_is_clear(_id: String,_from: Vector3,_to: Vector3) -> bool:
		return true

class TestProceduralSeaIslands extends Node3D:
	var world_seed := 7171
	var island_records: Array[Dictionary] = [
		{"id":"proc_6_6","center":Vector3(0,0,0),"radius":65.0,"biome":"Saltgrass Coast","sky":false,"safe":false,"procedural":true,"paths":[],"pois":[]},
		{"id":"proc_7_7","center":Vector3(220,0,0),"radius":65.0,"biome":"Mangrove Orchard","sky":false,"safe":false,"procedural":true,"paths":[],"pois":[]},
	]
	var navigation_graphs := {}
	func get_dungeon(_id: String) -> Dictionary:
		return {}
	func sample_surface_at(_p: Vector3) -> float:
		return 4.0
	func sample_ground_height(_x: float,_z: float) -> float:
		return -12.0
	func is_safe_zone(_p: Vector3) -> bool:
		return false
	func route_is_clear(_id: String,_from: Vector3,_to: Vector3) -> bool:
		return false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var islands := TestIslands.new()
	root.add_child(islands)
	var manager := Manager.new()
	root.add_child(manager)
	manager.configure(islands,null)
	var world := State.new("creature_runtime_test",4141)
	check(world.connect_player("tester","Tester").ok,"Player setup failed")
	check(manager.seed_world(world)==11,"Modeled, biome-eligible species did not spawn")
	check(world.mobs.size()==11 and manager.actors.size()==11,"Runtime/model population mismatch")
	check(manager.actors.has("wild/test_basalt/knuckler/0") and manager.actors.has("wild/test_sky/cumulus/0"),"New land and sky species are missing")
	var before := world.mobs.duplicate(true)
	check(manager.seed_world(world)==0,"Seeding twice must not create more mobs")
	check(before==world.mobs,"Reseeding rerolled persistent inventory or stats")
	var crab_id := "wild/test_basalt/kettleback/0"
	check(manager.actors[crab_id].body.get_meta("mob_id")==crab_id,"Projectile collision identity is missing")
	check(manager.actors[crab_id].body.collision_layer==8,"Creature is absent from projectile collision mask")
	check(not manager.damage_mob(crab_id,"tester",10,world).ok,"Harbour player damaged a mob")
	world.update_player_position("tester",Vector3(150,4,0),false)
	var old_health: float = world.mobs[crab_id].health
	check(not manager.damage_mob(crab_id,"tester",NAN,world).ok,"Non-finite damage accepted")
	check(not manager.damage_mob(crab_id,"tester",-5,world).ok,"Negative damage accepted")
	check(manager.damage_mob(crab_id,"tester",10,world).ok,"Legal damage rejected")
	check(is_equal_approx(world.mobs[crab_id].health,old_health-10),"Damage did not change persistent health")
	# Obstructing a route must halt a crab even without a ready nav server map.
	islands.blocked = true
	islands.navigation_graphs.test_basalt.revision += 1
	var body: CharacterBody3D = manager.actors[crab_id].body
	var held := body.position
	for index in 15:
		manager.simulate(1.0/60.0,world,{})
		await physics_frame
	check(Vector2(body.position.x-held.x,body.position.z-held.z).length()<0.01,"Crab walked through a blocked route")
	islands.blocked = false
	islands.navigation_graphs.test_basalt.revision += 1
	for index in 45:
		manager.simulate(1.0/60.0,world,{})
		await physics_frame
	check(body.position.distance_to(held)>0.1,"Crab did not resume wandering after obstruction removed")
	# Death is one transaction: one public inventory chest, no resurrection/reroll.
	var loot_before := world.loot.size()
	var killed: Dictionary = manager.damage_mob(crab_id,"tester",9999,world)
	check(killed.ok and world.loot.size()==loot_before+1,"Death did not produce exactly one chest")
	check(not manager.damage_mob(crab_id,"tester",9999,world).ok,"Dead mob could be killed twice")
	manager.seed_world(world)
	check(not world.mobs[crab_id].alive and not manager.actors.has(crab_id),"Reseeding resurrected a killed creature")
	check(world.loot.size()==loot_before+1,"Duplicate creature loot was created")
	var replay := Manager.new()
	root.add_child(replay)
	replay.configure(islands,null)
	replay.sync_snapshot(world.snapshot())
	check(replay.actors.size()==10 and not replay.actors.has(crab_id),"Client restored a dead actor")
	var compact := manager.simulation_snapshot(world)
	replay.sync_snapshot({"mobs":compact})
	check(replay.actors.size()==compact.size(),"Compact simulation snapshot changed population")
	check(str(replay.actors["wild/test_basalt/kettleback/1"].record.get("island_id",""))=="test_basalt","Compact snapshots erased reliable island metadata")
	var live_crab := "wild/test_basalt/kettleback/1"
	world.players.tester.health = 1.0
	world.update_player_position("tester",Manager._vector(world.mobs[live_crab].position),false)
	manager.actors[live_crab].cooldown = 0.0
	manager.simulate(1.0/60.0,world,{})
	check(not world.players.tester.alive,"Crab contact attack did not enter normal player death flow")
	var save_path := "user://tests/creature-runtime-world.json"
	check(world.save_to(save_path)==OK,"Creature world save failed")
	var restored := State.new("creature_runtime_test",0)
	check(restored.load_from(save_path).ok,"Creature world save could not be loaded")
	check(restored.mobs.has(crab_id) and not restored.mobs[crab_id].alive,"Save/load lost persistent creature death")
	var restored_manager := Manager.new()
	root.add_child(restored_manager)
	restored_manager.configure(islands,null)
	check(restored_manager.seed_world(restored)==0,"Rehosting duplicated the persisted population")
	check(restored.mobs.size()==11,"World restore changed creature identities")
	DirAccess.remove_absolute(save_path)
	# Midnight should defer daytime Threadwing recipes until daylight.
	var night_world := State.new("night_test",99)
	var night_manager := Manager.new()
	root.add_child(night_manager)
	night_manager.configure(islands,null)
	night_manager.time_of_day = 23.0
	check(night_manager.seed_world(night_world)==4,"Daytime-only species appeared at night")
	night_manager.time_of_day = 12.0
	for index in 22:
		night_manager.simulate(0.1,night_world,{})
	check(night_world.mobs.size()==11,"Deferred daytime species did not spawn in daylight")
	var sea_islands := TestSeaIslands.new()
	var sea_ocean := TestOcean.new()
	root.add_child(sea_islands)
	root.add_child(sea_ocean)
	var sea_manager := Manager.new()
	root.add_child(sea_manager)
	sea_manager.configure(sea_islands,sea_ocean)
	var sea_world := State.new("sea_runtime_test",1414)
	check(sea_manager.seed_world(sea_world)==4,"Daytime sea habitats did not spawn Ribbonwakes and Tidebell")
	check(sea_world.mobs.size()==4,"Daytime sea habitats did not spawn Ribbonwakes and Tidebell")
	check(sea_manager.actors.has("wild/needle_cay/ribbonwake/0") and sea_manager.actors.has("wild/tide_vault/tidebell/0"),"Sea creatures have no live model actor")
	var tide_y: float = sea_world.mobs["wild/tide_vault/tidebell/0"].position[1]
	check(tide_y >= -11.2 and tide_y+5.0 <= -0.8,"Tidebell mesh breaches seabed or water surface")
	sea_manager.time_of_day = 23.0
	for index in 22:
		sea_manager.simulate(0.1,sea_world,{})
	check(sea_world.mobs.size()==6 and sea_manager.actors.has("wild/rootwatch/lanternjaw/0"),"Night Lanternjaws did not join persistent sea ecology")
	var storm_islands := TestStormglass.new()
	root.add_child(storm_islands)
	var storm_manager := Manager.new()
	root.add_child(storm_manager)
	storm_manager.configure(storm_islands,null)
	storm_manager.time_of_day = 17.0
	var storm_world := State.new("stormglass_runtime_test",1717)
	check(storm_manager.seed_world(storm_world)==4,"Stormglass creatures did not spawn in their window")
	check(storm_world.mobs["wild/stormglass/stormglass_roc/0"].rarity == "rare","Stormglass Roc used a disallowed rarity")
	var stream_islands := TestStreamingIslands.new()
	root.add_child(stream_islands)
	var stream_manager := Manager.new()
	root.add_child(stream_manager)
	stream_manager.configure(stream_islands,null)
	stream_manager.set_stream_anchors([Vector3.ZERO])
	var stream_world := State.new("stream_runtime_test",4141)
	stream_manager.seed_world(stream_world)
	check(stream_world.mobs.has("wild/near_basalt/kettleback/0") and not stream_world.mobs.has("wild/far_basalt/kettleback/0"),"Distant prefetch islands spawned persistent mobs before approach")
	check(stream_manager.actors.has("wild/near_basalt/kettleback/0") and stream_manager.actors.size()<=Manager.MAX_ACTIVE_ACTORS,"Initial streamed actors are bounded near the player")
	var retained: Dictionary = stream_world.mobs["wild/near_basalt/kettleback/0"].duplicate(true)
	stream_manager.set_stream_anchors([Vector3(1400,4,0)])
	stream_manager.seed_world(stream_world)
	check(not stream_manager.actors.has("wild/near_basalt/kettleback/0") and stream_manager.actors.has("wild/far_basalt/kettleback/0"),"Crossing the sea unloads far physics actors and loads nearby ones")
	check(stream_world.mobs["wild/near_basalt/kettleback/0"]==retained,"Streaming modified a persistent distant creature record")
	stream_islands.navigation_graphs.erase("far_basalt")
	stream_manager.seed_world(stream_world)
	check(not stream_manager.actors.has("wild/far_basalt/kettleback/0") and stream_world.mobs.has("wild/far_basalt/kettleback/0"),"Unloaded navigation terrain retained a live collision actor")
	stream_islands.navigation_graphs.far_basalt = {"revision":0,"blocked":[]}
	for index in 120:
		stream_world.spawn_mob("knuckler","Basalt Heath",12.0,Vector3(1400+float(index%20),4.0,float(index/20)))
	stream_manager.seed_world(stream_world)
	check(stream_manager.actors.size()<=Manager.MAX_ACTIVE_ACTORS,"Streaming exceeded the 96 live actor ceiling")
	var replay_id := "wild/far_basalt/kettleback/0"
	var replay_anchor: Vector3 = Manager._vector(stream_world.mobs[replay_id].position)
	stream_manager.set_stream_anchors([replay_anchor])
	stream_manager.seed_world(stream_world)
	var stream_replay := Manager.new()
	root.add_child(stream_replay)
	stream_replay.configure(stream_islands,null)
	stream_replay.set_stream_anchors([replay_anchor])
	stream_replay.sync_snapshot(stream_world.snapshot())
	check(stream_replay.actors.size()<=Manager.MAX_ACTIVE_ACTORS,"Client created every historical actor from a full world snapshot")
	var replay_island := str(stream_replay.actors[replay_id].record.get("island_id",""))
	stream_replay.sync_snapshot({"mobs":stream_manager.simulation_snapshot(stream_world)})
	check(str(stream_replay.actors[replay_id].record.get("island_id",""))==replay_island and replay_island=="far_basalt","Compact multiplayer packets erased streamed creature metadata")
	var procedural_islands := TestProceduralSeaIslands.new()
	var procedural_ocean := TestOcean.new()
	root.add_child(procedural_islands)
	root.add_child(procedural_ocean)
	var procedural_manager := Manager.new()
	root.add_child(procedural_manager)
	procedural_manager.configure(procedural_islands,procedural_ocean)
	var procedural_world := State.new("procedural_sea_test",7171)
	procedural_manager.seed_world(procedural_world)
	check(procedural_world.mobs.has("wild/proc_6_6/ribbonwake/0"),"Procedural sunny coast lacks legal Ribbonwakes")
	procedural_manager.time_of_day = 23.0
	for index in 22:
		procedural_manager.simulate(0.1,procedural_world,{})
	check(procedural_world.mobs.has("wild/proc_7_7/lanternjaw/0"),"Procedural kelp coast did not gain nocturnal Lanternjaws")
	print("CREATURE_RUNTIME_TEST_FAILURES=",failures.size())
	manager.queue_free(); replay.queue_free(); restored_manager.queue_free(); night_manager.queue_free(); islands.queue_free(); sea_manager.queue_free(); sea_ocean.queue_free(); sea_islands.queue_free(); storm_manager.queue_free(); storm_islands.queue_free(); stream_manager.queue_free(); stream_replay.queue_free(); stream_islands.queue_free(); procedural_manager.queue_free(); procedural_ocean.queue_free(); procedural_islands.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
