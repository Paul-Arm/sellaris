shader_type spatial;
render_mode blend_mix, depth_draw_never, unshaded, cull_disabled;

uniform float fresnel_power = 1.85;
uniform float center_alpha = 0.1;
uniform float edge_alpha = 0.26;
uniform float emission_strength = 1.0;
uniform float pulse_strength = 0.08;
uniform float pulse_speed = 0.75;
uniform float noise_scale = 0.018;

varying vec3 world_pos;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float fresnel = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), fresnel_power);
	float pulse = 1.0 + sin(TIME * pulse_speed + world_pos.x * noise_scale + world_pos.z * noise_scale * 0.73) * pulse_strength;
	float alpha = mix(center_alpha, edge_alpha, fresnel) * COLOR.a * pulse;

	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * (emission_strength + fresnel * 0.85) * pulse;
	ALPHA = alpha;
}
