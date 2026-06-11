// Dry / desert / arid worlds: domain-warped dune bands in warm tans and
// ochres, optional sparse craters. Pattern is a pure function of the
// model-space direction + seeded uniforms (bake contract).
shader_type spatial;
render_mode unshaded, cull_back;

#include "celestial_common.gdshaderinc"

uniform vec3 noise_offset = vec3(0.0);
uniform float noise_frequency = 3.0;
uniform vec3 palette_a = vec3(0.72, 0.58, 0.42);
uniform vec3 palette_b = vec3(0.18, 0.14, 0.1);
uniform vec3 palette_c = vec3(0.7, 0.7, 0.6);
uniform vec3 palette_d = vec3(0.0, 0.1, 0.2);
uniform float band_frequency = 4.5;
uniform float warp_amount = 1.1;
uniform float crater_strength = 0.0;
uniform float crater_frequency = 5.0;
uniform float pastel_sat_max = 0.45;
uniform float pastel_val_min = 0.45;
uniform float pastel_val_max = 0.92;
uniform vec3 shadow_tint : source_color = vec3(0.66, 0.62, 0.88);
uniform float shadow_floor = 0.32;
uniform vec3 rim_color : source_color = vec3(1.0, 0.9, 0.78);
uniform float rim_strength = 0.2;
uniform float rim_power = 3.0;

varying vec3 v_model_dir;
varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_model_dir = normalize(VERTEX);
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 desert_surface(vec3 dir) {
	float lat = cb_latitude(dir);
	float warp = cb_fbm3(dir * noise_frequency + noise_offset, 4) - 0.5;
	float band = sin((lat * band_frequency + warp_amount * warp) * 3.14159265);
	float t = 0.5 + 0.5 * band;
	// Fine grain over the dunes.
	t = mix(t, cb_fbm3_aa(dir * noise_frequency * 3.0 + noise_offset, 3), 0.22);

	// Optional sparse craters (most desert worlds roll 0 strength).
	if (crater_strength > 0.001) {
		vec2 craters = cb_voronoi3(dir * crater_frequency + noise_offset);
		float active = step(0.62, craters.y);
		float crater_floor = 1.0 - cb_soft_threshold(craters.x, 0.16, 0.04);
		t -= active * crater_floor * crater_strength;
	}

	return cb_cosine_palette(0.32 + 0.46 * clamp(t, 0.0, 1.0), palette_a, palette_b, palette_c, palette_d);
}

void fragment() {
	vec3 dir = normalize(v_model_dir);
	vec3 albedo = cb_pastelize(desert_surface(dir), pastel_sat_max, pastel_val_min, pastel_val_max);
	vec3 sun_dir = cb_resolve_sun_dir(v_world_pos);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	ALBEDO = cb_pastel_light(
		albedo, v_world_normal, sun_dir, view_dir,
		shadow_tint, shadow_floor, rim_color, rim_strength, rim_power
	);
}
