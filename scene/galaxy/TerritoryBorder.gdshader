shader_type spatial;

render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform int palette_size = 1;
uniform float bright_rim_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float inner_alpha_floor : hint_range(0.0, 0.5, 0.01) = 0.18;

vec4 sample_palette(float palette_index) {
	float safe_palette_size = max(float(palette_size), 1.0);
	float clamped_index = clamp(palette_index, 0.0, safe_palette_size - 1.0);
	float u = (clamped_index + 0.5) / safe_palette_size;
	return texture(palette_texture, vec2(u, 0.5));
}

void fragment() {
	float palette_index = round(UV2.x);
	vec4 map_color = sample_palette(palette_index);
	// One contour with a soft inward fade, rather than two white contour bands.
	float outer_rim = (1.0 - smoothstep(0.0, 0.18, UV.y)) * bright_rim_strength;
	float inside = pow(max(1.0 - UV.y, 0.0), 2.0);
	vec3 final_color = mix(map_color.rgb, vec3(0.75, 0.91, 0.88), outer_rim * 0.28);
	ALBEDO = final_color * (1.0 + outer_rim * 0.3);
	ALPHA = clamp(map_color.a * (inside * inner_alpha_floor * 0.3 + outer_rim * 0.72), 0.0, 1.0);
}
