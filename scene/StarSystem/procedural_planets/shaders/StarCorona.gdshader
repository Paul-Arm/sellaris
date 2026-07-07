// True-3D volumetric star corona: raymarches a spherical fog shell between
// the star surface (inner_radius) and the fringe edge (outer_radius).
// Density = 3D fbm billows sampled in star-local space, so cloud clumps sit
// spatially in front of and behind the star, parallax with the camera, and
// the rim brightens naturally where rays travel the longest chord through
// the shell. Rendered on an enlarged sphere mesh (cull_front), occlusion
// against the star handled analytically inside the march.
shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never;

#include "celestial_common.gdshaderinc"

uniform vec4 corona_color : source_color = vec4(1.0, 0.85, 0.6, 0.4);
uniform float inner_radius = 5.0;
uniform float outer_radius = 6.5;
uniform float cloud_frequency = 2.2;
uniform float billow_strength = 1.0;
uniform float base_glow = 0.18;
uniform float brightness = 0.8;
uniform float rotation_speed = 0.03;
uniform float drift_speed = 0.05;
uniform vec3 noise_offset = vec3(0.0);
uniform float phase_offset = 0.0;

varying vec3 v_world_pos;

const int STEPS = 14;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 ray_origin = CAMERA_POSITION_WORLD;
	vec3 ray_dir = normalize(v_world_pos - ray_origin);
	vec3 center = MODEL_MATRIX[3].xyz;

	// Ray / outer-sphere intersection.
	vec3 oc = ray_origin - center;
	float b = dot(oc, ray_dir);
	float c_out = dot(oc, oc) - outer_radius * outer_radius;
	float h_out = b * b - c_out;
	if (h_out <= 0.0) {
		discard;
	}
	float sq_out = sqrt(h_out);
	float t_near = max(-b - sq_out, 0.0);
	float t_far = -b + sq_out;
	// Stop at the star surface — the disc occludes the far half of the shell.
	float c_in = dot(oc, oc) - inner_radius * inner_radius;
	float h_in = b * b - c_in;
	if (h_in > 0.0) {
		t_far = min(t_far, -b - sqrt(h_in));
	}
	if (t_far <= t_near) {
		discard;
	}

	// Slow churn: the whole fog field rotates around Y and drifts.
	float spin_angle = TIME * rotation_speed + phase_offset;
	float ca = cos(spin_angle);
	float sa = sin(spin_angle);
	mat3 spin = mat3(vec3(ca, 0.0, -sa), vec3(0.0, 1.0, 0.0), vec3(sa, 0.0, ca));

	float shell_outer = outer_radius / inner_radius;
	float dt = (t_far - t_near) / float(STEPS);
	float accum = 0.0;
	for (int i = 0; i < STEPS; i++) {
		vec3 p = ray_origin + ray_dir * (t_near + (float(i) + 0.5) * dt);
		vec3 q = spin * (p - center) / inner_radius; // 1.0 at the star surface
		float r = length(q);
		float shell = 1.0 - smoothstep(1.0, shell_outer, r);
		float n = cb_fbm3(q * cloud_frequency + noise_offset + vec3(0.0, 0.0, TIME * drift_speed), 3);
		float billow = smoothstep(0.32, 0.72, n);
		accum += shell * (base_glow + billow_strength * billow);
	}
	// Normalize by shell thickness — tangent chords through the shell still
	// run several times longer than the thickness, brightening the rim.
	accum *= dt / max(outer_radius - inner_radius, 0.001) * brightness;

	// unshaded mode ignores EMISSION — additive output goes through ALBEDO.
	ALBEDO = corona_color.rgb * accum * corona_color.a * 2.0;
	ALPHA = 1.0;
}
