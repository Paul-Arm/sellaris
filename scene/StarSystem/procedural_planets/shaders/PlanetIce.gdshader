// Ice / frozen worlds: the brightest archetype. Pale pastel blues and whites,
// glacial fissures via ridged noise with a bright crest line, optional darker
// frozen lakes. Pattern is a pure function of the model-space direction +
// seeded uniforms (bake contract).
shader_type spatial;
render_mode unshaded, cull_back;

#include "celestial_common.gdshaderinc"

uniform vec3 noise_offset = vec3(0.0);
uniform float noise_frequency = 3.0;
uniform vec3 palette_a = vec3(0.82, 0.88, 0.95);
uniform vec3 palette_b = vec3(0.1, 0.1, 0.12);
uniform vec3 palette_c = vec3(0.6, 0.6, 0.7);
uniform vec3 palette_d = vec3(0.5, 0.55, 0.65);
uniform float crack_frequency = 6.0;
uniform float crack_strength = 0.45;
uniform float lake_amount = 0.0;
uniform vec3 crack_color : source_color = vec3(0.36, 0.58, 0.78);
uniform float pastel_sat_max = 0.3;
uniform float pastel_val_min = 0.72;
uniform float pastel_val_max = 0.97;
uniform vec3 shadow_tint : source_color = vec3(0.6, 0.66, 0.94);
uniform float shadow_floor = 0.34;
uniform vec3 rim_color : source_color = vec3(0.85, 0.94, 1.0);
uniform float rim_strength = 0.3;
uniform float rim_power = 2.8;

varying vec3 v_model_dir;
varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_model_dir = normalize(VERTEX);
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 dir = normalize(v_model_dir);
	float base = 0.55 + 0.3 * cb_fbm3_aa(dir * noise_frequency + noise_offset, 4);
	vec3 albedo = cb_cosine_palette(base, palette_a, palette_b, palette_c, palette_d);
	// Pastel clamp on the bright base only — cracks and lakes mix in AFTER,
	// otherwise the value floor lifts them back to near-white.
	albedo = cb_pastelize(albedo, pastel_sat_max, pastel_val_min, pastel_val_max);

	// Glacial fissures: deep teal cracks with a bright crest at the ridge.
	float ridge = cb_ridged3(dir * crack_frequency + noise_offset, 4);
	float crack = smoothstep(0.48, 0.66, ridge);
	float crest = smoothstep(0.78, 0.88, ridge);
	albedo = mix(albedo, crack_color, crack * crack_strength);
	albedo += vec3(0.14) * crest;

	// Optional frozen lakes: low-frequency darker glossy patches.
	if (lake_amount > 0.001) {
		float lakes = cb_fbm3(dir * noise_frequency * 0.7 + noise_offset + vec3(41.7), 3);
		float lake_mask = smoothstep(0.62, 0.7, lakes);
		albedo = mix(albedo, crack_color * 0.85, lake_mask * lake_amount);
	}

	vec3 sun_dir = cb_resolve_sun_dir(v_world_pos);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	ALBEDO = cb_pastel_light(
		albedo, v_world_normal, sun_dir, view_dir,
		shadow_tint, shadow_floor, rim_color, rim_strength, rim_power
	);
}
