shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform int well_count = 0;
uniform vec4 wells[32]; // x, z, softening radius, visual depth
uniform float map_extent = 100.0;
uniform int exit_count = 0;
uniform vec4 exits[32]; // x, z, compact support radius, depth
#include "res://scene/StarSystem/design/MapDirectLight.gdshaderinc"
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
	for (int i = 0; i < 32; i++) {
		if (i >= exit_count) { break; }
		vec2 q = (p - exits[i].xy) / exits[i].z;
		h -= exits[i].w * pow(max(0.0, 1.0 - dot(q, q)), 3.0);
	}
	return h;
}

void vertex() {
	map_position = VERTEX.xz;
	potential_height = potential(map_position);
	VERTEX.y = potential_height;
}

vec3 surface_normal(vec2 p) {
	vec2 gradient = vec2(0.0);
	for (int i = 0; i < 32; i++) {
		if (i >= well_count) { break; }
		vec2 delta = p - wells[i].xy;
		float r2 = dot(delta, delta) + wells[i].z * wells[i].z;
		gradient += wells[i].w * wells[i].z * delta / (r2 * sqrt(r2));
	}
	for (int i = 0; i < 32; i++) {
		if (i >= exit_count) { break; }
		vec2 delta = p - exits[i].xy;
		float r2 = exits[i].z * exits[i].z;
		float falloff = max(0.0, 1.0 - dot(delta, delta) / r2);
		gradient += 6.0 * exits[i].w * delta / r2 * falloff * falloff;
	}
	return normalize(vec3(-gradient.x, 1.0, -gradient.y));
}

void fragment() {
	vec3 light = map_direct_light(map_position);
	light = mix(vec3(dot(light, vec3(0.2126, 0.7152, 0.0722))), light, 0.16);
	// Constant-potential contours; derivatives keep the line width stable on zoom.
	float h = potential(map_position) * 1.0;
	float width = max(fwidth(h), 0.018);
	float line = 1.0 - smoothstep(width * 0.28, width * 0.95, abs(fract(h + 0.5) - 0.5));
	float edge = 1.0 - smoothstep(0.72, 0.98, length(map_position) / map_extent);
	vec3 normal = surface_normal(map_position);
	float relief = 0.24 + 0.76 * max(dot(normal, normalize(vec3(-0.5, 0.8, 0.35))), 0.0);
	vec3 well_glow = vec3(0.0);
	for (int i = 0; i < 32; i++) {
		if (i >= body_count) { break; }
		if (bodies[i].w <= 0.0) { continue; }
		float distance_in_radii = length(map_position - bodies[i].xy) / max(bodies[i].z * 4.0, 0.01);
		vec3 aura_color = mix(body_colors[i].rgb, vec3(0.9, 0.28, 0.68), 0.65);
		well_glow += aura_color * exp(-distance_in_radii * distance_in_radii * 0.5);
	}
	vec3 contour_color = vec3(0.065, 0.10, 0.14) + light * illumination_strength;
	// Outbound traces start at their local spacetime well. A geometric
	// chevron encodes direction; these are connections, not orbital paths.
	float routes = 0.0;
	float gates = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= exit_count) { break; }
		vec2 direction = normalize(exits[i].xy);
		vec2 delta = map_position - exits[i].xy;
		float along = dot(delta, direction);
		float across = abs(dot(delta, vec2(-direction.y, direction.x)));
		float aa = max(fwidth(across), 0.035);
		float trace = 1.0 - smoothstep(aa * 0.8, aa * 1.8, across);
		float length_limit = map_extent * 0.25;
		trace *= smoothstep(0.0, exits[i].z * 0.3, along) * (1.0 - smoothstep(length_limit * 0.75, length_limit, along));
		float arrow_at = exits[i].z * 1.5;
		float arrow = 1.0 - smoothstep(aa * 0.7, aa * 1.9, abs(across + (along - arrow_at) * 0.7));
		arrow *= step(arrow_at - exits[i].z * 0.55, along) * step(along, arrow_at);
		routes = max(routes, max(trace, arrow));
		float q = length(delta) / exits[i].z;
		gates = max(gates, (1.0 - smoothstep(0.4, 1.3, q)) * line);
	}
	// No filled surface, grid, or depth footprint. Only luminous contours
	// and exit traces survive; the mesh boundary fades radially to zero.
	ALBEDO = contour_color * (0.16 + 0.22 * relief) + well_glow * 2.4 + vec3(0.05, 0.27, 0.40) * gates + vec3(0.18, 0.55, 0.72) * routes;
	ALPHA = edge * clamp(max(line * 0.8, max(routes, gates)), 0.0, 1.0);
}
