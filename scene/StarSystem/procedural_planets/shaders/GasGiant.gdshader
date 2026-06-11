// Gas giants: smoothstep-softened latitude bands over a turbulent latitude
// coordinate, slow differential drift (equator faster), optional great spot,
// stronger built-in limb darkening. The band pattern (gas_surface) is a pure
// function of a direction + seeded uniforms; TIME only rotates the sampling
// direction (drift), so a bake at drift=0 reproduces the identity look.
shader_type spatial;
render_mode unshaded, cull_back;

#include "celestial_common.gdshaderinc"

uniform vec3 noise_offset = vec3(0.0);
uniform float turb_frequency = 3.0;
uniform vec3 palette_a = vec3(0.78, 0.68, 0.62);
uniform vec3 palette_b = vec3(0.16, 0.14, 0.12);
uniform vec3 palette_c = vec3(0.8, 0.7, 0.6);
uniform vec3 palette_d = vec3(0.1, 0.2, 0.3);
uniform float band_count = 6.0;
uniform float band_warp = 0.3;
uniform float band_drift = 0.004;
uniform float phase_offset = 0.0;
uniform float has_spot = 0.0;
uniform vec3 spot_dir = vec3(0.8, 0.3, 0.5);
uniform float spot_radius = 0.16;
uniform vec3 spot_tint : source_color = vec3(0.9, 0.6, 0.55);
uniform float limb_darkening = 0.25;
uniform float pastel_sat_max = 0.38;
uniform float pastel_val_min = 0.55;
uniform float pastel_val_max = 0.94;
uniform vec3 shadow_tint : source_color = vec3(0.64, 0.66, 0.9);
uniform float shadow_floor = 0.32;
uniform vec3 rim_color : source_color = vec3(0.95, 0.9, 0.85);
uniform float rim_strength = 0.22;
uniform float rim_power = 2.2;

varying vec3 v_model_dir;
varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_model_dir = normalize(VERTEX);
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 gas_surface(vec3 dir) {
	float lat = cb_latitude(dir);
	float turbulence = cb_fbm3(dir * turb_frequency + noise_offset, 5) - 0.5;
	float band_coord = lat + band_warp * turbulence;

	// Great spot: local swirl perturbs the band coordinate, plus a tint.
	float spot_mask = 0.0;
	if (has_spot > 0.5) {
		float spot_dist = acos(clamp(dot(dir, normalize(spot_dir)), -1.0, 1.0));
		spot_mask = exp(-(spot_dist * spot_dist) / max(spot_radius * spot_radius, 0.0001));
		band_coord += spot_mask * 0.15 * sin(spot_dist * 24.0);
	}

	float t = 0.5 + 0.5 * sin(band_coord * band_count * 3.14159265);
	t = smoothstep(0.15, 0.85, t);
	vec3 col = cb_cosine_palette(t, palette_a, palette_b, palette_c, palette_d);
	col = mix(col, spot_tint, spot_mask * 0.7);
	return col;
}

void fragment() {
	vec3 dir = normalize(v_model_dir);
	// Differential drift: equatorial flow runs faster than the poles.
	float lat = cb_latitude(dir);
	float drift = TIME * band_drift * (1.0 + 0.5 * (1.0 - abs(lat))) + phase_offset;
	vec3 albedo = gas_surface(cb_rotate_y(dir, drift));
	albedo = cb_pastelize(albedo, pastel_sat_max, pastel_val_min, pastel_val_max);

	vec3 sun_dir = cb_resolve_sun_dir(v_world_pos);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 col = cb_pastel_light(
		albedo, v_world_normal, sun_dir, view_dir,
		shadow_tint, shadow_floor, rim_color, rim_strength, rim_power
	);
	// Deep soft limb, on top of the atmosphere shell.
	col *= 1.0 - limb_darkening * cb_fresnel(v_world_normal, view_dir, 1.5);
	ALBEDO = col;
}
