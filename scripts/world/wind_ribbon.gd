class_name WindRibbon
extends Node3D

var material: ShaderMaterial
var clock := 0.0

func _ready() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float flow = 0.0;
void fragment(){
 float edge=pow(max(0.0,1.0-abs(UV.y*2.0-1.0)),0.55);
 float pulse=0.72+0.28*sin(UV.x*26.0-flow*4.0);
 ALBEDO=vec3(0.45,1.0,0.87);
 EMISSION=vec3(0.36,1.0,0.79)*2.2;
 ALPHA=edge*pulse*(0.75+0.25*sin(UV.x*8.0+flow));
}
"""
	material=ShaderMaterial.new()
	material.shader=shader
	for strand in 4:
		var st:=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 120:
			var points:Array[Vector3]=[]
			for step in [i,i+1]:
				var t:=float(step)/120.0
				var angle:=t*TAU*1.6+float(strand)*0.23
				var radius:=0.12+t*(1.25+strand*0.09)
				var center:=Vector3(cos(angle)*radius,sin(angle)*radius,0)
				var width:=0.025+sin(t*PI)*0.055
				var tangent:=Vector3(-sin(angle),cos(angle),0)
				points.append(center+tangent*width)
				points.append(center-tangent*width)
			for index in [0,1,2,1,3,2]:
				st.set_uv(Vector2(float(i+int(index/2))/120.0,index%2))
				st.add_vertex(points[index]+Vector3(0,0,float(strand)*0.035))
		st.generate_normals()
		var ribbon:=MeshInstance3D.new()
		ribbon.mesh=st.commit()
		ribbon.material_override=material
		ribbon.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ribbon)
	var light:=OmniLight3D.new()
	light.light_color=Color("83ffd9")
	light.light_energy=1.8
	light.omni_range=4
	add_child(light)

func _process(delta:float) -> void:
	clock+=delta
	material.set_shader_parameter("flow",clock)
	var camera:=get_viewport().get_camera_3d()
	if camera: look_at(camera.global_position,Vector3.UP)
