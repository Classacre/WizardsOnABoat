class_name SpellwakeBoat
extends AnimatableBody3D

var ship_id := ""
var ocean: Node3D
var archipelago: Node3D
var speed := 0.0
var steering := 0.0
var throttle := 0.0
var heading := 0.0
var wind_charge := 0.0
var pilot_id := ""
var sail: Node3D
var last_transform := Transform3D.IDENTITY
var _phase := 0.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	sync_to_physics = false
	set_meta("ship_id",ship_id)
	for part in ["boat", "boat_sail"]:
		if ResourceLoader.exists("res://assets/models/%s.glb" % part):
			var model: Node3D = load("res://assets/models/%s.glb" % part).instantiate()
			add_child(model)
			if part == "boat_sail":
				sail = model
	_add_box(Vector3(6.2,0.36,10.5),Vector3(0,1.0,0))
	# Sail collider allows projectile raycasts to physically find the canvas.
	var sail_collider := StaticBody3D.new()
	sail_collider.collision_layer = 8
	sail_collider.collision_mask = 0
	sail_collider.set_meta("sail_ship_id",ship_id)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.8,6.6,0.55)
	shape.shape = box
	sail_collider.add_child(shape)
	sail_collider.position = Vector3(2.15,6.0,-1.9)
	sail_collider.rotation.y = 0.724
	add_child(sail_collider)
	last_transform = global_transform

func _add_box(size: Vector3, offset: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	add_child(shape)

func simulate(delta: float) -> void:
	last_transform = global_transform
	_phase += delta
	wind_charge = maxf(0,wind_charge-delta*0.65)
	var target_speed := throttle*7.0 + wind_charge
	speed = move_toward(speed,target_speed,delta*1.25)
	heading += steering*delta*0.35*clampf(absf(speed)/3.0,0.2,1)
	var forward := Vector3(-sin(heading),0,-cos(heading))
	var next := global_position + forward*speed*delta
	if archipelago and archipelago.sample_ground_height(next.x,next.z) > -0.9:
		speed = move_toward(speed,0,delta*12)
	else:
		global_position.x = next.x
		global_position.z = next.z
	if ocean:
		var h: float = ocean.sample_height(global_position)
		var fore: float = ocean.sample_height(global_position+forward*4)
		var aft: float = ocean.sample_height(global_position-forward*4)
		var right := forward.cross(Vector3.UP)
		var starboard: float = ocean.sample_height(global_position+right*2)
		var port: float = ocean.sample_height(global_position-right*2)
		global_position.y = lerpf(global_position.y,h,1.0-exp(-delta*3))
		rotation = Vector3(clampf((fore-aft)/8,-0.13,0.13),heading,clampf((port-starboard)/4,-0.13,0.13))
	if sail:
		sail.rotation.y = sin(_phase*0.5)*0.02 + steering*0.12

func apply_wind(direction: Vector3, strength: float) -> void:
	var forward := Vector3(-sin(heading),0,-cos(heading))
	var aligned := maxf(0.15,direction.dot(forward))
	wind_charge = minf(wind_charge+strength*aligned,13.0)
	heading += direction.dot(global_basis.x)*strength*0.007

func deck_contains(pos: Vector3) -> bool:
	var local := to_local(pos)
	return absf(local.x)<3.1 and absf(local.z)<6 and local.y>0.5 and local.y<3.5
