shader_type spatial;

render_mode blend_mix, depth_draw_opaque, cull_back;

uniform float emission_strength : hint_range(0.0, 6.0) = 1.15;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.2;
uniform float rim_power : hint_range(0.2, 8.0) = 2.5;
uniform float saturation_boost : hint_range(0.0, 2.0) = 1.35;

void fragment() {
	vec3 base_color = COLOR.rgb;
	float luminance = dot(base_color, vec3(0.299, 0.587, 0.114));
	base_color = mix(vec3(luminance), base_color, saturation_boost);
	float view_dot = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - view_dot, rim_power) * rim_strength;
	vec3 lit_color = mix(base_color * 0.58, base_color * 1.08, max(NORMAL.y * 0.5 + 0.5, 0.0));
	ALBEDO = lit_color;
	EMISSION = base_color * (emission_strength + rim);
	ROUGHNESS = 0.16;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
