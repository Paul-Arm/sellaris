// Lava / molten worlds: dark warm crust with emissive lava veins (ridged
// fbm) that feed the environment glow and keep the night side interesting.
// The crust/vein pattern is a pure function of the model-space direction +
// seeded uniforms; TIME only drives the cosmetic emission pulse.
shader_type spatial;
render_mode unshaded, cull_back;

#include "celestial_common.gdshaderinc"

uniform vec3 noise_offset = vec3(0.0);
uniform float noise_frequency = 3.0;
uniform vec3 palette_a = vec3(0.32, 0.22, 0.2);
uniform vec3 palette_b = vec3(0.14, 0.1, 0.08);
uniform vec3 palette_c = vec3(0.7, 0.6, 0.5);
uniform vec3 palette_d = vec3(0.0, 0.05, 0.1);
uniform float vein_frequency = 4.5;
uniform float vein_emission = 2.4;
uniform vec3 vein_color : source_color = vec3(1.0, 0.62, 0.35);
uniform float pulse_speed = 0.6;
uniform float phase_offset = 0.0;
uniform float pastel_sat_max = 0.4;
uniform float pastel_val_min = 0.12;
uniform float pastel_val_max = 0.42;
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.58, 0.86);
uniform float shadow_floor = 0.28;
uniform vec3 rim_color : source_color = vec3(1.0, 0.7, 0.5);
uniform float rim_strength = 0.18;
uniform float rim_power = 3.0;

varying vec3 v_model_dir;
varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_model_dir = normalize(VERTEX);
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 lava_crust(vec3 dir, out float vein_mask) {
	float crust = clamp(cb_fbm3_aa(dir * noise_frequency + noise_offset, 4), 0.0, 1.0);
	vec3 warped = cb_warp3(dir, 0.25, 3.0, noise_offset);
	float veins = cb_ridged3(warped * vein_frequency + noise_offset, 4);
	vein_mask = smoothstep(0.58, 0.7, veins);
	// Fixed dark warm ramp — the seeded cosine palette only tints it lightly,
	// so crusts always read as cooled rock between the glowing veins.
	vec3 dark_ramp = mix(vec3(0.14, 0.09, 0.08), vec3(0.4, 0.27, 0.21), crust);
	vec3 palette_tone = cb_cosine_palette(crust, palette_a, palette_b, palette_c, palette_d);
	return mix(dark_ramp, dark_ramp * (0.6 + 0.8 * palette_tone), 0.35);
}

void fragment() {
	vec3 dir = normalize(v_model_dir);
	float vein_mask;
	vec3 albedo = lava_crust(dir, vein_mask);
	albedo = cb_pastelize(albedo, pastel_sat_max, pastel_val_min, pastel_val_max);
	vec3 sun_dir = cb_resolve_sun_dir(v_world_pos);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 lit = cb_pastel_light(
		albedo, v_world_normal, sun_dir, view_dir,
		shadow_tint, shadow_floor, rim_color, rim_strength, rim_power
	);
	// Veins glow regardless of the light ramp; unshaded mode ignores
	// EMISSION, so the HDR vein glow is added to ALBEDO (feeds the bloom).
	float pulse = 0.85 + 0.15 * sin(TIME * pulse_speed + phase_offset * 7.0);
	ALBEDO = lit + vein_color * vein_mask * vein_emission * pulse;
}
