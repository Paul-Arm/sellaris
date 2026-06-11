// Glowing cloud around the star: two counter-rotating fbm layers shape a
// churning fog over the radial falloff — billowing clumps, not a smooth
// gradient. Billboarding happens shader-side in vertex() (no per-frame
// script work), and a distance boost keeps far stars readable at maximum
// zoom — computed from the camera position in-shader.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

#include "celestial_common.gdshaderinc"

uniform vec4 corona_color : source_color = vec4(1.0, 0.85, 0.6, 0.4);
// Star limb in quad UV space — set from GDScript as ~1/halo_scale.
uniform float core_radius = 0.75;
uniform float falloff = 6.0;
uniform float cloud_frequency = 2.4;
uniform float billow_strength = 1.1;
uniform float base_glow = 0.25;
uniform float rotation_speed = 0.05;
uniform float drift_speed = 0.06;
uniform float phase_offset = 0.0;
uniform float boost_distance = 180.0;
uniform float boost_max = 2.2;

varying float v_boost;

void vertex() {
	vec3 model_scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);
	mat4 billboard = mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * model_scale.x, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * model_scale.y, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * model_scale.z, 0.0),
		MODEL_MATRIX[3]
	);
	float camera_distance = length(CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz);
	v_boost = clamp(camera_distance / boost_distance, 1.0, boost_max);
	VERTEX *= v_boost;
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float radius = length(centered_uv);
	float base_angle = atan(centered_uv.y, centered_uv.x);

	// Two cloud layers, counter-rotating, drifting slowly outward. Periodic
	// by construction: noise sampled on the unit circle embedding, radius on
	// the third axis.
	float a1 = base_angle + TIME * rotation_speed + phase_offset;
	vec3 p1 = vec3(cos(a1), sin(a1), 0.0) * cloud_frequency;
	p1.z = radius * cloud_frequency * 1.6 - TIME * drift_speed + phase_offset;
	float c1 = cb_fbm3(p1, 5);

	float a2 = base_angle - TIME * rotation_speed * 0.6 + phase_offset * 1.7;
	vec3 p2 = vec3(cos(a2), sin(a2), 0.0) * cloud_frequency * 2.1;
	p2.z = radius * cloud_frequency * 3.0 - TIME * drift_speed * 1.7 + 41.0;
	float c2 = cb_fbm3(p2, 4);

	float billow = smoothstep(0.3, 0.78, c1) * (0.65 + 0.55 * c2);

	float reach = max(radius - core_radius, 0.0);
	float radial = exp(-reach * falloff);
	// Bright rim hugging the limb so the cloud connects to the disc.
	float rim = exp(-reach * 10.0) * 0.55;
	float glow = radial * (base_glow + billow_strength * billow) + rim;
	glow *= 1.0 - smoothstep(0.82, 1.0, radius);

	float alpha = clamp(glow * corona_color.a, 0.0, 1.0);
	// unshaded mode ignores EMISSION — additive output goes through ALBEDO.
	ALBEDO = corona_color.rgb * glow * corona_color.a * 2.0;
	ALPHA = alpha;
}
