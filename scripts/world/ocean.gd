class_name Ocean
extends "res://addons/boujie_water_shader/types/ocean.gd"
## Boujie LOD ocean with one shared Gerstner model for visuals and server physics.
## Simulation time is explicitly writable by the authoritative world clock.

const WATER_SHADER = preload("res://shaders/ocean.gdshader")
const WAVES: Array[Vector4] = [
	Vector4(0.88, 0.48, 0.58, 21.0),
	Vector4(-0.42, 0.91, 0.26, 11.5),
	Vector4(0.98, -0.2, 0.16, 5.8),
	Vector4(0.4, 0.92, 0.075, 2.7),
]
var simulation_time: float = 0.0
var externally_clocked: bool = false
var world: Node3D
var water_material: ShaderMaterial

func _ready() -> void:
	outermost_resolution = 32
	levels_of_detail = 5
	unit_size = 0.25
	far_edge = 15000
	water_material = ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	water_material.set_shader_parameter("foam_pattern",load("res://assets/textures/ocean-foam.png"))
	material = water_material
	for i in WAVES.size():
		water_material.set_shader_parameter("wave_%d" % i, WAVES[i])
	build_meshes()
	for child in get_children():
		if child is MeshInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			child.extra_cull_margin = 4.0
	add_to_group("ocean")

func _process(delta: float) -> void:
	if not externally_clocked:
		simulation_time += delta
	if water_material:
		water_material.set_shader_parameter("ocean_time", simulation_time)
	var camera := get_viewport().get_camera_3d()
	if camera:
		# Snap by outer tile spacing so the geometry itself does not swim.
		position.x = snappedf(camera.global_position.x, max_unit_size)
		position.z = snappedf(camera.global_position.z, max_unit_size)

func set_simulation_time(value: float) -> void:
	externally_clocked = true
	simulation_time = value

func _displacement(q: Vector2, at_time: float) -> Vector3:
	var result := Vector3.ZERO
	for wave in WAVES:
		var direction := Vector2(wave.x, wave.y).normalized()
		var k := TAU / wave.w
		var phase := k * direction.dot(q) - sqrt(9.81 * k) * at_time
		result += Vector3(direction.x * wave.z * 0.68 * cos(phase), wave.z * sin(phase), direction.y * wave.z * 0.68 * cos(phase))
	return result

func sample_height(point: Vector3, at_time: float = -1.0) -> float:
	var t := simulation_time if at_time < 0.0 else at_time
	var target := Vector2(point.x, point.z)
	var q := target
	# Invert the horizontal Gerstner shift; sampling undeformed XZ is incorrect.
	for i in 5:
		var shift := _displacement(q, t)
		q = target - Vector2(shift.x, shift.z)
	return _displacement(q, t).y

func sample_normal(point: Vector3, at_time: float = -1.0) -> Vector3:
	const EPS := 0.12
	var dx := sample_height(point + Vector3(EPS, 0, 0), at_time) - sample_height(point - Vector3(EPS, 0, 0), at_time)
	var dz := sample_height(point + Vector3(0, 0, EPS), at_time) - sample_height(point - Vector3(0, 0, EPS), at_time)
	return Vector3(-dx, EPS * 2.0, -dz).normalized()

func sample_velocity(point: Vector3, at_time: float = -1.0) -> Vector3:
	var t := simulation_time if at_time < 0.0 else at_time
	return (_displacement(Vector2(point.x, point.z), t + 0.025) - _displacement(Vector2(point.x, point.z), t - 0.025)) / 0.05

func set_shore_data(heightmap: Texture2D, origin: Vector2, map_size: Vector2) -> void:
	water_material.set_shader_parameter("seabed_height", heightmap)
	water_material.set_shader_parameter("seabed_origin", origin)
	water_material.set_shader_parameter("seabed_size", map_size)
	water_material.set_shader_parameter("has_seabed", true)

func set_ship_wakes(wakes: Array) -> void:
	if not water_material:
		return
	var values: Array[Vector4]=[]
	for i in 6:
		values.append(wakes[i] if i<wakes.size() else Vector4.ZERO)
	water_material.set_shader_parameter("ship_wakes",values)
	water_material.set_shader_parameter("wake_count",mini(wakes.size(),6))
