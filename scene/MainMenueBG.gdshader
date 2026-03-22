shader_type canvas_item;

uniform vec4 background_color : source_color = vec4(0.005, 0.008, 0.02, 1.0);
uniform vec4 core_color : source_color = vec4(0.42, 0.72, 1.0, 1.0);
uniform vec4 arm_color_a : source_color = vec4(0.32, 0.45, 0.95, 1.0);
uniform vec4 arm_color_b : source_color = vec4(0.88, 0.42, 0.78, 1.0);
uniform vec4 dust_color : source_color = vec4(0.03, 0.02, 0.06, 1.0);
uniform vec4 star_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);

uniform float galaxy_scale : hint_range(0.6, 1.8, 0.01) = 1.05;
uniform float galaxy_tilt : hint_range(0.1, 1.4, 0.01) = 0.58;
uniform float swirl : hint_range(0.0, 6.0, 0.01) = 3.1;
uniform float arm_count : hint_range(2.0, 6.0, 1.0) = 4.0;
uniform float nebula_strength : hint_range(0.0, 2.0, 0.01) = 1.15;
uniform float star_density : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float motion_speed : hint_range(0.0, 0.2, 0.001) = 0.02;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		v += noise2d(p) * a;
		p = p * 2.03 + vec2(17.1, 9.4);
		a *= 0.5;
	}
	return v;
}

float star_layer(vec2 uv, vec2 grid_scale, float threshold, float size_boost) {
	vec2 grid_uv = uv * grid_scale;
	vec2 cell = floor(grid_uv);
	vec2 local = fract(grid_uv) - 0.5;

	float rnd = hash12(cell);
	float star = smoothstep(threshold, 1.0, rnd);
	vec2 offset = vec2(hash12(cell + 3.1), hash12(cell + 7.3)) - 0.5;
	float d = length(local - offset * 0.35);
	float flare = smoothstep(size_boost, 0.0, d);
	return star * flare;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

	float t = TIME * motion_speed;

	vec2 galaxy_uv = uv / galaxy_scale;
	galaxy_uv.y /= max(galaxy_tilt, 0.001);

	float radius = length(galaxy_uv);
	float angle = atan(galaxy_uv.y, galaxy_uv.x);
	float twisted = angle + radius * swirl - t * 0.7;

	float arm_wave = 0.5 + 0.5 * cos(twisted * arm_count);
	float arm_mask = pow(arm_wave, 3.5);
	float disc_falloff = smoothstep(1.15, 0.12, radius);
	float core = smoothstep(0.42, 0.0, radius);

	vec2 flow_uv = vec2(cos(twisted), sin(twisted)) * radius;
	float nebula_large = fbm(flow_uv * 2.2 + vec2(t * 0.8, -t * 0.35));
	float nebula_small = fbm(flow_uv * 5.8 - vec2(t * 0.3, -t * 0.6));
	float nebula = (nebula_large * 0.75 + nebula_small * 0.25) * arm_mask * disc_falloff * nebula_strength;

	float dust_noise = fbm(flow_uv * 6.5 + 30.0);
	float dust_lanes = smoothstep(0.38, 0.82, dust_noise) * arm_mask * disc_falloff * 0.9;

	vec2 far_uv = UV + vec2(t * 0.006, t * 0.002);
	vec2 mid_uv = UV + vec2(t * 0.014, -t * 0.004);
	vec2 near_uv = UV + vec2(t * 0.028, -t * 0.011);

	float far_stars = star_layer(far_uv, vec2(170.0, 96.0), 0.992, 0.18);
	float mid_stars = star_layer(mid_uv, vec2(110.0, 62.0), 0.986, 0.22);
	float near_stars = star_layer(near_uv, vec2(72.0, 40.0), 0.978, 0.28);

	float star_field = far_stars * 0.45 + mid_stars * 0.75 + near_stars * 1.2;
	star_field *= star_density;

	vec3 color = background_color.rgb;

	vec3 arm_mix = mix(arm_color_a.rgb, arm_color_b.rgb, clamp(nebula_small * 1.25, 0.0, 1.0));
	color += arm_mix * nebula;
	color += core_color.rgb * core * 1.35;
	color = mix(color, dust_color.rgb, dust_lanes * 0.55);
	color += star_color.rgb * star_field;

	float halo = smoothstep(0.95, 0.0, radius) * 0.08;
	color += mix(core_color.rgb, arm_color_b.rgb, 0.4) * halo;

	COLOR = vec4(color, 1.0);
}
