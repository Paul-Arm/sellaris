// Black hole accretion disk on the shared annulus mesh: radial temperature
// ramp (white-hot inner edge -> amber -> dim rose), slowly scrolling log
// spiral streaks, and a doppler brightness asymmetry — the approaching side
// glows hotter and whiter, the receding side dims toward red.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

#include "celestial_common.gdshaderinc"

uniform vec3 inner_color : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 mid_color : source_color = vec3(1.0, 0.72, 0.45);
uniform vec3 outer_color : source_color = vec3(0.85, 0.45, 0.5);
uniform float disk_emission = 2.6;
uniform float doppler_strength = 0.6;
uniform float scroll_speed = 0.15;
uniform float spiral_shear = 6.0;
uniform float band_seed = 0.0;
uniform float disk_alpha = 0.85;

varying vec3 v_world_pos;
varying vec2 v_uv;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
}

void fragment() {
	float t = v_uv.y;
	float angle = v_uv.x * 6.28318530718;
	// Spiral streaks, periodic via the unit-circle embedding.
	float spiral_angle = angle - TIME * scroll_speed - t * spiral_shear;
	vec3 sample_pos = vec3(cos(spiral_angle), sin(spiral_angle), t * 4.0 + band_seed * 17.0) * 2.2;
	float streaks = cb_fbm3(sample_pos, 4);

	float heat = 1.0 - t;
	vec3 col = mix(outer_color, mix(mid_color, inner_color, smoothstep(0.55, 1.0, heat)), smoothstep(0.0, 0.55, heat));
	float edge_fade = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.85, 1.0, t));
	float density = (0.55 + 0.45 * streaks) * edge_fade;

	// Doppler asymmetry from the orbital tangent vs. the view direction.
	vec3 disk_center = MODEL_MATRIX[3].xyz;
	vec3 disk_normal = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 radial_dir = normalize(v_world_pos - disk_center);
	vec3 tangent = normalize(cross(disk_normal, radial_dir));
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float doppler = 1.0 + doppler_strength * dot(tangent, view_dir);
	col = mix(col, vec3(1.0, 0.95, 0.9), clamp((doppler - 1.0) * 0.5, 0.0, 0.5));
	col = mix(col, col * vec3(1.0, 0.6, 0.5), clamp((1.0 - doppler) * 0.6, 0.0, 0.6));

	float brightness = density * doppler;
	float hot_edge = 1.0 + 1.5 * smoothstep(0.7, 1.0, heat);
	// unshaded mode ignores EMISSION — additive HDR goes through ALBEDO.
	ALBEDO = col * brightness * disk_emission * hot_edge;
	ALPHA = clamp(brightness, 0.0, 1.0) * disk_alpha;
}
