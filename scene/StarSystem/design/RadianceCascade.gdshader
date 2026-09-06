// Flatland radiance intervals. Spatial spacing doubles while angular samples
// quadruple. Upper intervals are averaged angularly and bilinearly in space.
// This is a map-space light transport pass, not a screen bloom filter.
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D upper_cascade : filter_nearest, repeat_disable;
uniform int cascade_index = 0;
uniform int body_count = 0;
uniform vec4 bodies[32]; // x, z, radius, emitter strength
uniform vec4 body_colors[32];
uniform float map_extent = 100.0;
const float PI2 = 6.28318530718;
const int ATLAS = 256;

vec4 trace_interval(vec2 origin, vec2 direction, float start, float end) {
	float nearest = end;
	vec3 light = vec3(0.0);
	float transmission = 1.0;
	for (int i = 0; i < 32; i++) {
		if (i >= body_count) { break; }
		vec2 relative = origin - bodies[i].xy;
		float b = dot(relative, direction);
		float c = dot(relative, relative) - bodies[i].z * bodies[i].z;
		float disc = b * b - c;
		if (disc < 0.0) { continue; }
		float root = sqrt(disc);
		float entry = max(start, -b - root);
		float exit_t = -b + root;
		if (exit_t >= start && entry < nearest) {
			nearest = entry;
			light = body_colors[i].rgb * bodies[i].w;
			transmission = 0.0;
		}
	}
	return vec4(light, transmission);
}

vec4 upper_probe(ivec2 probe, int direction, int grid, int tile) {
	probe = clamp(probe, ivec2(0), ivec2(grid - 1));
	ivec2 texel = probe * tile + ivec2(direction % tile, direction / tile);
	return texelFetch(upper_cascade, texel, 0);
}

void fragment() {
	int tile = 2 << cascade_index;
	int grid = ATLAS / tile;
	ivec2 pixel = ivec2(FRAGCOORD.xy);
	ivec2 probe = pixel / tile;
	ivec2 local = pixel - probe * tile;
	int direction_index = local.y * tile + local.x;
	float angle = PI2 * (float(direction_index) + 0.5) / float(tile * tile);
	vec2 direction = vec2(cos(angle), sin(angle));
	vec2 probe_uv = (vec2(probe) + 0.5) / float(grid);
	vec2 origin = (probe_uv * 2.0 - 1.0) * map_extent;
	float base_interval = map_extent / 24.0;
	float interval_start = base_interval * (pow(4.0, float(cascade_index)) - 1.0) / 3.0;
	float interval_end = interval_start + base_interval * pow(4.0, float(cascade_index));
	vec4 near_light = trace_interval(origin, direction, interval_start, interval_end);
	vec4 far_light = vec4(0.0, 0.0, 0.0, 1.0);
	if (cascade_index < 3 && near_light.a > 0.0) {
		int next_grid = grid / 2;
		vec2 coord = probe_uv * float(next_grid) - 0.5;
		ivec2 base = ivec2(floor(coord));
		vec2 f = fract(coord);
		far_light = vec4(0.0);
		for (int d = 0; d < 4; d++) {
			int next_direction = direction_index * 4 + d;
			vec4 a = mix(upper_probe(base, next_direction, next_grid, tile * 2), upper_probe(base + ivec2(1, 0), next_direction, next_grid, tile * 2), f.x);
			vec4 b = mix(upper_probe(base + ivec2(0, 1), next_direction, next_grid, tile * 2), upper_probe(base + ivec2(1, 1), next_direction, next_grid, tile * 2), f.x);
			far_light += mix(a, b, f.y) * 0.25;
		}
	}
	COLOR = vec4(near_light.rgb + near_light.a * far_light.rgb, near_light.a * far_light.a);
}
