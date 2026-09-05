shader_type spatial;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(0.55, 0.83, 0.79, 1.0);
uniform bool emitter = false;
void fragment() {
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
	vec3 color = tint.rgb * mix(0.65, 1.0, max(dot(NORMAL, normalize(vec3(-0.4, 0.5, 0.8))), 0.0));
	if (emitter) { color = mix(tint.rgb, vec3(1.0), 0.75); }
	ALBEDO = color + tint.rgb * rim * 0.6;
	EMISSION = emitter ? tint.rgb * 1.5 : tint.rgb * rim * 0.3;
}
