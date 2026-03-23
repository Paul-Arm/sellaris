shader_type spatial;

render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float fresnel_power : hint_range(0.2, 8.0) = 2.8;
uniform float glow_strength : hint_range(0.0, 8.0) = 2.4;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.12;
uniform float pulse_speed : hint_range(0.0, 8.0) = 1.6;
uniform float center_fill : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec4 final_color = glow_color * COLOR;
	float view_dot = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - view_dot, fresnel_power);
	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_strength;
	float halo = max(fresnel, center_fill);
	vec3 emission = final_color.rgb * halo * glow_strength * pulse;
	EMISSION = emission;
	ALBEDO = final_color.rgb * 0.14;
	ALPHA = clamp(halo * final_color.a * 0.9, 0.0, 1.0);
}
