// System view post-process, rebuilt from scratch. The celestial bodies carry
// their own pastel grading now, so this pass is only a gentle unifier:
// mild contrast around a low pivot, split toning (cool shadows / warm
// highlights), light saturation, a soft corner vignette and a pixel-true
// dither against gradient banding.
//
// Deliberately absent (they bleached and blurred the old look): full-frame
// box blur, additive color wash over dark pixels, posterize, heavy grain.
// Space stays dark, the image stays crisp.
shader_type canvas_item;

uniform float exposure : hint_range(0.7, 1.4) = 1.0;
uniform float contrast : hint_range(0.85, 1.25) = 1.10;
// Contrast pivot near black so the space background is not lifted.
uniform float black_pivot : hint_range(0.0, 0.5) = 0.085;
uniform float saturation : hint_range(0.5, 1.5) = 1.02;
uniform vec4 shadow_tint : source_color = vec4(0.72, 0.78, 1.0, 1.0);
uniform float shadow_tint_strength : hint_range(0.0, 0.5) = 0.08;
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.95, 0.86, 1.0);
uniform float highlight_tint_strength : hint_range(0.0, 0.5) = 0.035;
uniform float vignette_strength : hint_range(0.0, 0.4) = 0.08;
uniform float vignette_floor : hint_range(0.5, 1.0) = 0.88;
uniform float dither_strength : hint_range(0.0, 0.01) = 0.0035;

float luminance(vec3 color) {
	return dot(color, vec3(0.299, 0.587, 0.114));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec3 col = src.rgb * exposure;

	// Mild contrast around a low pivot: darks stay dark, mids gain punch.
	col = max((col - black_pivot) * contrast + black_pivot, vec3(0.0));

	float luma = luminance(col);

	// Shadows: multiplicative cool tint — shifts hue without lifting black
	// (the old shader's additive wash is what bleached the background).
	float shadow_mask = 1.0 - smoothstep(0.05, 0.45, luma);
	col = mix(col, col * shadow_tint.rgb, shadow_mask * shadow_tint_strength);

	// Highlights: pull toward warm white only where the frame is already bright.
	float highlight_mask = smoothstep(0.6, 0.95, luma);
	col = mix(col, highlight_tint.rgb, highlight_mask * highlight_tint_strength);

	col = mix(vec3(luminance(col)), col, saturation);

	vec2 centered_uv = UV * 2.0 - 1.0;
	float vignette = 1.0 - dot(centered_uv, centered_uv) * vignette_strength;
	col *= clamp(vignette, vignette_floor, 1.0);

	// Pixel-based (not UV-based) dither: invisible, prevents banding.
	col += (hash(FRAGCOORD.xy) - 0.5) * dither_strength;

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), src.a);
}
