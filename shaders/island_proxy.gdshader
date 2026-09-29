shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.55, 0.65, 0.36);

float island_profile(float radius, float shelf_fraction) {
	float inland = pow(max(0.0, 1.0 - radius), 0.62);
	float shelf = (1.0 - smoothstep(0.87, 1.20, radius)) * shelf_fraction - 0.9 * shelf_fraction;
	return inland + shelf;
}

void vertex() {
	float radius = length(VERTEX.xz);
	float angle = atan(VERTEX.z, VERTEX.x);
	float phase = INSTANCE_CUSTOM.x * 6.2831853 - 3.1415927;
	float perimeter = 1.0 + sin(angle * 5.0 + phase) * 0.082 + cos(angle * 8.0 - phase) * 0.045;
	float shelf_fraction = INSTANCE_CUSTOM.y;
	VERTEX.xz *= perimeter;
	VERTEX.y = island_profile(radius, shelf_fraction);
	float slope = (island_profile(min(radius + 0.02, 1.2), shelf_fraction) - island_profile(max(radius - 0.02, 0.0), shelf_fraction)) / 0.04;
	NORMAL = normalize(vec3(-cos(angle) * slope, 1.0, -sin(angle) * slope));
}

void fragment() {
	ALBEDO = base_color;
	ROUGHNESS = 1.0;
}
