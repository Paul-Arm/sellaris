// Belt rock material for MultiMesh instances. Faceted low-poly look from
// screen-space derivative normals (no face normals needed in the mesh),
// crevice AO from vertex COLOR.r, per-instance tint between two pastel belt
// colors via INSTANCE_CUSTOM.x and slow tumbling in the vertex shader from
// INSTANCE_CUSTOM.yz (phase in radians, speed in rad/s).
shader_type spatial;
render_mode unshaded, cull_back;

#include "celestial_common.gdshaderinc"

uniform vec3 belt_color_a : source_color = vec3(0.64, 0.6, 0.55);
uniform vec3 belt_color_b : source_color = vec3(0.55, 0.56, 0.62);
uniform vec3 shadow_tint : source_color = vec3(0.62, 0.66, 0.92);
uniform float shadow_floor = 0.32;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_tint;
varying float v_ao;

void vertex() {
	float tumble_phase = INSTANCE_CUSTOM.y;
	float tumble_speed = INSTANCE_CUSTOM.z;
	vec3 tumble_axis = normalize(vec3(
		sin(tumble_phase * 1.3) + 0.2,
		cos(tumble_phase * 0.7) + 0.3,
		sin(tumble_phase * 2.1) - 0.2
	));
	mat3 tumble = cb_axis_rotation(tumble_axis, TIME * tumble_speed + tumble_phase);
	VERTEX = tumble * VERTEX;
	NORMAL = tumble * NORMAL;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_tint = INSTANCE_CUSTOM.x;
	v_ao = COLOR.r;
}

void fragment() {
	// Perfect facets from screen-space derivatives of the world position,
	// oriented along the smooth geometric normal (derivative winding can flip).
	vec3 facet_normal = normalize(cross(dFdx(v_world_pos), dFdy(v_world_pos)));
	if (dot(facet_normal, v_world_normal) < 0.0) {
		facet_normal = -facet_normal;
	}

	vec3 albedo = mix(belt_color_a, belt_color_b, v_tint);
	albedo *= mix(0.55, 1.0, v_ao);
	albedo = cb_pastelize(albedo, 0.25, 0.4, 0.9);

	vec3 sun_dir = cb_resolve_sun_dir(v_world_pos);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	ALBEDO = cb_pastel_light(
		albedo, facet_normal, sun_dir, view_dir,
		shadow_tint, shadow_floor, vec3(0.9, 0.92, 1.0), 0.12, 3.0
	);
}
