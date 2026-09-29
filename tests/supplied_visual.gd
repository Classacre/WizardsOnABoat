extends SceneTree
## Rendered spot checks of the playable main scene after supplied model import.

const State = preload("res://scripts/data/world_state.gd")
const OUTPUT := "res://tmp/model-intake/"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game._build_world(7319,1)
	game.hud.hide()
	var world := State.new("supplied_visual",7319,1)
	game.creature_manager.seed_world(world)
	game.creature_manager.time_of_day = 23.0
	for index in 22:
		game.creature_manager.simulate(0.1,world,{})
	game.sky.set_time_of_day(12.0)
	var camera: Camera3D = game.preview_camera
	await _capture(camera,Vector3(6.4,6.4,73.0),Vector3(6.4,4.0,58.0),"runtime-harbour-ship.png")
	var boat: Node3D = game.preview_boat
	var playable_boat: Node3D = load("res://scripts/actors/boat.gd").new()
	game.scenery.add_child(playable_boat)
	playable_boat.global_transform = boat.global_transform
	boat.hide()
	await _capture(camera,playable_boat.to_global(Vector3(-1.6,2.82,2.5)),playable_boat.to_global(Vector3(0,2.0,-5.0)),"runtime-helm-playable.png")
	boat.show()
	playable_boat.hide()
	await _capture(camera,boat.to_global(Vector3(11,2.8,1.0)),boat.to_global(Vector3(0,1.3,0)),"runtime-hull-waterline.png")
	var shop := _poi(game,"hearthharbour/shop")
	if shop.is_finite():
		await _capture(camera,shop+Vector3(11,5,14),shop+Vector3(0,2,0),"runtime-harbour-shop.png")
	var root_dungeon := _poi(game,"rootwatch/dungeon")
	if root_dungeon.is_finite():
		await _capture(camera,root_dungeon+Vector3(15,8,16),root_dungeon+Vector3(1,2,0),"runtime-rootwatch-kit.png")
	var tide_dungeon := _poi(game,"tide_vault/dungeon")
	if tide_dungeon.is_finite():
		await _capture(camera,tide_dungeon+Vector3(15,8,16),tide_dungeon+Vector3(1,2,0),"runtime-tide-kit.png")
	var sky_creature := _creature(game,"threadwing")
	if sky_creature.is_finite():
		await _capture(camera,sky_creature+Vector3(9,5,11),sky_creature,"runtime-threadwing.png")
	var cumulus := _creature(game,"cumulus")
	if cumulus.is_finite():
		await _capture(camera,cumulus+Vector3(9,5,11),cumulus,"runtime-cumulus.png")
	var tidebell := _creature(game,"tidebell")
	if tidebell.is_finite():
		await _capture(camera,tidebell+Vector3(9,1,11),tidebell,"runtime-tidebell-underwater.png")
	var crab := _creature(game,"kettleback")
	if crab.is_finite():
		await _capture(camera,crab+Vector3(6,4,9),crab,"runtime-crab.png")
	print("SUPPLIED_VISUAL_CAPTURE_COMPLETE")
	quit()

func _poi(game: Node3D, id: String) -> Vector3:
	for poi in game.archipelago.pois:
		if poi.id == id:
			return poi.position
	return Vector3(NAN,NAN,NAN)

func _creature(game: Node3D, species: String) -> Vector3:
	for actor in game.creature_manager.actors.values():
		if actor.record.species == species:
			return actor.body.position
	return Vector3(NAN,NAN,NAN)

func _capture(camera: Camera3D, position_value: Vector3, target: Vector3, filename: String) -> void:
	camera.position = position_value
	camera.look_at(target)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image_value := root.get_texture().get_image()
	var error := image_value.save_png(OUTPUT + filename)
	print("RUNTIME_CAPTURE ",filename," error=",error," size=",image_value.get_size())
