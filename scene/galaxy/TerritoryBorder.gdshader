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
	float edge_distance = min(UV.y, 1.0 - UV.y);
	float outer_rim = (1.0 - smoothstep(0.0, 0.11, edge_distance)) * bright_rim_strength;
	float inner_falloff = pow(max(1.0 - UV.y, 0.0), 2.7);
	float glow_band = (1.0 - UV.y) * 0.26;
	float inner_coverage = inner_alpha_floor * 0.35 + inner_falloff * 0.22;
	vec3 rim_tint = vec3(0.84, 0.87, 0.94);
	vec3 final_color = mix(map_color.rgb * (0.92 + glow_band * 0.56), rim_tint, outer_rim);
	ALBEDO = final_color;
	EMISSION = final_color * (0.45 * inner_coverage + outer_rim * 0.85);
	ALPHA = clamp(inner_coverage * map_color.a + outer_rim * 0.78, 0.0, 1.0);
}
