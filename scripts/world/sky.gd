class_name GreatSeaSky
extends Node3D

const SKY_SHADER=preload("res://shaders/sky.gdshader")
var environment_node: WorldEnvironment
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var time_of_day: float=12.0
var _seconds:=0.0
var _daylight := -1.0

func _ready() -> void:
	var sky:=Sky.new()
	sky.radiance_size=Sky.RADIANCE_SIZE_128
	sky.process_mode=Sky.PROCESS_MODE_INCREMENTAL
	sky_material=ShaderMaterial.new()
	sky_material.shader=SKY_SHADER
	if ResourceLoader.exists("res://assets/textures/cloud-sky.png"):
		sky_material.set_shader_parameter("cloud_panorama",load("res://assets/textures/cloud-sky.png"))
		sky_material.set_shader_parameter("has_panorama",true)
	sky.sky_material=sky_material
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_SKY
	environment.sky=sky
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("9dbdcc")
	environment.ambient_light_energy=0.28
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode=Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure=1.0
	environment.fog_enabled=true
	environment.fog_light_color=Color("81bdcf")
	environment.fog_light_energy=0.8
	environment.fog_density=0.0009
	environment.fog_sky_affect=0.04
	environment.ssao_enabled=true
	environment.ssao_radius=1.3
	environment.ssao_intensity=1.3
	environment.glow_enabled=true
	environment.glow_intensity=0.65
	environment_node=WorldEnvironment.new()
	environment_node.name="GreatSeaEnvironment"
	environment_node.environment=environment
	add_child(environment_node)
	sun=DirectionalLight3D.new()
	sun.name="WarmNoonSun"
	sun.rotation_degrees=Vector3(-48,-32,0)
	sun.light_color=Color("fff1cb")
	sun.light_energy=1.18
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=190.0
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias=0.04
	sun.shadow_normal_bias=1.3
	add_child(sun)

func _process(delta: float) -> void:
	_seconds+=delta
	if sky_material and _daylight < 0.999 and int(_seconds / 3.0) != int((_seconds-delta) / 3.0):
		sky_material.set_shader_parameter("cloud_time",_seconds)

func set_underwater(underwater: bool, depth:=0.0) -> void:
	if not environment_node:
		return
	var environment:=environment_node.environment
	var density: float=lerpf(0.037,0.095,clampf(depth/35.0,0,1)) if underwater else 0.0009
	var fog_color:=Color("166b86") if underwater else Color("81bdcf")
	var ambient: float=0.48 if underwater else 0.28
	if not is_equal_approx(environment.fog_density,density): environment.fog_density=density
	if environment.fog_light_color!=fog_color: environment.fog_light_color=fog_color
	if not is_equal_approx(environment.ambient_light_energy,ambient): environment.ambient_light_energy=ambient

func set_time_of_day(hour: float) -> void:
	time_of_day=fposmod(hour,24.0)
	if not sun or not environment_node:
		return
	var daylight:=smoothstep(5.0,8.0,time_of_day)*(1.0-smoothstep(17.0,20.0,time_of_day))
	if not is_equal_approx(daylight,_daylight):
		sun.light_energy=lerpf(0.16,1.18,daylight)
		sun.light_color=Color("749bcc").lerp(Color("fff1cb"),daylight)
		sky_material.set_shader_parameter("zenith_color",Color("082343").lerp(Color("1975d6"),daylight))
		sky_material.set_shader_parameter("horizon_color",Color("1d4463").lerp(Color("8ccfea"),daylight))
		sky_material.set_shader_parameter("panorama_strength",daylight)
		_daylight=daylight
	sun.rotation_degrees.x=-maxf(16.0,sin((time_of_day-6.0)/12.0*PI)*48.0)
