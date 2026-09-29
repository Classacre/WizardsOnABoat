shader_type sky;
uniform sampler2D cloud_panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_panorama = false;
uniform float panorama_strength = 1.0;
uniform vec3 zenith_color : source_color = vec3(0.10,0.46,0.84);
uniform vec3 horizon_color : source_color = vec3(0.55,0.81,0.92);
uniform vec3 cloud_color : source_color = vec3(1.0,0.97,0.85);
uniform vec3 cloud_shadow : source_color = vec3(0.58,0.75,0.80);
uniform float cloud_time = 0.0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y); }
float fbm(vec2 p) {return noise(p)*0.55+noise(p*2.03+14.0)*0.28+noise(p*4.11+36.0)*0.12+noise(p*8.07)*0.05;}
void sky(){
	vec3 d=normalize(EYEDIR);
	float horizon=pow(max(0.0,1.0-d.y),3.1);
	vec3 base=mix(zenith_color,horizon_color,horizon);
	if(d.y>0.0){
		if(has_panorama && panorama_strength>=0.999){
			vec2 uv=vec2(atan(d.x,d.z)/6.2831853+0.5,acos(clamp(d.y,-1.0,1.0))/3.1415927);
			base=texture(cloud_panorama,uv).rgb;
		}else{
			vec2 p=d.xz/max(0.06,d.y)*0.66+vec2(cloud_time*0.003,0);
			float mass=fbm(p*0.48);
			float detail=fbm(p*2.6+vec2(2.0,8.0));
			float threshold=0.56+smoothstep(0.60,0.97,d.y)*0.09;
			float coverage=smoothstep(threshold-0.04,threshold+0.013,mass+detail*0.11);
			float sculpt=smoothstep(0.28,0.72,detail+mass*0.2);
			vec3 clouds=mix(cloud_shadow,cloud_color,sculpt);
			base=mix(base,clouds,coverage*smoothstep(0.0,0.04,d.y));
			if(has_panorama){
				vec2 uv=vec2(atan(d.x,d.z)/6.2831853+0.5,acos(clamp(d.y,-1.0,1.0))/3.1415927);
				vec3 painted=texture(cloud_panorama,uv).rgb;
				base=mix(base,painted,panorama_strength);
			}
		}
	}
	float sun=max(0.0,dot(d,normalize(vec3(-0.5,0.72,0.38))));
	base+=vec3(1.0,0.82,0.52)*pow(sun,400.0)*0.55;
	COLOR=base;
}
