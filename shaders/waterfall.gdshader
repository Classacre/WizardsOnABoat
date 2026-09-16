shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
uniform float speed = 0.35;
uniform vec3 water_color : source_color = vec3(0.29,0.78,0.84);
varying vec3 world_pos;
void vertex(){
	world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	VERTEX.x += sin(VERTEX.y*0.7+TIME*2.0)*0.11;
	VERTEX.z += cos(VERTEX.y*0.51+TIME*2.6)*0.10;
}
void fragment(){
	float flow=sin(UV.x*86.0+sin(UV.y*24.0+TIME*7.0)*1.9);
	float streak=smoothstep(0.1,0.8,flow);
	ALBEDO=mix(water_color,vec3(0.95,0.99,0.91),streak*0.77);
	ROUGHNESS=0.54;
	EMISSION=ALBEDO*0.19;
	ALPHA=0.75+streak*0.21;
}
