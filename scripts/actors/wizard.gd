class_name SeaWizard
extends CharacterBody3D

var player_id := ""
var local_control := false
var ocean: Node3D
var archipelago: Node3D
var camera: Camera3D
var visual: Node3D
var staff: Node3D
var yaw := 0.0
var pitch := 0.0
var breath := 30.0
var mana := 100.0
var aboard_id := ""
var helm_id := ""
var alive := true
var swimming := false
var head_underwater := false
var input_data: Dictionary = {}
var knockback := Vector3.ZERO
var target_position := Vector3.ZERO
var _step_time := 0.0
var dev_fly_enabled := false
var dev_fly_speed := 24.0
var _walk_collision_layer := 2
var _walk_collision_mask := 1
var _walk_floor_snap_length := 0.65

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	platform_floor_layers = 0
	floor_max_angle = deg_to_rad(55)
	floor_snap_length = 0.65
	_walk_collision_layer = collision_layer
	_walk_collision_mask = collision_mask
	_walk_floor_snap_length = floor_snap_length
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.92
	add_child(collider)
	set_meta("player_id", player_id)
	if ResourceLoader.exists("res://assets/models/wizard.glb"):
		visual = load("res://assets/models/wizard.glb").instantiate()
		add_child(visual)
		visual.visible = not local_control
	if local_control:
		camera = Camera3D.new()
		camera.position.y = 1.64
		camera.near = 0.06
		camera.far = 2200.0
		camera.fov = 78
		add_child(camera)
		camera.current = true
		if ResourceLoader.exists("res://assets/models/staff.glb"):
			staff = load("res://assets/models/staff.glb").instantiate()
			camera.add_child(staff)
			staff.position = Vector3(0.43,-0.86,-0.75)
			staff.scale = Vector3.ONE*0.56

func aim(relative: Vector2) -> void:
	yaw -= relative.x * 0.0022
	pitch = clampf(pitch-relative.y*0.0022,-1.47,1.47)
	_update_look()

func _update_look() -> void:
	rotation.y = yaw
	if camera:
		camera.rotation.x = pitch

func set_dev_fly(enabled: bool) -> void:
	if dev_fly_enabled == enabled:
		return
	dev_fly_enabled = enabled
	velocity = Vector3.ZERO
	knockback = Vector3.ZERO
	if enabled:
		collision_layer = 0
		collision_mask = 0
		floor_snap_length = 0.0
		aboard_id = ""
		return
	collision_layer = _walk_collision_layer
	collision_mask = _walk_collision_mask
	floor_snap_length = _walk_floor_snap_length
	if archipelago:
		var dungeon_id: String = archipelago.dungeon_at(global_position) if archipelago.has_method("dungeon_at") else ""
		if not dungeon_id.is_empty() and archipelago.has_method("dungeon_landmarks"):
			var nearest := global_position
			var nearest_distance := INF
			for landmark in archipelago.dungeon_landmarks():
				if str(landmark.get("dungeon_id","")) != dungeon_id or archipelago.dungeon_at(landmark.position) != dungeon_id: continue
				var point: Vector3 = landmark.position
				var distance := global_position.distance_squared_to(point)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest = point
			global_position = nearest
		else:
			global_position.y = maxf(global_position.y,archipelago.sample_surface_at(global_position)+1.25)

func simulate(delta: float, boats: Dictionary) -> void:
	if not alive:
		return
	yaw = float(input_data.get("yaw",yaw))
	pitch = float(input_data.get("pitch",pitch))
	_update_look()
	mana = minf(100,mana+delta*9)
	if dev_fly_enabled:
		var move := Vector2(float(input_data.get("move_x",0)),float(input_data.get("move_y",0))).limit_length()
		var vertical := float(bool(input_data.get("ascend",false)))-float(bool(input_data.get("descend",false)))
		var look_basis := Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,pitch)
		var direction := look_basis*Vector3(move.x,0,move.y)+Vector3.UP*vertical
		if direction.length_squared()>1.0: direction=direction.normalized()
		global_position += direction*dev_fly_speed*(2.0 if bool(input_data.get("sprint",false)) else 1.0)*delta
		velocity = Vector3.ZERO
		breath = 30.0
		swimming = false
		head_underwater = false
		return
	if not helm_id.is_empty() and boats.has(helm_id):
		var boat: Node3D = boats[helm_id]
		global_position = boat.to_global(SpellwakeBoat.HELM_LOCAL)
		velocity = Vector3.ZERO
		breath = 30.0
		return
	var deck: Node3D = boats.get(aboard_id)
	var on_deck: bool = deck != null and deck.deck_contains(global_position)
	var water_y: float = ocean.sample_height(global_position) if ocean else 0.0
	var fall: Dictionary = archipelago.waterfall_at(global_position) if archipelago else {}
	swimming = (global_position.y + 0.95 < water_y and not on_deck) or not fall.is_empty()
	head_underwater = global_position.y+1.64 < water_y and fall.is_empty()
	breath = maxf(0,breath-delta) if head_underwater else minf(30,breath+delta*10)
	var move := Vector2(float(input_data.get("move_x",0)),float(input_data.get("move_y",0)))
	move = move.limit_length()
	var wish := Basis(Vector3.UP,yaw)*Vector3(move.x,0,move.y)
	var speed := 7.0 if bool(input_data.get("sprint",false)) else 4.8
	if swimming:
		speed = 5.0
		var vertical := float(bool(input_data.get("ascend",false)))-float(bool(input_data.get("descend",false)))
		if not fall.is_empty():
			vertical = 1.0 if vertical >= 0 else vertical
		velocity.y = lerpf(velocity.y,vertical*7.5,1.0-exp(-delta*5))
		if vertical == 0.0 and not head_underwater and fall.is_empty():
			velocity.y += (water_y-0.9-global_position.y)*delta*5
	else:
		velocity.y -= 20.0*delta
		if bool(input_data.get("jump",false)) and (is_on_floor() or (on_deck and deck.to_local(global_position).y < 1.3)):
			velocity.y = 7.6
	velocity.x = move_toward(velocity.x,wish.x*speed,delta*24)
	velocity.z = move_toward(velocity.z,wish.z*speed,delta*24)
	velocity += knockback*delta
	knockback = knockback.move_toward(Vector3.ZERO,delta*12)
	move_and_slide()
	if deck:
		var deck_pos: Vector3 = deck.to_local(global_position)
		if absf(deck_pos.x)<3.0 and absf(deck_pos.z)<5.2 and deck_pos.y<1.19 and deck_pos.y>0.2 and velocity.y<=0:
			deck_pos.y=1.19
			global_position=deck.to_global(deck_pos)
			velocity.y=0
		elif absf(deck_pos.x)>3.1 or absf(deck_pos.z)>5.4 or deck_pos.y<0.2:
			aboard_id=""
	# Let the physical floor support the wizard. The terrain height image is a
	# smooth approximation of streamed triangles; snapping up to it can hold
	# feet above the collider forever and prevent grounded jumping.
	if local_control and staff:
		_step_time += delta*move.length()*8
		staff.position.y = -0.86 + sin(_step_time)*0.022
		staff.rotation.z = sin(_step_time*0.5)*0.015

func get_aim_direction() -> Vector3:
	return Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,pitch)*Vector3.FORWARD

func get_eye_position() -> Vector3:
	return global_position+Vector3.UP*1.64
