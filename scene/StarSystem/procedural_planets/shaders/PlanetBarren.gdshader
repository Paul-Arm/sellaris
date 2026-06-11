// Barren / rocky / moon worlds: desaturated lavender greys with two octaves
// of voronoi crater bombing. Pattern is a pure function of the model-space
// direction + seeded uniforms (bake contract, see celestial_common).
shader_type spatial;
render_mode unshaded, cull_back;

#include "celestial_common.gdshaderinc"

uniform vec3 noise_offset = vec3(0.0);
uniform float noise_frequency = 3.0;
uniform vec3 palette_a = vec3(0.62, 0.62, 0.68);
uniform vec3 palette_b = vec3(0.12, 0.12, 0.14);
uniform vec3 palette_c = vec3(0.8, 0.8, 0.8);
uniform vec3 palette_d = vec3(0.0, 0.1, 0.2);
uniform float crater_frequency = 6.0;
uniform float crater_depth = 0.18;
uniform float pastel_sat_max = 0.18;
uniform float pastel_val_min = 0.42;
uniform float pastel_val_max = 0.88;
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.66, 0.92);
uniform float shadow_floor = 0.30;
uniform vec3 rim_color : source_color = vec3(0.78, 0.82, 0.95);
uniform float rim_strength = 0.10;
uniform float rim_power = 3.0;

varying vec3 v_model_dir;
varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_model_dir = normalize(VERTEX);
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 barren_surface(vec3 dir, out float relief) {
	float base = 0.35 + 0.4 * cb_fbm3_aa(dir * noise_frequency * 1.6 + noise_offset, 4);

	float crater_shade = 0.0;
	// Large craters: ~60% of voronoi cells host one (irregular clustering).
	vec2 large = cb_voronoi3(dir * crater_frequency + noise_offset);
	float large_active = step(0.4, large.y);
	float large_floor = 1.0 - cb_soft_threshold(large.x, 0.20, 0.05);
	float large_rim = clamp(1.0 - abs(large.x - 0.30) / 0.07, 0.0, 1.0);
	crater_shade += large_active * (large_rim * 0.12 - large_floor * crater_depth);
	// Small craters, sparser.
	vec2 small = cb_voronoi3(dir * crater_frequency * 2.3 + noise_offset + vec3(13.1));
	float small_active = step(0.55, small.y);
	float small_floor = 1.0 - cb_soft_threshold(small.x, 0.13, 0.04);
	float small_rim = clamp(1.0 - abs(small.x - 0.19) / 0.05, 0.0, 1.0);
	crater_shade += small_active * (small_rim * 0.08 - small_floor * crater_depth * 0.7);

	float t = clamp(base + crater_shade, 0.0, 1.0);
	relief = t;
	return cb_cosine_palette(t, palette_a, palette_b, palette_c, palette_d);
}

void fragment() {
	vec3 dir = normalize(v_model_dir);
	float relief;
	vec3 albedo = cb_pastelize(barren_surface(dir, relief), pastel_sat_max, pastel_val_min, pastel_val_max);
	// Relief contrast AFTER the pastel value clamp, so craters stay visible
	// even with the near-flat desaturated palette.
	albedo *= mix(0.66, 1.12, relief);
	vec3 sun_dir = cb_resolve_sun_dir(v_world_pos);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	ALBEDO = cb_pastel_light(
		albedo, v_world_normal, sun_dir, view_dir,
		shadow_tint, shadow_floor, rim_color, rim_strength, rim_power
	);
}
