// Star surface: emissive sphere with slow fbm granulation and voronoi
// convection cells, painterly limb darkening plus a thin bright fresnel rim.
// Color ramp and energy come from the star class (set by ProceduralStarVisual);
// pulse_speed > 0 turns it into a pulsing compact star (neutron).
shader_type spatial;
render_mode unshaded, cull_back;

#include "celestial_common.gdshaderinc"

uniform vec3 noise_offset = vec3(0.0);
uniform float cell_frequency = 6.0;
uniform vec3 color_cool : source_color = vec3(0.95, 0.62, 0.35);
uniform vec3 color_hot : source_color = vec3(1.0, 0.94, 0.78);
uniform float core_energy = 1.8;
uniform float limb_strength = 0.55;
uniform float pulse_speed = 0.0;
uniform float phase_offset = 0.0;

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
	// Visible boil: spots crawl across the surface within seconds; the
	// identity (palette, energy) stays seed-pure.
	vec3 drift = vec3(TIME * 0.055, TIME * 0.038, -TIME * 0.046) + vec3(phase_offset);

	// Glowing-cloud surface: domain-warped billow noise forms bright cloud
	// clumps separated by visibly darker channels (Stellaris artwork look).
	vec3 sample_dir = dir * cell_frequency * 0.8 + noise_offset + drift;
	vec3 warped = cb_warp3(sample_dir, 0.55, 1.7, noise_offset + vec3(7.0));
	float base = cb_fbm3(warped, 5);
	float detail = cb_fbm3(warped * 2.6 + vec3(31.0), 4);
	// Mostly-bright disc: clouds cover ~70% of the surface, the channels
	// between them are thin darker veins (not broad dark patches).
	float clouds = smoothstep(0.16, 0.55, base) * (0.7 + 0.6 * smoothstep(0.25, 0.75, detail));
	clouds = clamp(clouds, 0.0, 1.0);
	float granulation = clouds;
	// Veins stay below the tonemap burnout; clumps blow out.
	vec3 grain_col = mix(color_cool * 0.58, color_hot, clouds);

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float facing = clamp(dot(normalize(v_world_normal), view_dir), 0.0, 1.0);
	float center_boost = pow(facing, 3.0);
	vec3 white_hot = mix(color_hot, vec3(1.0), 0.75) * (0.88 + 0.25 * clouds);
	vec3 col = mix(grain_col, white_hot, center_boost * 0.6);
	float limb = 1.0 - limb_strength * 0.6 * pow(1.0 - facing, 1.6);
	float edge_glow = cb_fresnel(v_world_normal, view_dir, 3.0) * 0.6;

	float pulse = 1.0;
	if (pulse_speed > 0.001) {
		pulse = 0.8 + 0.2 * sin(TIME * pulse_speed + phase_offset);
	}

	// Energy tapers toward the limb so the convection texture stays below
	// the tonemap burnout there — white-hot center, textured rim.
	float energy = core_energy * mix(0.52, 1.0, center_boost);

	// unshaded mode ignores EMISSION — HDR output goes through ALBEDO and
	// still feeds the environment glow.
	// Compress the luminous surface so convection remains visible on SDR.
	vec3 radiance = (col * limb * energy + color_hot * edge_glow) * pulse;
	ALBEDO = radiance / (vec3(1.0) + radiance * 0.65);
}
