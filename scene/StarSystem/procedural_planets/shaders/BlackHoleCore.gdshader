// Black hole event horizon: a near-black sphere with a thin, intensely
// emissive fresnel "photon ring" at the silhouette edge that feeds the bloom.
shader_type spatial;
render_mode unshaded, cull_back;

#include "celestial_common.gdshaderinc"

uniform vec3 ring_color : source_color = vec3(1.0, 0.82, 0.55);
uniform float ring_emission = 2.5;
uniform float ring_power = 8.0;

varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float f = cb_fresnel(v_world_normal, view_dir, ring_power);
	float ring = smoothstep(0.35, 0.75, f);
	// unshaded mode ignores EMISSION — HDR photon ring goes through ALBEDO.
	ALBEDO = vec3(0.005) + ring_color * ring * ring_emission;
}
