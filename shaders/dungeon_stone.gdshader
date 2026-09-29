shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.51, 0.56, 0.53);
uniform bool floor_mode = false;
uniform float moss_amount : hint_range(0.0, 0.35) = 0.10;

varying vec3 stone_world_pos;
varying vec3 stone_world_normal;

float stone_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	stone_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	stone_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 normal_world = abs(normalize(stone_world_normal));
	bool horizontal = floor_mode || normal_world.y > 0.7;
	vec2 coordinate = horizontal ? stone_world_pos.xz :
		(normal_world.x > normal_world.z ? stone_world_pos.zy : stone_world_pos.xy);
	vec2 block_size = horizontal ? vec2(1.85, 1.75) : vec2(1.55, 0.72);
	vec2 block_uv = coordinate / block_size;
	float row = floor(block_uv.y);
	block_uv.x += mod(row, 2.0) * 0.5;
	vec2 cell = floor(block_uv);
	vec2 within = fract(block_uv);
	float edge = min(min(within.x, 1.0 - within.x), min(within.y, 1.0 - within.y));

	float stone_variation = stone_hash(cell) - 0.5;
	float broad_grain = sin(coordinate.x * 5.1 + coordinate.y * 2.7) *
		sin(coordinate.y * 4.3 - coordinate.x * 2.1);
	vec3 stone = base_color * (0.99 + stone_variation * 0.17 + broad_grain * 0.025);
	float moss = smoothstep(0.70, 0.94, stone_hash(cell + vec2(41.0, 79.0)));
	stone = mix(stone, stone * vec3(0.73, 0.88, 0.74), moss * moss_amount);

	float joint = smoothstep(0.014, 0.042, edge);
	float bevel = (1.0 - smoothstep(0.045, 0.115, edge)) * joint;
	ALBEDO = mix(base_color * 0.35, stone * (1.0 + bevel * 0.10), joint);
	ROUGHNESS = 0.94;
	SPECULAR = 0.22;
}
