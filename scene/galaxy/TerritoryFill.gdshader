shader_type spatial;

render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D influence_map : filter_linear, repeat_disable;
uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform int palette_size = 1;
uniform float threshold : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float fill_overlap : hint_range(0.0, 0.2, 0.01) = 0.06;
uniform float fill_softness : hint_range(0.01, 0.5, 0.01) = 0.16;
uniform float fill_opacity : hint_range(0.0, 0.45, 0.01) = 0.18;

vec4 sample_palette(float palette_index) {
	float safe_palette_size = max(float(palette_size), 1.0);
	float clamped_index = clamp(palette_index, 0.0, safe_palette_size - 1.0);
	float u = (clamped_index + 0.5) / safe_palette_size;
	return texture(palette_texture, vec2(u, 0.5));
}

void fragment() {
	vec4 influence_data = texture(influence_map, UV);
	float influence_value = influence_data.r;
	float palette_index = round(influence_data.g);
	if (palette_index < 0.5) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(0.0);
		ALPHA = 0.0;
	} else {
		float fill_mask = smoothstep(threshold - fill_overlap, threshold + fill_softness, influence_value);
		vec4 map_color = sample_palette(palette_index);
		vec3 final_color = map_color.rgb * (0.72 + fill_mask * 0.28);
		ALBEDO = final_color;
		EMISSION = final_color * 0.16;
		ALPHA = clamp(fill_mask * fill_opacity * map_color.a, 0.0, 1.0);
	}
}
