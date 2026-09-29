// Gerstner displacement adapted from Boujie Water Shader (MIT; see addons/PROVENANCE.md).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float ocean_time = 0.0;
uniform vec4 wave_0 = vec4(0.88, 0.48, 0.35, 31.0);
uniform vec4 wave_1 = vec4(-0.42, 0.91, 0.29, 20.5);
uniform vec4 wave_2 = vec4(0.98, -0.2, 0.23, 13.2);
uniform vec4 wave_3 = vec4(0.4, 0.92, 0.14, 8.1);
uniform vec4 wave_4 = vec4(-0.73, -0.68, 0.08, 5.0);
uniform vec4 wave_5 = vec4(0.24, -0.97, 0.035, 3.0);
// Normalized direction, wave number and angular speed, shared with CPU sampling.
uniform vec4 wave_0_info;
uniform vec4 wave_1_info;
uniform vec4 wave_2_info;
uniform vec4 wave_3_info;
uniform vec4 wave_4_info;
uniform vec4 wave_5_info;
uniform vec4 wave_phases;
uniform vec2 wave_tail_phases;
// Three crossing, long-period envelopes make broad calm and choppy patches.
uniform vec4 group_0_info;
uniform vec4 group_1_info;
uniform vec4 group_2_info;
uniform vec3 group_phases;
uniform vec2 foam_seed_offset;
uniform vec3 deep_color : source_color = vec3(0.025, 0.255, 0.58);
uniform vec3 middle_color : source_color = vec3(0.025, 0.42, 0.73);
uniform vec3 shallow_color : source_color = vec3(0.07, 0.66, 0.70);
uniform vec3 foam_color : source_color = vec3(0.97, 0.975, 0.88);
uniform sampler2D seabed_height : filter_linear, repeat_disable;
uniform vec2 seabed_origin = vec2(-512.0);
uniform vec2 seabed_size = vec2(1024.0);
uniform bool has_seabed = false;
uniform vec4 shore_patches[8]; // Eight nearest islands: world X/Z, radius, height.
uniform int shore_patch_count = 0;
uniform vec4 ship_wakes[6]; // world X, world Z, heading radians, speed m/s
uniform int wake_count = 0;
varying vec3 world_pos;
varying vec2 base_xz;

// Columns: displacement, d(displacement)/dx, d(displacement)/dz.
mat3 wave_sample(vec2 q, vec4 w, vec4 info, float phase_offset, float amount) {
	float f=info.z*dot(info.xy,q)-info.w*ocean_time+phase_offset;
	float s=sin(f);
	float c=cos(f);
	float amplitude=w.z*amount;
	float lateral=-amplitude*0.68*info.z*s;
	float vertical=amplitude*info.z*c;
	return mat3(
		vec3(info.x*amplitude*0.68*c,amplitude*s,info.y*amplitude*0.68*c),
		vec3(info.x*info.x*lateral,info.x*vertical,info.y*info.x*lateral),
		vec3(info.x*info.y*lateral,info.y*vertical,info.y*info.y*lateral)
	);
}
float pixel_filter(float wave_number, float footprint) {
	return 1.0-smoothstep(0.7,2.15,wave_number*footprint);
}
float mesh_filter(float wavelength, float camera_distance) {
	return 1.0-smoothstep(wavelength*24.0,wavelength*43.0,camera_distance);
}
mat3 surface_waves(vec2 q, float footprint, float camera_distance, bool mesh_stage) {
	float a0=mesh_stage?mesh_filter(wave_0.w,camera_distance):pixel_filter(wave_0_info.z,footprint);
	float a1=mesh_stage?mesh_filter(wave_1.w,camera_distance):pixel_filter(wave_1_info.z,footprint);
	float a2=mesh_stage?mesh_filter(wave_2.w,camera_distance):pixel_filter(wave_2_info.z,footprint);
	float a3=mesh_stage?mesh_filter(wave_3.w,camera_distance):pixel_filter(wave_3_info.z,footprint);
	float a4=mesh_stage?mesh_filter(wave_4.w,camera_distance):pixel_filter(wave_4_info.z,footprint);
	float a5=mesh_stage?mesh_filter(wave_5.w,camera_distance):pixel_filter(wave_5_info.z,footprint);
	return wave_sample(q,wave_0,wave_0_info,wave_phases.x,a0)+
		wave_sample(q,wave_1,wave_1_info,wave_phases.y,a1)+
		wave_sample(q,wave_2,wave_2_info,wave_phases.z,a2)+
		wave_sample(q,wave_3,wave_3_info,wave_phases.w,a3)+
		wave_sample(q,wave_4,wave_4_info,wave_tail_phases.x,a4)+
		wave_sample(q,wave_5,wave_5_info,wave_tail_phases.y,a5);
}
// X is envelope, Y/Z are spatial derivatives for exact Gerstner tangents.
vec3 grouping(vec2 q) {
	float f0=group_0_info.z*dot(group_0_info.xy,q)-group_0_info.w*ocean_time+group_phases.x;
	float f1=group_1_info.z*dot(group_1_info.xy,q)-group_1_info.w*ocean_time+group_phases.y;
	float f2=group_2_info.z*dot(group_2_info.xy,q)-group_2_info.w*ocean_time+group_phases.z;
	vec2 slopes=0.11*cos(f0)*group_0_info.z*group_0_info.xy+
		0.08*cos(f1)*group_1_info.z*group_1_info.xy+
		0.07*cos(f2)*group_2_info.z*group_2_info.xy;
	return vec3(0.93+0.11*sin(f0)+0.08*sin(f1)+0.07*sin(f2),slopes);
}
float hash(vec2 q) { return fract(sin(dot(q,vec2(127.1,311.7))) * 43758.5453123); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),u.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),u.x),u.y);
}
float foam_field(vec2 p) {
	mat2 turn=mat2(vec2(0.8,-0.6),vec2(0.6,0.8));
	return noise(p)*0.47+noise(turn*p*2.13+18.4)*0.34+noise(p*3.71-7.1)*0.19;
}
void vertex() {
	vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	vec2 q=p.xz;
	float camera_distance=length(q-CAMERA_POSITION_WORLD.xz);
	mat3 waves=surface_waves(q,0.0,camera_distance,true);
	vec3 envelope=grouping(q);
	vec3 shift=waves[0]*envelope.x;
	float far_fade=1.0-smoothstep(900.0,1800.0,camera_distance);
	p += shift*far_fade;
	VERTEX=(inverse(MODEL_MATRIX)*vec4(p,1.0)).xyz;
	vec3 sx=vec3(1.0,0.0,0.0)+waves[1]*envelope.x+waves[0]*envelope.y;
	vec3 sz=vec3(0.0,0.0,1.0)+waves[2]*envelope.x+waves[0]*envelope.z;
	NORMAL=normalize(cross(sz,sx));
	world_pos=p;
	base_xz=q;
}
void fragment() {
	// Grid coordinates interpolate exactly even where distant mesh vertices cannot
	// resolve the short waves. Evaluate shading at each pixel, then band-limit it.
	vec2 q=base_xz;
	// A smooth footprint avoids derivative jumps where coarse LOD triangles meet.
	vec3 camera_delta=CAMERA_POSITION_WORLD-vec3(q.x,0.0,q.y);
	float camera_distance=length(camera_delta);
	float view_slope=clamp(abs(camera_delta.y)/max(camera_distance,0.001),0.18,1.0);
	float footprint=clamp(camera_distance*0.00155/sqrt(view_slope),0.002,8.0);
	mat3 waves=surface_waves(q,footprint,0.0,false);
	vec3 envelope=grouping(q);
	float geometry_fade=1.0-smoothstep(900.0,1800.0,length(q-CAMERA_POSITION_WORLD.xz));
	vec3 shift=waves[0]*envelope.x*geometry_fade;
	vec3 sx=vec3(1.0,0.0,0.0)+waves[1]*envelope.x+waves[0]*envelope.y;
	vec3 sz=vec3(0.0,0.0,1.0)+waves[2]*envelope.x+waves[0]*envelope.z;
	vec3 n=normalize(mix(vec3(0.0,1.0,0.0),normalize(cross(sz,sx)),geometry_fade));
	vec2 p=q+shift.xz;
	float surface_height=shift.y;
	float depth=30.0;
	if(has_seabed){
		vec2 uv=(p-seabed_origin)/seabed_size;
		if(all(greaterThanEqual(uv,vec2(0)))&&all(lessThanEqual(uv,vec2(1)))) depth=max(0.0,world_pos.y-texture(seabed_height,uv).r);
	}
	for(int i=0;i<8;i++){
		if(i>=shore_patch_count){break;}
		vec4 island=shore_patches[i];
		float edge_distance=length(p-island.xy)-island.z;
		float shelf=clamp(14.0+island.w*0.32,18.0,34.0);
		if(edge_distance<shelf*1.8){
			float local_depth=max(0.0,edge_distance)*30.0/shelf;
			depth=min(depth,mix(local_depth,30.0,smoothstep(shelf,shelf*1.8,edge_distance)));
		}
	}
	vec2 drift=p+vec2(ocean_time*0.16,-ocean_time*0.10);
	float broad=noise(p*0.21+foam_seed_offset*0.37+vec2(ocean_time*0.005,0.0));
	float field=foam_field(drift*1.25+foam_seed_offset);
	float foam_edge_width=clamp(0.009+footprint*0.05,0.009,0.12);
	float contour=abs(field-(0.50+0.06*(broad-0.5)));
	float lace=1.0-smoothstep(0.012,0.012+foam_edge_width,contour);
	float gaps=smoothstep(0.28,0.58,noise(p*0.57+foam_seed_offset*0.19));
	float flecks=smoothstep(0.72,0.84,noise(drift*2.65-foam_seed_offset*0.27))*(1.0-smoothstep(0.3,0.8,footprint));
	float broken=smoothstep(0.36,0.63,broad);
	float compression=max(0.0,1.0-(sx.x*sz.z-sx.z*sz.x));
	float crest_gate=smoothstep(0.015,0.17,compression+surface_height*0.08+(broad-0.5)*0.10);
	float shore=(1.0-smoothstep(0.4,3.0,depth))*smoothstep(0.32,0.58,field);
	float foam=clamp(max(crest_gate*(0.86*lace*gaps+0.17*flecks)*(0.55+0.45*broken),shore*(0.55+0.45*lace)),0.0,1.0);
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
		float bow=(1.0-smoothstep(0.05,0.38,abs(hull-1.0)))*(0.45+0.55*smoothstep(0.5,5.0,speed))*(0.65+0.35*lace);
		wake_foam=max(wake_foam,max(v_shape,bow)*(0.60+0.40*broken));
	}
	foam=max(foam,wake_foam);
	float mottling=broad+field*0.4;
	vec3 v=normalize(CAMERA_POSITION_WORLD-world_pos);
	vec3 sea=mix(deep_color*0.66,middle_color,clamp(surface_height*0.55+mottling*0.27+0.20,0.0,1.0));
	sea*=0.77+max(dot(n,normalize(vec3(-0.4,0.82,0.4))),0.0)*0.38;
	sea=mix(sea,shallow_color,(1.0-smoothstep(1.0,15.0,depth))*0.80);
	float sun_glint=pow(max(dot(reflect(-normalize(vec3(-0.4,0.82,0.4)),n),v),0.0),110.0);
	float fresnel=pow(1.0-max(dot(n,v),0.0),3.0);
	sea+=vec3(0.60,0.82,0.85)*sun_glint*0.55+vec3(0.035,0.08,0.12)*fresnel;
	float foam_distance=1.0-smoothstep(170.0,850.0,length(world_pos-CAMERA_POSITION_WORLD));
	ALBEDO=mix(sea,foam_color,clamp(foam*(0.72+0.28*foam_distance),0.0,1.0));
	ROUGHNESS=mix(0.56,0.96,foam);
	SPECULAR=0.12;
	METALLIC=0.0;
	NORMAL=normalize((VIEW_MATRIX*vec4(n,0.0)).xyz);
	EMISSION=vec3(0.0);
}
