// Continental / ocean / gaia worlds: fbm landmasses with soft painterly
// coastlines, two-tone ocean with a bright coastal shelf, noisy polar caps
// and a stylized ocean sun glint. Pattern (terran_surface) is a pure function
// of the model-space direction + seeded uniforms (bake contract).
shader_type spatial;
render_mode unshaded, cull_back;

#include "celestial_common.gdshaderinc"

uniform vec3 noise_offset = vec3(0.0);
uniform float noise_frequency = 3.2;
uniform vec3 palette_a = vec3(0.5, 0.55, 0.45);
uniform vec3 palette_b = vec3(0.22, 0.2, 0.18);
uniform vec3 palette_c = vec3(0.9, 0.8, 0.7);
uniform vec3 palette_d = vec3(0.1, 0.3, 0.2);
uniform float ocean_level = 0.52;
uniform float cap_extent = 0.7;
uniform float continent_warp = 0.18;
uniform float glint_strength = 0.6;
uniform vec3 ocean_deep_color : source_color = vec3(0.16, 0.3, 0.52);
uniform vec3 ocean_shelf_color : source_color = vec3(0.32, 0.56, 0.72);
uniform float pastel_sat_max = 0.5;
uniform float pastel_val_min = 0.38;
uniform float pastel_val_max = 0.92;
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.66, 0.92);
uniform float shadow_floor = 0.30;
uniform vec3 rim_color : source_color = vec3(0.74, 0.88, 1.0);
uniform float rim_strength = 0.28;
uniform float rim_power = 2.6;

varying vec3 v_model_dir;
varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_model_dir = normalize(VERTEX);
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 terran_surface(vec3 dir, out float land_mask) {
	vec3 warped = cb_warp3(dir, continent_warp, noise_frequency * 0.5, noise_offset);
	float height = cb_fbm3(warped * noise_frequency + noise_offset, 5);
	land_mask = cb_soft_threshold(height, ocean_level, 0.015);
	float lat = abs(cb_latitude(dir));

	// Ocean: deep base with a bright shelf hugging the coastlines.
	float shelf = smoothstep(ocean_level - 0.12, ocean_level, height);
	vec3 ocean = mix(ocean_deep_color, ocean_shelf_color, shelf);

	// Land: palette ramp driven by elevation and latitude (cooler poleward).
	float land_t = 0.4 + 0.5 * (0.6 * smoothstep(ocean_level, 1.0, height) + 0.4 * lat);
	land_t += 0.08 * (cb_fbm3_aa(dir * noise_frequency * 3.0 + noise_offset, 3) - 0.5);
	vec3 land = cb_cosine_palette(land_t, palette_a, palette_b, palette_c, palette_d);

	vec3 col = mix(ocean, land, land_mask);

	// Noisy-edged polar caps.
	float cap_noise = 0.05 * cb_fbm3(dir * 8.0 + noise_offset, 2);
	float cap = smoothstep(cap_extent, cap_extent + 0.08, lat + cap_noise);
	return mix(col, vec3(0.93, 0.96, 1.0), cap);
}

void fragment() {
	vec3 dir = normalize(v_model_dir);
	float land_mask;
	vec3 albedo = terran_surface(dir, land_mask);
	albedo = cb_pastelize(albedo, pastel_sat_max, pastel_val_min, pastel_val_max);
	vec3 sun_dir = cb_resolve_sun_dir(v_world_pos);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 lit = cb_pastel_light(
		albedo, v_world_normal, sun_dir, view_dir,
		shadow_tint, shadow_floor, rim_color, rim_strength, rim_power
	);
	// Stylized sun glint on water; slightly HDR for a hint of bloom (unshaded
	// mode ignores EMISSION, so it is added to ALBEDO).
	float glint = pow(max(dot(reflect(-sun_dir, normalize(v_world_normal)), view_dir), 0.0), 96.0);
	glint *= smoothstep(0.0, 0.15, dot(normalize(v_world_normal), sun_dir));
	ALBEDO = lit + vec3(1.0, 0.98, 0.9) * glint * (1.0 - land_mask) * glint_strength * 1.2;
}
