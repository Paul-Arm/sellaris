shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
uniform vec4 tint : source_color = vec4(0.85, 0.35, 0.7, 1.0);
uniform float strength = 1.0;
uniform float phase = 0.0;

void vertex() {
	// Camera-facing light volume, with a circular falloff before every edge.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	float falloff = exp(-radius * radius * 22.0) * 0.7 + exp(-radius * radius * 5.0) * 0.09;
	float edge = 1.0 - smoothstep(0.7, 1.0, radius);
	float breathe = 1.0 + 0.025 * sin(TIME * 0.65 + phase);
	ALBEDO = tint.rgb * 3.0;
	ALPHA = falloff * edge * strength * breathe;
}
