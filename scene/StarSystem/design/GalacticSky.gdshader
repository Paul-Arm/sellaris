// Directional deep-space sky: a tilted galactic band, absorbing dust
// filaments and fine stars. Stable in world space and seeded per system.
shader_type sky;
uniform float seed_offset = 0.0;

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
	vec3 dir = normalize(EYEDIR);
	float angle = sin(seed_offset * 0.013) * 0.24;
	vec3 normal = normalize(vec3(0.32 + angle, 0.72, -0.65));
	vec3 tangent = normalize(cross(normal, vec3(0.0, 0.0, 1.0)));
	vec3 bitangent = cross(normal, tangent);
	vec3 p = vec3(dot(dir, tangent), dot(dir, normal), dot(dir, bitangent));
	vec3 seed = vec3(seed_offset * 0.037);
	float broad = sky_fbm(dir * 5.0 + seed);
	float detail = sky_fbm(dir * 26.0 + seed + vec3(41.0));
	float dust = sky_fbm(dir * 63.0 + seed + vec3(19.0));
	float latitude = p.y + (broad - 0.5) * 0.11;
	float band = exp(-pow(latitude / 0.105, 2.0));
	float outer = exp(-pow(latitude / 0.30, 2.0));
	// Broken dark lanes run through the luminous star clouds.
	float rift = exp(-pow((latitude + 0.018 + (detail - 0.5) * 0.065) / 0.021, 2.0));
	float transmission = (1.0 - rift * 0.82) * (0.35 + 0.65 * smoothstep(0.27, 0.72, dust));
	vec3 silver = mix(vec3(0.035, 0.047, 0.069), vec3(0.06, 0.064, 0.079), broad);
	vec3 col = vec3(0.0018, 0.0028, 0.0060);
	col += vec3(0.004, 0.007, 0.013) * outer;
	col += silver * band * transmission * (0.35 + detail * 0.65);
	// Small stars stay sharp; the distant population gathers in the band.
	col += star_layer(dir, 65.0, 440.0) * 0.62;
	col += star_layer(dir * 1.61 + vec3(31.0), 92.0, 380.0) * (0.12 + band * 0.34);
	COLOR = col;
}
