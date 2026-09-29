extends SceneTree

const Catalog = preload("res://scripts/data/game_catalog.gd")
const Manager = preload("res://scripts/actors/creature_manager.gd")
const World = preload("res://scripts/world/archipelago.gd")
const Ocean = preload("res://scripts/world/ocean.gd")
const State = preload("res://scripts/data/world_state.gd")
const Boat = preload("res://scripts/actors/boat.gd")

const USED_MODULES := {
	"tide_kit": ["tide_arch", "tide_rubble"],
	"coastal_kit": ["coastal_arch", "coastal_moss", "coastal_pillar"],
	"root_kit": ["root_arch"],
}

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	for species in Manager.MODELS:
		var path: String = Manager.MODELS[species]
		check(ResourceLoader.exists(path),"Missing supplied model for " + species)
		if not ResourceLoader.exists(path):
			continue
		var instance: Node3D = load(path).instantiate()
		check(not instance.find_children("*","MeshInstance3D",true,false).is_empty(),"Imported model has no mesh: " + species)
		var skeletons := instance.find_children("*","Skeleton3D",true,false)
		var players := instance.find_children("*","AnimationPlayer",true,false)
		check(not skeletons.is_empty() and not players.is_empty(),"Missing imported rig or AnimationPlayer: " + species)
		if not players.is_empty():
			var clips: Array[String] = []
			for clip in players[0].get_animation_list():
				clips.append(str(clip).to_lower())
			check(clips.has("idle") and (clips.has("walk") or clips.has("swim") or clips.has("fly")),"Missing idle or movement clip: " + species)
		instance.free()
	for kit in USED_MODULES:
		var path := "res://assets/models/supplied/%s.glb" % kit
		check(ResourceLoader.exists(path),"Missing supplied kit: " + kit)
		if not ResourceLoader.exists(path):
			continue
		var instance: Node3D = load(path).instantiate()
		for module_name in USED_MODULES[kit]:
			check(instance.find_child(module_name,true,false) != null,"Missing placed module: " + module_name)
		instance.free()
	for part in ["boat_hull", "boat_rig", "cottage", "dock", "ruin_arch", "crate", "lantern", "tide_gate"]:
		check(ResourceLoader.exists("res://assets/models/supplied/%s.glb" % part),"Missing supplied world prop: " + part)
	var archipelago := World.new()
	root.add_child(archipelago)
	archipelago.configure(7319,1)
	archipelago.build()
	var ocean := Ocean.new()
	root.add_child(ocean)
	ocean.set_shore_data(archipelago.shore_texture,Vector2(-512,-512),Vector2(1024,1024))
	var manager := Manager.new()
	root.add_child(manager)
	manager.configure(archipelago,ocean)
	var world := State.new("supplied_model_test",7319,1)
	manager.seed_world(world)
	manager.time_of_day = 23.0
	for index in 22:
		manager.simulate(0.1,world,{})
	var covered := {}
	for mob in world.mobs.values():
		var first_of_species: bool = not covered.has(mob.species)
		covered[mob.species] = true
		check(manager.actors.has(mob.id),"Spawned creature has no live model: " + mob.species)
		if manager.actors.has(mob.id):
			var actor: Dictionary = manager.actors[mob.id]
			var player: AnimationPlayer = actor.animation_player
			if player != null:
				if first_of_species:
					var actor_skeletons: Array[Node] = actor.visual.find_children("*","Skeleton3D",true,false)
					print("RIG_PATH ",mob.species," skeleton=",actor_skeletons[0].get_path() if not actor_skeletons.is_empty() else "missing"," player=",player.get_path())
				for clip in [actor.idle_clip,actor.move_clip]:
					if not str(clip).is_empty():
						var animation: Animation = player.get_animation(clip)
						check(animation.loop_mode == Animation.LOOP_LINEAR,"Locomotion clip does not loop: " + mob.species + "/" + str(clip))
						player.play(clip)
						player.advance(0.0)
						player.advance(animation.length * 2.25)
						check(player.is_playing() and player.current_animation_position < animation.length * 0.5,"Locomotion clip stopped after two cycles: " + mob.species + "/" + str(clip))
	for species in Catalog.SPECIES:
		check(covered.has(species),"Species absent from playable world across day and night: " + species)
	var boat := Boat.new()
	root.add_child(boat)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	await physics_frame
	var space := root.world_3d.direct_space_state
	var blocked := PhysicsRayQueryParameters3D.create(Vector3(0,2.4,2.5),Vector3(0,2.4,4.0),4)
	var clear := PhysicsRayQueryParameters3D.create(Vector3(-1.6,2.4,2.5),Vector3(-1.6,2.4,4.0),4)
	check(space.intersect_ray(blocked).get("collider") == boat,"Raised stern cabin does not block centerline traversal")
	check(space.intersect_ray(clear).is_empty(),"Port-side helm lane is blocked")
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = capsule
	probe.collision_mask = 4
	probe.transform = Transform3D(Basis.IDENTITY,Boat.HELM_LOCAL + Vector3(0,0.92,0))
	check(space.intersect_shape(probe).is_empty(),"Wizard capsule intersects the supplied cabin at the helm")
	print("SUPPLIED_MODELS_TEST: %d species, %d failures" % [covered.size(),failures.size()])
	boat.queue_free(); camera.queue_free(); manager.queue_free(); ocean.queue_free(); archipelago.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
