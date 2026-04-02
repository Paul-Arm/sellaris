shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 halo_color : source_color = vec4(0.6, 0.8, 1.0, 0.35);
uniform float inner_radius : hint_range(0.0, 1.0) = 0.34;
uniform float outer_radius : hint_range(0.0, 1.5) = 0.48;
uniform float softness : hint_range(0.01, 1.0) = 0.18;

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float radius = length(centered_uv);
	float inner = smoothstep(inner_radius - softness, inner_radius + softness, radius);
	float outer = 1.0 - smoothstep(outer_radius - softness, outer_radius + softness, radius);
	float alpha = clamp(inner * outer, 0.0, 1.0) * halo_color.a;
	ALBEDO = halo_color.rgb;
	EMISSION = halo_color.rgb * alpha * 2.2;
	ALPHA = alpha;
}
