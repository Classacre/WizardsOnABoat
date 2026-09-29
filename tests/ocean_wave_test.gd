extends SceneTree

const OceanScript = preload("res://scripts/world/ocean.gd")
const WaterShader = preload("res://shaders/ocean.gdshader")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _shader_displacement(material: ShaderMaterial, q: Vector2, at_time: float) -> Vector3:
	var result := Vector3.ZERO
	var phases: Vector4 = material.get_shader_parameter("wave_phases")
	var tail_phases: Vector2 = material.get_shader_parameter("wave_tail_phases")
	for i in 6:
		var wave: Vector4 = material.get_shader_parameter("wave_%d" % i)
		var info: Vector4 = material.get_shader_parameter("wave_%d_info" % i)
		var phase_offset: float = phases[i] if i < 4 else tail_phases[i-4]
		var phase: float = info.z * (info.x * q.x + info.y * q.y) - info.w * at_time + phase_offset
		result += Vector3(info.x * wave.z * 0.68 * cos(phase), wave.z * sin(phase), info.y * wave.z * 0.68 * cos(phase))
	var group_phases: Vector3 = material.get_shader_parameter("group_phases")
	var grouping := 0.93
	for i in 3:
		var info: Vector4 = material.get_shader_parameter("group_%d_info" % i)
		var phase: float = info.z * (info.x * q.x + info.y * q.y) - info.w * at_time + group_phases[i]
		grouping += Vector3(0.11,0.08,0.07)[i] * sin(phase)
	return result * grouping

func _run() -> void:
	var first = OceanScript.new()
	var repeat = OceanScript.new()
	var other = OceanScript.new()
	first.configure(7319)
	repeat.configure(7319)
	other.configure(9182)
	var material := ShaderMaterial.new()
	material.shader = WaterShader
	first.water_material = material
	first.configure(7319) # Configuring after a material exists updates render uniforms.
	check(first._waves.size() == 6 and first._waves == repeat._waves and first._wave_info == repeat._wave_info and first._wave_tail_phases == repeat._wave_tail_phases,"Same seed reproduces all six wave components")
	check(first._group_info == repeat._group_info and first._group_phases == repeat._group_phases,"Same seed reproduces broad wave groups")
	check(first._waves != other._waves and first._foam_seed_offset != other._foam_seed_offset,"Different seeds alter waves and foam placement")
	var diverse_directions := 0
	for i in first._waves.size():
		for j in range(i+1,first._waves.size()):
			if absf(Vector2(first._waves[i].x,first._waves[i].y).dot(Vector2(first._waves[j].x,first._waves[j].y))) < 0.45:
				diverse_directions += 1
	check(diverse_directions >= 3,"Seeded waves include several crossing directions")
	var largest_difference := 0.0
	var group_min := INF
	var group_max := -INF
	for at_time in [0.0, 17.8, 132.6]:
		for index in 80:
			var q := Vector2(index * 3.41 - 96.0, index * -2.87 + 62.0)
			var displacement: Vector3 = first._displacement(q, at_time)
			var actual := Vector3(q.x + displacement.x, 0.0, q.y + displacement.z)
			check(absf(first.sample_height(actual, at_time) - displacement.y) < 0.001,"Horizontal inversion matches displaced surface")
			check(displacement.distance_to(_shader_displacement(material, q, at_time)) < 0.0001,"CPU displacement matches shader uniforms")
			check(absf(first.sample_height(actual, at_time) - repeat.sample_height(actual, at_time)) < 0.000001,"Peers with the same seed and time sample identical height")
			largest_difference = maxf(largest_difference, absf(first.sample_height(actual, at_time) - other.sample_height(actual, at_time)))
			var envelope: float = first._group_factor(q, at_time)
			group_min = minf(group_min, envelope)
			group_max = maxf(group_max, envelope)
			if index % 7 == 0:
				var normal: Vector3 = first.sample_normal(actual, at_time)
				var eps := 0.04
				var dx: float = (first.sample_height(actual + Vector3(eps,0,0), at_time) - first.sample_height(actual - Vector3(eps,0,0), at_time)) / (2.0 * eps)
				var dz: float = (first.sample_height(actual + Vector3(0,0,eps), at_time) - first.sample_height(actual - Vector3(0,0,eps), at_time)) / (2.0 * eps)
				check(normal.dot(Vector3(-dx,1.0,-dz).normalized()) > 0.998,"Analytic grouped-wave normal matches numerical surface slope")
	check(largest_difference > 0.1,"Different seeds produce visibly distinct sea heights")
	check(group_max - group_min > 0.16,"Crossing low-frequency groups create varied calm and choppy patches")
	first.set_shore_patches([
		{"center":Vector3(1200,0,-800),"radius":80.0,"height":30.0,"sky":false},
		{"center":Vector3(500,80,300),"radius":30.0,"height":15.0,"sky":true},
	])
	check(first._shore_patches.size() == 1 and int(material.get_shader_parameter("shore_patch_count")) == 1,"Shore patches are bounded and skip sky islands")
	var many_patches: Array = []
	for index in 12:
		many_patches.append({"center":Vector3(index * 100.0,0,0),"radius":35.0,"height":24.0,"sky":false})
	first.set_shore_patches(many_patches)
	check(first._shore_sources.size() == 12 and first._shore_patches.size() == 8,"Ocean retains all island records but uploads only eight nearby shore patches")
	first._refresh_shore_patches(Vector2(1100,0))
	check(absf(first._shore_patches[0].x - 1100.0) < 0.01,"Distant voyages select their nearby island shoreline")
	first.free()
	repeat.free()
	other.free()
	print("OCEAN_WAVE_TEST failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
