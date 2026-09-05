shader_type spatial;
render_mode unshaded, cull_disabled;
uniform int well_count = 0;
uniform vec4 wells[32]; // x, z, softening radius, visual depth
uniform float map_extent = 100.0;
uniform sampler2D radiance_cascade : filter_nearest, repeat_disable;
uniform float illumination_strength : hint_range(0.0, 12.0) = 7.0;
varying vec2 map_position;
varying float potential_height;

float potential(vec2 p) {
	float h = -1.2;
	for (int i = 0; i < 32; i++) {
		if (i >= well_count) { break; }
		vec2 delta = p - wells[i].xy;
		float radius = wells[i].z;
		h -= wells[i].w * radius / sqrt(dot(delta, delta) + radius * radius);
	}
	return h;
}

vec3 probe_light(ivec2 probe) {
	probe = clamp(probe, ivec2(0), ivec2(63));
	vec3 sum = vec3(0.0);
	for (int y = 0; y < 2; y++) {
		for (int x = 0; x < 2; x++) {
			sum += texelFetch(radiance_cascade, probe * 2 + ivec2(x, y), 0).rgb;
		}
	}
	return sum * 0.25;
}

void vertex() {
	map_position = VERTEX.xz;
	potential_height = potential(map_position);
	VERTEX.y = potential_height;
}

void fragment() {
	vec2 map_uv = map_position / (map_extent * 2.0) + 0.5;
	vec2 coord = map_uv * 64.0 - 0.5;
	ivec2 base = ivec2(floor(coord));
	vec2 f = fract(coord);
	vec3 light = mix(mix(probe_light(base), probe_light(base + ivec2(1, 0)), f.x), mix(probe_light(base + ivec2(0, 1)), probe_light(base + ivec2(1, 1)), f.x), f.y);
	// Constant-potential contours; derivatives keep the line width stable on zoom.
	float h = potential(map_position) * 2.4;
	float width = max(fwidth(h), 0.018);
	float line = 1.0 - smoothstep(width * 0.28, width * 0.95, abs(fract(h + 0.5) - 0.5));
	float edge = 1.0 - smoothstep(0.66, 1.0, max(abs(map_uv.x - 0.5), abs(map_uv.y - 0.5)) * 2.0);
	vec3 floor_color = vec3(0.009, 0.016, 0.021) + light * illumination_strength * 0.23;
	vec3 contour_color = vec3(0.13, 0.19, 0.20) + light * illumination_strength;
	ALBEDO = mix(vec3(0.003, 0.006, 0.010), floor_color + contour_color * line * 0.50, edge);
}
