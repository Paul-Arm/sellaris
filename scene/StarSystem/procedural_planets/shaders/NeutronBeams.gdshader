// Neutron star polar jets on a single tall quad spanning both poles,
// billboarded around the jet axis (cylindrical billboard — the quad spins to
// face the camera but stays aligned with the axis). Hot white core line in a
// soft blue sheath, widest at the star, tapering to points at both tips.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec3 beam_color : source_color = vec3(0.78, 0.9, 1.0);
uniform float beam_alpha = 0.85;
uniform float pulse_speed = 5.0;
uniform float phase_offset = 0.0;

varying vec2 v_uv;

void vertex() {
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_camera = CAMERA_POSITION_WORLD - origin;
	vec3 x_axis = normalize(cross(axis, to_camera));
	vec3 z_axis = normalize(cross(x_axis, axis));
	float scale_x = length(MODEL_MATRIX[0].xyz);
	float scale_y = length(MODEL_MATRIX[1].xyz);
	mat4 aligned = mat4(
		vec4(x_axis * scale_x, 0.0),
		vec4(axis * scale_y, 0.0),
		vec4(z_axis * scale_x, 0.0),
		vec4(origin, 1.0)
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * aligned;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_uv = UV;
}

void fragment() {
	vec2 centered = v_uv * 2.0 - 1.0; // y = 0 at the star, +/-1 at the tips
	float along = abs(centered.y);
	// Width pinches toward the tips.
	float taper = pow(max(1.0 - along, 0.0), 0.65);
	float width = max(taper, 0.02);
	float across = abs(centered.x) / width;

	float core_line = exp(-across * across * 18.0);
	float sheath = exp(-across * across * 3.5) * 0.4;
	float axial_fade = pow(max(1.0 - along, 0.0), 0.9);
	// Bright flare where the jets meet the star.
	float base_flare = exp(-centered.y * centered.y * 10.0) * 0.5;

	float pulse = 0.8 + 0.2 * sin(TIME * pulse_speed + phase_offset);
	float strength = ((core_line + sheath) * axial_fade + base_flare * core_line) * pulse;
	// unshaded mode ignores EMISSION — additive output goes through ALBEDO.
	ALBEDO = mix(beam_color, vec3(1.0), core_line * 0.7) * strength * 2.2;
	ALPHA = clamp(strength, 0.0, 1.0) * beam_alpha;
}
