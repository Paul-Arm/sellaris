// Cloud shell (separate sphere, ~1.025x surface radius). Drift comes from
// node rotation relative to the surface spin; the pattern itself is static.
// Own light ramp: the cloud terminator runs visibly ahead of the ground
// terminator and clouds catch rim light at the limb — the strongest 3D cue.
shader_type spatial;
render_mode unshaded, cull_back;

#include "celestial_common.gdshaderinc"

uniform vec3 noise_offset = vec3(0.0);
uniform float cloud_frequency = 3.0;
uniform float cloud_cover = 0.52;
uniform float cloud_density = 0.85;
uniform vec3 cloud_tint : source_color = vec3(0.97, 0.97, 1.0);
uniform vec3 shadow_tint : source_color = vec3(0.58, 0.63, 0.92);
uniform float shadow_floor = 0.42;
uniform vec3 rim_color : source_color = vec3(1.0, 0.98, 0.94);
uniform float rim_strength = 0.3;
uniform float rim_power = 2.2;

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
	float clouds = cb_fbm3(cb_warp3(dir, 0.35, 3.0, noise_offset) * cloud_frequency + noise_offset, 5);
	float alpha = smoothstep(cloud_cover, cloud_cover + 0.18, clouds) * cloud_density;

	vec3 sun_dir = cb_resolve_sun_dir(v_world_pos);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 lit = cb_pastel_light(
		cloud_tint, v_world_normal, sun_dir, view_dir,
		shadow_tint, shadow_floor, rim_color, rim_strength, rim_power
	);
	ALBEDO = lit;
	ALPHA = alpha;
}
