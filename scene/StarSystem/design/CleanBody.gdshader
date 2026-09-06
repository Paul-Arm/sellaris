shader_type spatial;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(0.55, 0.83, 0.79, 1.0);
uniform bool emitter = false;
uniform int body_kind = 0;
uniform float pattern_seed = 0.0;
uniform vec3 sun_position = vec3(0.0, 12.0, 0.0);
varying vec3 sphere_position;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	sphere_position = normalize(VERTEX);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float facing = max(dot(n, VIEW), 0.0);
	float rim = pow(1.0 - facing, 3.0);
	float daylight = smoothstep(-0.15, 0.7, dot(normalize(world_normal), normalize(sun_position - world_position)));
	// Clean luminous ceramic globes. Broad, low-contrast marks distinguish
	// types without noisy terrain, external rings or a dark brown night side.
	vec3 p = normalize(sphere_position);
	float seed = pattern_seed;
	vec3 axis = normalize(vec3(sin(seed * 1.7) * 0.45, 1.0, cos(seed) * 0.4));
	float latitude = dot(p, axis);
	float pattern = sin(dot(p, vec3(2.1, 3.2, 1.7)) + seed) * cos(dot(p, vec3(-1.8, 1.3, 2.5)) - seed);
	if (body_kind == 2) { pattern = sin(latitude * 17.0 + sin(latitude * 5.0 + seed) * 1.3); }
	if (body_kind == 3) { pattern = sin(dot(p, vec3(3.0, 1.2, 2.0)) + seed) * 0.55; }
	float material_variation = 0.92 + 0.08 * smoothstep(-0.6, 0.6, pattern);
	vec3 neutral_tint = mix(vec3(dot(tint.rgb, vec3(0.3, 0.59, 0.11))), tint.rgb, 0.35);
	vec3 pearl = mix(tint.rgb, vec3(0.82, 0.9, 1.0), 0.4);
	vec3 color = pearl * (0.22 + 0.36 * daylight) * material_variation;
	color += pearl * rim * 0.22;
	EMISSION = pearl * 0.06;
	if (emitter) {
		// HDR core feeds bloom; smooth limb shading preserves the sphere.
		vec3 core = mix(neutral_tint, vec3(1.0, 0.96, 0.99), 0.82);
		EMISSION = core * (1.7 + 0.8 * pow(facing, 0.6));
		color = core * 0.65;
	}
	if (!emitter && max(tint.r, max(tint.g, tint.b)) < 0.03) { color = tint.rgb; EMISSION = vec3(0.0); }
	// Unshaded materials output ALBEDO directly, including HDR radiance.
	ALBEDO = color + EMISSION;
}
