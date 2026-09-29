class_name Ocean
extends "res://addons/boujie_water_shader/types/ocean.gd"
## Boujie LOD ocean with one shared Gerstner model for visuals and server physics.
## Simulation time is explicitly writable by the authoritative world clock.

const WATER_SHADER = preload("res://shaders/ocean.gdshader")
const WAVES: Array[Vector4] = [
	Vector4(0.88, 0.48, 0.35, 31.0),
	Vector4(-0.42, 0.91, 0.29, 20.5),
	Vector4(0.98, -0.2, 0.23, 13.2),
	Vector4(0.4, 0.92, 0.14, 8.1),
	Vector4(-0.73, -0.68, 0.08, 5.0),
	Vector4(0.24, -0.97, 0.035, 3.0),
]
const GROUP_STRENGTH := Vector3(0.11, 0.08, 0.07)
var simulation_time: float = 0.0
var externally_clocked: bool = false
var world_seed: int = 0
var world: Node3D
var water_material: ShaderMaterial
var _waves: Array[Vector4] = []
var _wave_info: Array[Vector4] = []
var _wave_phases := Vector4.ZERO
var _wave_tail_phases := Vector2.ZERO
var _group_info: Array[Vector4] = []
var _group_phases := Vector3.ZERO
var _foam_seed_offset := Vector2.ZERO
var _shore_sources: Array[Vector4] = []
var _shore_patches: Array[Vector4] = []
var _last_shore_anchor := Vector2(INF, INF)

func _ready() -> void:
	outermost_resolution = 32
	levels_of_detail = 5
	unit_size = 0.25
	outer_shell_resolution_divisor = 2
	far_edge = 15000
	_ensure_spectrum()
	water_material = ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	material = water_material
	_apply_spectrum()
	_apply_shore_patches()
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
		var camera_xz := Vector2(camera.global_position.x, camera.global_position.z)
		if camera_xz.distance_squared_to(_last_shore_anchor) > 625.0:
			_refresh_shore_patches(camera_xz)

func set_simulation_time(value: float) -> void:
	externally_clocked = true
	simulation_time = value

func configure(seed_value: int) -> void:
	world_seed = seed_value
	_waves.clear()
	_wave_info.clear()
	_group_info.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var phases: Array[float] = []
	for index in WAVES.size():
		var template: Vector4 = WAVES[index]
		var angle := atan2(template.y, template.x) + rng.randf_range(-0.35 if index < 3 else -0.55, 0.35 if index < 3 else 0.55)
		var direction := Vector2(cos(angle), sin(angle))
		var amplitude := template.z * rng.randf_range(0.83, 1.17)
		var wavelength := template.w * rng.randf_range(0.82, 1.19)
		_waves.append(Vector4(direction.x, direction.y, amplitude, wavelength))
		var k := TAU / wavelength
		_wave_info.append(Vector4(direction.x, direction.y, k, sqrt(9.81 * k)))
		phases.append(rng.randf_range(-PI, PI))
	_wave_phases = Vector4(phases[0], phases[1], phases[2], phases[3])
	_wave_tail_phases = Vector2(phases[4], phases[5])
	for interval in [Vector2(85.0, 135.0), Vector2(160.0, 245.0), Vector2(52.0, 86.0)]:
		var angle := rng.randf_range(-PI, PI)
		var direction := Vector2(cos(angle), sin(angle))
		var k := TAU / rng.randf_range(interval.x, interval.y)
		_group_info.append(Vector4(direction.x, direction.y, k, sqrt(9.81 * k) * 0.5))
	_group_phases = Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))
	_foam_seed_offset = Vector2(rng.randf_range(-100.0, 100.0), rng.randf_range(-100.0, 100.0))
	_apply_spectrum()

func _ensure_spectrum() -> void:
	if _waves.is_empty():
		configure(world_seed)

func _apply_spectrum() -> void:
	if water_material == null:
		return
	for i in _waves.size():
		water_material.set_shader_parameter("wave_%d" % i, _waves[i])
		water_material.set_shader_parameter("wave_%d_info" % i, _wave_info[i])
	water_material.set_shader_parameter("wave_phases", _wave_phases)
	water_material.set_shader_parameter("wave_tail_phases", _wave_tail_phases)
	water_material.set_shader_parameter("group_0_info", _group_info[0])
	water_material.set_shader_parameter("group_1_info", _group_info[1])
	water_material.set_shader_parameter("group_2_info", _group_info[2])
	water_material.set_shader_parameter("group_phases", _group_phases)
	water_material.set_shader_parameter("foam_seed_offset", _foam_seed_offset)

func _group_phase(index: int, q: Vector2, at_time: float) -> float:
	var info: Vector4 = _group_info[index]
	return info.z * (info.x * q.x + info.y * q.y) - info.w * at_time + _group_phases[index]

func _group_factor(q: Vector2, at_time: float) -> float:
	var result := 0.93
	for i in _group_info.size():
		result += GROUP_STRENGTH[i] * sin(_group_phase(i, q, at_time))
	return result

func _group_with_gradient(q: Vector2, at_time: float) -> Vector3:
	var result := Vector3(0.93, 0.0, 0.0)
	for i in _group_info.size():
		var info: Vector4 = _group_info[i]
		var strength: float = GROUP_STRENGTH[i]
		var phase := _group_phase(i, q, at_time)
		result.x += strength * sin(phase)
		var slope := strength * cos(phase) * info.z
		result.y += slope * info.x
		result.z += slope * info.y
	return result

func _displacement(q: Vector2, at_time: float) -> Vector3:
	_ensure_spectrum()
	var result := Vector3.ZERO
	for i in _waves.size():
		var wave: Vector4 = _waves[i]
		var info: Vector4 = _wave_info[i]
		var phase_offset: float = _wave_phases[i] if i < 4 else _wave_tail_phases[i-4]
		var phase := info.z * (info.x * q.x + info.y * q.y) - info.w * at_time + phase_offset
		result += Vector3(info.x * wave.z * 0.68 * cos(phase), wave.z * sin(phase), info.y * wave.z * 0.68 * cos(phase))
	return result * _group_factor(q, at_time)

func _inverse_horizontal(point: Vector3, at_time: float) -> Vector2:
	var target := Vector2(point.x, point.z)
	var q := target
	# Invert the horizontal Gerstner shift; sampling undeformed XZ is incorrect.
	for i in 5:
		var shift := _displacement(q, at_time)
		q = target - Vector2(shift.x, shift.z)
	return q

func sample_height(point: Vector3, at_time: float = -1.0) -> float:
	var t := simulation_time if at_time < 0.0 else at_time
	var q := _inverse_horizontal(point, t)
	return _displacement(q, t).y

func sample_normal(point: Vector3, at_time: float = -1.0) -> Vector3:
	var t := simulation_time if at_time < 0.0 else at_time
	var q := _inverse_horizontal(point, t)
	var displacement := Vector3.ZERO
	var tangent_x := Vector3.ZERO
	var tangent_z := Vector3.ZERO
	for i in _waves.size():
		var wave: Vector4 = _waves[i]
		var info: Vector4 = _wave_info[i]
		var phase_offset: float = _wave_phases[i] if i < 4 else _wave_tail_phases[i-4]
		var phase := info.z * (info.x * q.x + info.y * q.y) - info.w * t + phase_offset
		var sine := sin(phase)
		var cosine := cos(phase)
		displacement += Vector3(info.x * wave.z * 0.68 * cosine, wave.z * sine, info.y * wave.z * 0.68 * cosine)
		var lateral := -wave.z * 0.68 * info.z * sine
		var vertical := wave.z * info.z * cosine
		var derivative := Vector3(info.x * lateral, vertical, info.y * lateral)
		tangent_x += derivative * info.x
		tangent_z += derivative * info.y
	var group := _group_with_gradient(q, t)
	tangent_x = Vector3.RIGHT + tangent_x * group.x + displacement * group.y
	tangent_z = Vector3.BACK + tangent_z * group.x + displacement * group.z
	return tangent_z.cross(tangent_x).normalized()

func sample_velocity(point: Vector3, at_time: float = -1.0) -> Vector3:
	var t := simulation_time if at_time < 0.0 else at_time
	var q := _inverse_horizontal(point, t)
	return (_displacement(q, t + 0.025) - _displacement(q, t - 0.025)) / 0.05

func set_shore_data(heightmap: Texture2D, origin: Vector2, map_size: Vector2) -> void:
	water_material.set_shader_parameter("seabed_height", heightmap)
	water_material.set_shader_parameter("seabed_origin", origin)
	water_material.set_shader_parameter("seabed_size", map_size)
	water_material.set_shader_parameter("has_seabed", true)

func set_shore_patches(patches: Array) -> void:
	_shore_sources.clear()
	for patch in patches:
		if not patch is Dictionary:
			continue
		if patch.get("sky", false):
			continue
		var center: Vector3 = patch.get("center", Vector3.ZERO)
		var radius: float = float(patch.get("radius", 0.0))
		var height: float = float(patch.get("height", 0.0))
		if not center.is_finite() or not is_finite(radius) or radius <= 0.0 or not is_finite(height):
			continue
		_shore_sources.append(Vector4(center.x, center.z, radius, height))
	_last_shore_anchor = Vector2(INF, INF)
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var anchor := Vector2(camera.global_position.x, camera.global_position.z) if camera else Vector2.ZERO
	_refresh_shore_patches(anchor)

func _refresh_shore_patches(anchor: Vector2) -> void:
	var nearest: Array[Vector4] = []
	var distances: Array[float] = []
	for patch in _shore_sources:
		var distance_value := maxf(0.0, Vector2(patch.x, patch.y).distance_to(anchor) - patch.z)
		var index := 0
		while index < nearest.size() and distances[index] <= distance_value:
			index += 1
		if index >= 8:
			continue
		nearest.insert(index, patch)
		distances.insert(index, distance_value)
		if nearest.size() > 8:
			nearest.resize(8)
			distances.resize(8)
	_shore_patches = nearest
	_last_shore_anchor = anchor
	_apply_shore_patches()

func _apply_shore_patches() -> void:
	if water_material == null:
		return
	var values: Array[Vector4] = []
	for i in 8:
		values.append(_shore_patches[i] if i < _shore_patches.size() else Vector4.ZERO)
	water_material.set_shader_parameter("shore_patches", values)
	water_material.set_shader_parameter("shore_patch_count", _shore_patches.size())

func set_ship_wakes(wakes: Array) -> void:
	if not water_material:
		return
	var values: Array[Vector4]=[]
	for i in 6:
		values.append(wakes[i] if i<wakes.size() else Vector4.ZERO)
	water_material.set_shader_parameter("ship_wakes",values)
	water_material.set_shader_parameter("wake_count",mini(wakes.size(),6))
