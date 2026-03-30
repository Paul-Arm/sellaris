shader_type canvas_item;

uniform vec4 warm_tint : source_color = vec4(1.0, 0.83, 0.72, 1.0);
uniform vec4 cool_tint : source_color = vec4(0.57, 0.84, 1.0, 1.0);
uniform vec4 highlight_tint : source_color = vec4(0.96, 0.8, 0.9, 1.0);
uniform float softness : hint_range(0.0, 1.0) = 0.38;
uniform float wash_strength : hint_range(0.0, 1.0) = 0.52;
uniform float edge_glow : hint_range(0.0, 1.0) = 0.2;
uniform float posterize_steps : hint_range(3.0, 12.0) = 6.0;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.045;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.18;
uniform float saturation_boost : hint_range(0.5, 1.5) = 1.08;

float luminance(vec3 color) {
	return dot(color, vec3(0.299, 0.587, 0.114));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec3 saturate_color(vec3 color, float amount) {
	float gray = luminance(color);
	return mix(vec3(gray), color, amount);
}

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec4 src = texture(TEXTURE, UV);
	vec3 blur = (
		texture(TEXTURE, UV + vec2(texel.x, 0.0)).rgb +
		texture(TEXTURE, UV - vec2(texel.x, 0.0)).rgb +
		texture(TEXTURE, UV + vec2(0.0, texel.y)).rgb +
		texture(TEXTURE, UV - vec2(0.0, texel.y)).rgb
	) * 0.25;

	vec3 softened = mix(src.rgb, blur, softness);
	float lightness = luminance(softened);
	float cool_mix = smoothstep(0.12, 0.88, 1.0 - lightness) * 0.5 + 0.15;
	float warm_mix = smoothstep(0.18, 0.95, lightness) * 0.5 + 0.12;
	vec3 pastel = softened;
	pastel = mix(pastel, cool_tint.rgb, cool_mix * wash_strength);
	pastel = mix(pastel, warm_tint.rgb, warm_mix * wash_strength);
	pastel = mix(pastel, highlight_tint.rgb, pow(max(lightness, 0.0), 1.8) * 0.2);

	vec3 quantized = floor(pastel * posterize_steps) / posterize_steps;
	pastel = mix(pastel, quantized, 0.24);
	pastel = saturate_color(pastel, saturation_boost);

	float edge = distance(src.rgb, blur);
	pastel += edge * edge_glow * vec3(0.18, 0.16, 0.12);

	float grain = hash(UV * vec2(1240.0, 860.0)) - 0.5;
	pastel += grain * grain_strength;

	vec2 centered_uv = UV * 2.0 - 1.0;
	float vignette = 1.0 - dot(centered_uv, centered_uv) * vignette_strength;
	pastel *= clamp(vignette, 0.72, 1.0);

	COLOR = vec4(clamp(pastel, vec3(0.0), vec3(1.0)), src.a);
}
