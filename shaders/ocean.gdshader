// Gerstner displacement adapted from Boujie Water Shader (MIT; see addons/PROVENANCE.md).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float ocean_time = 0.0;
uniform vec4 wave_0 = vec4(0.88, 0.48, 0.38, 21.0);
uniform vec4 wave_1 = vec4(-0.42, 0.91, 0.22, 11.5);
uniform vec4 wave_2 = vec4(0.98, -0.2, 0.13, 5.8);
uniform vec4 wave_3 = vec4(0.4, 0.92, 0.075, 2.7);
uniform vec3 deep_color : source_color = vec3(0.025, 0.255, 0.58);
uniform vec3 middle_color : source_color = vec3(0.025, 0.42, 0.73);
uniform vec3 shallow_color : source_color = vec3(0.07, 0.66, 0.70);
uniform vec3 foam_color : source_color = vec3(0.97, 0.975, 0.88);
uniform sampler2D seabed_height : filter_linear, repeat_disable;
uniform vec2 seabed_origin = vec2(-512.0);
uniform vec2 seabed_size = vec2(1024.0);
uniform bool has_seabed = false;
uniform sampler2D foam_pattern : filter_linear_mipmap, repeat_enable;
uniform vec4 ship_wakes[6]; // world X, world Z, heading radians, speed m/s
uniform int wake_count = 0;
varying vec3 world_pos;
varying float crest;
varying vec3 world_normal;

vec3 wave(vec2 q, vec4 w) {
	vec2 d = normalize(w.xy);
	float k = 6.2831853 / w.w;
	float f = k * dot(d, q) - sqrt(9.81 * k) * ocean_time;
	return vec3(d.x * w.z * 0.68 * cos(f), w.z * sin(f), d.y * w.z * 0.68 * cos(f));
}
vec3 surface(vec2 q) { return wave(q,wave_0)+wave(q,wave_1)+wave(q,wave_2)+wave(q,wave_3); }
vec3 slope_wave(vec2 q, vec4 w) {
	vec2 d=normalize(w.xy);
	float k=6.2831853/w.w;
	float f=k*dot(d,q)-sqrt(9.81*k)*ocean_time;
	return vec3(d.x*k*w.z*cos(f),0.0,d.y*k*w.z*cos(f));
}
float hash(vec2 q) { return fract(sin(dot(q,vec2(127.1,311.7))) * 43758.5453123); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),u.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),u.x),u.y);
}
float foam_field(vec2 p) {
	mat2 turn=mat2(vec2(0.8,-0.6),vec2(0.6,0.8));
	return noise(p)*0.55+noise(turn*p*2.13+18.4)*0.29+noise(turn*p*4.27-7.1)*0.16;
}
void vertex() {
	vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	vec2 q=p.xz;
	vec3 shift=surface(q);
	float far_fade=1.0-smoothstep(900.0,1800.0,length(p.xz-CAMERA_POSITION_WORLD.xz));
	p += shift*far_fade;
	VERTEX=(inverse(MODEL_MATRIX)*vec4(p,1.0)).xyz;
	vec3 sx=vec3(0.12,0,0)+surface(q+vec2(0.12,0))-shift;
	vec3 sz=vec3(0,0,0.12)+surface(q+vec2(0,0.12))-shift;
	world_normal=normalize(cross(sz,sx));
	NORMAL=world_normal;
	world_pos=p;
	crest=shift.y;
}
void fragment() {
	vec2 p=world_pos.xz;
	float surface_height=surface(p).y;
	float depth=30.0;
	if(has_seabed){
		vec2 uv=(p-seabed_origin)/seabed_size;
		if(all(greaterThanEqual(uv,vec2(0)))&&all(lessThanEqual(uv,vec2(1)))) depth=max(0.0,world_pos.y-texture(seabed_height,uv).r);
	}
	float distance_fade=1.0-smoothstep(170.0,850.0,length(world_pos-CAMERA_POSITION_WORLD));
	vec2 drift=p*0.63+vec2(ocean_time*0.18,-ocean_time*0.11);
	drift+=vec2(noise(p*0.43+ocean_time*0.035),noise(p*0.47-8.0))*1.5;
	float field=foam_field(drift);
	// A warped multiscale level set makes organic branching lace, never polygon cells.
	float lace=1.0-smoothstep(0.023,0.066,abs(field-0.52));
	float broken=smoothstep(0.20,0.62,noise(p*0.36+vec2(ocean_time*0.10,0)));
	float texture_foam=texture(foam_pattern,p*0.043+vec2(ocean_time*0.0015,-ocean_time*0.0009)).r;
	float crest_foam=smoothstep(-0.28,0.32,surface_height+noise(p*0.28)*0.20)*texture_foam;
	float fine_lace=smoothstep(0.74,0.88,noise(drift*3.2))*0.08;
	float shore=(1.0-smoothstep(0.4,3.0,depth))*smoothstep(0.1,0.5,noise(p*0.8+ocean_time*0.23));
	float foam=clamp(max(crest_foam+fine_lace,shore*(0.45+texture_foam)),0.0,1.0);
	float wake_foam=0.0;
	for(int i=0;i<6;i++){
		if(i>=wake_count){break;}
		vec4 ship=ship_wakes[i];
		vec2 tail=vec2(sin(ship.z),cos(ship.z));
		vec2 side=vec2(tail.y,-tail.x);
		vec2 delta=p-ship.xy;
		float behind=dot(delta,tail);
		float lateral=abs(dot(delta,side));
		float speed=clamp(abs(ship.w),0.0,18.0);
		float wake_width=1.7+max(0.0,behind)*0.19;
		float rough_edge=(noise(p*1.8+ocean_time*0.13)-0.5)*0.65;
		float v_shape=(1.0-smoothstep(0.12,0.72,abs(lateral-wake_width)+rough_edge));
		v_shape*=smoothstep(1.5,5.0,behind)*(1.0-smoothstep(12.0,20.0+speed*1.2,behind));
		v_shape*=smoothstep(0.5,4.0,speed)*(0.55+0.45*lace);
		float hull=length(vec2(lateral/3.6,behind/6.9));
		float bow=(1.0-smoothstep(0.05,0.38,abs(hull-1.0)))*(0.45+0.55*smoothstep(0.5,5.0,speed))*(0.5+texture_foam);
		wake_foam=max(wake_foam,max(v_shape,bow)*(0.60+0.40*broken));
	}
	foam=max(foam,wake_foam);
	float mottling=noise(p*0.34)+noise(p*0.83)*0.4;
	vec3 slope=slope_wave(p,wave_0)+slope_wave(p,wave_1)+slope_wave(p,wave_2)+slope_wave(p,wave_3);
	vec3 n=normalize(vec3(-slope.x,1.0,-slope.z));
	vec3 v=normalize(CAMERA_POSITION_WORLD-world_pos);
	vec3 sea=mix(deep_color*0.66,middle_color,clamp(surface_height*0.85+mottling*0.25+0.15,0.0,1.0));
	sea*=0.84+max(dot(n,normalize(vec3(-0.4,0.82,0.4))),0.0)*0.25;
	sea=mix(sea,shallow_color,(1.0-smoothstep(1.0,15.0,depth))*0.80);
	float sun_glint=pow(max(dot(reflect(-normalize(vec3(-0.4,0.82,0.4)),n),v),0.0),170.0);
	sea+=vec3(0.60,0.82,0.85)*sun_glint*0.6;
	ALBEDO=mix(sea,foam_color,clamp(foam*(0.72+0.28*distance_fade),0.0,1.0));
	ROUGHNESS=mix(0.56,0.96,foam);
	SPECULAR=0.12;
	METALLIC=0.0;
	vec3 ripple=vec3(sin(p.x*4.2+ocean_time)*0.035,0.0,cos(p.y*3.7-ocean_time*1.4)*0.035)*distance_fade;
	NORMAL=normalize((VIEW_MATRIX*vec4(normalize(vec3(-slope.x,1.0,-slope.z)+ripple),0.0)).xyz);
	EMISSION=vec3(0.0);
}
