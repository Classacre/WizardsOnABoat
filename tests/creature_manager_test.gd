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
	func sample_surface_at(p: Vector3) -> float:
		return 40.0 if p.y>25 else 4.0
	func sample_ground_height(_x: float,_z: float) -> float:
		return 4.0
	func is_safe_zone(p: Vector3) -> bool:
		return p.x < -100.0
	func route_is_clear(_id: String,_from: Vector3,_to: Vector3) -> bool:
		return not blocked

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
	check(manager.seed_world(world)==7,"Only modeled, biome-eligible species should spawn")
	check(world.mobs.size()==7 and manager.actors.size()==7,"Runtime/model population mismatch")
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
	check(replay.actors.size()==6 and not replay.actors.has(crab_id),"Client restored a dead actor")
	var compact := manager.simulation_snapshot(world)
	replay.sync_snapshot({"mobs":compact})
	check(replay.actors.size()==compact.size(),"Compact simulation snapshot changed population")
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
	check(restored.mobs.size()==7,"World restore changed creature identities")
	DirAccess.remove_absolute(save_path)
	# Midnight should defer daytime Threadwing recipes until daylight.
	var night_world := State.new("night_test",99)
	var night_manager := Manager.new()
	root.add_child(night_manager)
	night_manager.configure(islands,null)
	night_manager.time_of_day = 23.0
	check(night_manager.seed_world(night_world)==4,"Daytime-only Threadwings appeared at night")
	night_manager.time_of_day = 12.0
	for index in 22:
		night_manager.simulate(0.1,night_world,{})
	check(night_world.mobs.size()==7,"Deferred daytime species did not spawn in daylight")
	print("CREATURE_RUNTIME_TEST_FAILURES=",failures.size())
	manager.queue_free(); replay.queue_free(); restored_manager.queue_free(); night_manager.queue_free(); islands.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
