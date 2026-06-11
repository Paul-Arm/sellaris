// Procedural backdrop for the system view: dark navy gradient, two seeded
// star layers and soft pastel nebula wisps with a very slow drift. Seeded per
// system (seed_offset) so every system shows its own sky, deterministically.
// Self-contained on purpose: celestial_common.gdshaderinc uses fwidth(),
// which is unavailable in the sky shader stage.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.06, 0.09, 0.17);
uniform vec3 bottom_color : source_color = vec3(0.035, 0.055, 0.105);
uniform vec3 nebula_color_a : source_color = vec3(0.45, 0.38, 0.62);
uniform vec3 nebula_color_b : source_color = vec3(0.24, 0.44, 0.54);
uniform float nebula_strength : hint_range(0.0, 0.5) = 0.14;
uniform float star_density = 26.0;
uniform float star_brightness : hint_range(0.0, 2.0) = 0.8;
uniform float seed_offset = 0.0;
uniform float drift_speed = 0.0025;

uint sky_pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

float sky_hash(vec3 lattice_point) {
	uvec3 q = uvec3(ivec3(lattice_point)) * uvec3(1597334673u, 3812015801u, 2798796415u);
	return float(sky_pcg(q.x ^ q.y ^ q.z)) * (1.0 / 4294967295.0);
}

vec3 sky_hash3(vec3 lattice_point) {
	uvec3 q = uvec3(ivec3(lattice_point)) * uvec3(1597334673u, 3812015801u, 2798796415u);
	uint n = q.x ^ q.y ^ q.z;
	return vec3(
		float(sky_pcg(n)) * (1.0 / 4294967295.0),
		float(sky_pcg(n ^ 0x68bc21ebu)) * (1.0 / 4294967295.0),
		float(sky_pcg(n ^ 0x2c1b3c6du)) * (1.0 / 4294967295.0)
	);
}

float sky_vnoise(vec3 p) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	vec3 u = fp * fp * fp * (fp * (fp * 6.0 - 15.0) + 10.0);
	float n000 = sky_hash(ip);
	float n100 = sky_hash(ip + vec3(1.0, 0.0, 0.0));
	float n010 = sky_hash(ip + vec3(0.0, 1.0, 0.0));
	float n110 = sky_hash(ip + vec3(1.0, 1.0, 0.0));
	float n001 = sky_hash(ip + vec3(0.0, 0.0, 1.0));
	float n101 = sky_hash(ip + vec3(1.0, 0.0, 1.0));
	float n011 = sky_hash(ip + vec3(0.0, 1.0, 1.0));
	float n111 = sky_hash(ip + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z);
}

float sky_fbm(vec3 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	float norm = 0.0;
	vec3 q = p;
	for (int i = 0; i < 4; i++) {
		sum += amplitude * sky_vnoise(q);
		norm += amplitude;
		q = q * 2.03 + vec3(17.3, 9.1, 23.7);
		amplitude *= 0.5;
	}
	return sum / norm;
}

vec3 star_layer(vec3 dir, float density, float dot_sharpness) {
	vec3 p = dir * density + vec3(seed_offset);
	vec3 id = floor(p);
	vec3 f = fract(p);
	// ~18% of cells host a star, placed away from cell borders.
	float presence = step(0.82, sky_hash(id + vec3(7.0)));
	vec3 star_pos = sky_hash3(id) * 0.7 + vec3(0.15);
	float dist = length(f - star_pos);
	float glow = presence * exp(-dist * dist * dot_sharpness);
	vec3 tint = mix(vec3(1.0, 0.95, 0.88), vec3(0.78, 0.87, 1.0), sky_hash(id + vec3(13.0)));
	return tint * glow;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 col = mix(bottom_color, top_color, clamp(dir.y * 0.5 + 0.5, 0.0, 1.0));

	// Slow-drifting pastel nebula wisps.
	vec3 p = dir * 2.3 + vec3(seed_offset * 0.01);
	p += vec3(TIME * drift_speed, TIME * drift_speed * 0.6, 0.0);
	float n1 = sky_fbm(p * 1.7);
	float n2 = sky_fbm(p * 3.1 + vec3(17.0));
	col += nebula_color_a * smoothstep(0.5, 0.85, n1) * nebula_strength * (0.6 + 0.4 * n2);
	col += nebula_color_b * smoothstep(0.55, 0.9, n2) * nebula_strength * 0.7;

	// Two star layers at different scales for depth.
	col += star_layer(dir, star_density, 240.0) * star_brightness;
	col += star_layer(dir * 1.61 + vec3(31.0), star_density * 2.1, 420.0) * star_brightness * 0.55;

	COLOR = col;
}
