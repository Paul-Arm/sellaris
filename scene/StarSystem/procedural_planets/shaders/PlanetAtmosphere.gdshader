// Atmosphere shell: slightly larger sphere with front faces culled. Only the
// rear shell visible around the planet's silhouette survives the depth test,
// producing a halo that hugs the limb with correct occlusion. Brightness
// rises from the shell's outer edge toward the planet limb and is biased to
// the day side (wrapped so the rim survives a bit past the terminator).
shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never;

#include "celestial_common.gdshaderinc"

uniform vec4 atmosphere_color : source_color = vec4(0.72, 0.9, 1.0, 0.6);
uniform float intensity = 1.3;
// planet_radius / shell_radius — where the planet limb sits on the shell.
uniform float limb_ratio = 0.9;
uniform float density_power = 2.2;

varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	// Rear shell: normals face away from the camera; flip for the profile.
	float facing = clamp(dot(-normalize(v_world_normal), view_dir), 0.0, 1.0);
	float limb_x = sqrt(max(1.0 - limb_ratio * limb_ratio, 0.0001));
	float profile = pow(clamp(facing / limb_x, 0.0, 1.0), density_power);

	vec3 sun_dir = cb_resolve_sun_dir(v_world_pos);
	float day = clamp(dot(normalize(v_world_normal), sun_dir) * 0.5 + 0.55, 0.0, 1.0);

	float strength = profile * day;
	// unshaded mode ignores EMISSION — additive output goes through ALBEDO.
	ALBEDO = atmosphere_color.rgb * strength * intensity;
	ALPHA = strength * atmosphere_color.a;
}
