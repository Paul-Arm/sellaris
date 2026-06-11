// Shared library for the 3D celestial body shaders (pastel / painterly style).
//
// Contract for planet surface shaders (future equirect bake seam):
// the surface pattern must be a pure function of the MODEL-SPACE unit
// direction (varying computed as normalize(VERTEX) in vertex()) and seeded
// uniforms — never of lighting, view, world position or TIME. Lighting is
// applied separately via cb_pastel_light(). A future colony-view baker can
// then render the identical pattern through a UV->direction wrapper.
//
// All functions are prefixed cb_ to avoid collisions.

#ifndef CELESTIAL_COMMON_INC
#define CELESTIAL_COMMON_INC

// --- Sun model -------------------------------------------------------------
// sun_mode 0: fixed direction (own-world previews: details panel, colony
// modal). sun_mode 1: point source at sun_position (system view; set via
// ProceduralPlanetVisual.set_sun_world_position with the primary star).
uniform float sun_mode : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_direction = vec3(0.56, 0.41, 0.72);
uniform vec3 sun_position = vec3(0.0, 0.0, 0.0);

vec3 cb_resolve_sun_dir(vec3 world_pos) {
	vec3 toward_sun = sun_position - world_pos;
	vec3 point_dir = toward_sun / max(length(toward_sun), 0.0001);
	return normalize(mix(normalize(sun_direction), point_dir, clamp(sun_mode, 0.0, 1.0)));
}

// --- Hashing (sin-free, stable on all GPUs) --------------------------------

uint cb_pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

float cb_hash_lattice(vec3 lattice_point) {
	uvec3 q = uvec3(ivec3(lattice_point)) * uvec3(1597334673u, 3812015801u, 2798796415u);
	return float(cb_pcg(q.x ^ q.y ^ q.z)) * (1.0 / 4294967295.0);
}

float cb_hash11(float p) {
	return float(cb_pcg(floatBitsToUint(p))) * (1.0 / 4294967295.0);
}

vec3 cb_hash33(vec3 lattice_point) {
	uvec3 q = uvec3(ivec3(lattice_point)) * uvec3(1597334673u, 3812015801u, 2798796415u);
	uint n = q.x ^ q.y ^ q.z;
	return vec3(
		float(cb_pcg(n)) * (1.0 / 4294967295.0),
		float(cb_pcg(n ^ 0x68bc21ebu)) * (1.0 / 4294967295.0),
		float(cb_pcg(n ^ 0x2c1b3c6du)) * (1.0 / 4294967295.0)
	);
}

// --- Noise ------------------------------------------------------------------

// 3D value noise, quintic fade, range [0, 1].
float cb_vnoise3(vec3 p) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	vec3 u = fp * fp * fp * (fp * (fp * 6.0 - 15.0) + 10.0);
	float n000 = cb_hash_lattice(ip);
	float n100 = cb_hash_lattice(ip + vec3(1.0, 0.0, 0.0));
	float n010 = cb_hash_lattice(ip + vec3(0.0, 1.0, 0.0));
	float n110 = cb_hash_lattice(ip + vec3(1.0, 1.0, 0.0));
	float n001 = cb_hash_lattice(ip + vec3(0.0, 0.0, 1.0));
	float n101 = cb_hash_lattice(ip + vec3(1.0, 0.0, 1.0));
	float n011 = cb_hash_lattice(ip + vec3(0.0, 1.0, 1.0));
	float n111 = cb_hash_lattice(ip + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	float nxy0 = mix(nx00, nx10, u.y);
	float nxy1 = mix(nx01, nx11, u.y);
	return mix(nxy0, nxy1, u.z);
}

float cb_fbm3(vec3 p, int octaves) {
	float sum = 0.0;
	float amplitude = 0.5;
	float norm = 0.0;
	vec3 q = p;
	for (int i = 0; i < 8; i++) {
		if (i >= octaves) {
			break;
		}
		sum += amplitude * cb_vnoise3(q);
		norm += amplitude;
		q = q * 2.03 + vec3(17.3, 9.1, 23.7);
		amplitude *= 0.5;
	}
	return sum / max(norm, 0.0001);
}

// fbm with the high octaves fading out before they alias (fragment-only:
// uses screen-space derivatives). Use for fine detail at far zoom.
float cb_fbm3_aa(vec3 p, int octaves) {
	float pixel_footprint = length(fwidth(p));
	float sum = 0.0;
	float amplitude = 0.5;
	float norm = 0.0;
	vec3 q = p;
	float frequency = 1.0;
	for (int i = 0; i < 8; i++) {
		if (i >= octaves) {
			break;
		}
		float fade = 1.0 - smoothstep(0.25, 0.5, frequency * pixel_footprint);
		sum += amplitude * fade * cb_vnoise3(q);
		norm += amplitude;
		q = q * 2.03 + vec3(17.3, 9.1, 23.7);
		amplitude *= 0.5;
		frequency *= 2.03;
	}
	return sum / max(norm, 0.0001);
}

// Ridged fbm for cracks, lava veins, mountain lines. Range [0, 1].
float cb_ridged3(vec3 p, int octaves) {
	float sum = 0.0;
	float amplitude = 0.5;
	float norm = 0.0;
	vec3 q = p;
	for (int i = 0; i < 8; i++) {
		if (i >= octaves) {
			break;
		}
		float n = 1.0 - abs(2.0 * cb_vnoise3(q) - 1.0);
		sum += amplitude * n * n;
		norm += amplitude;
		q = q * 2.03 + vec3(13.9, 27.1, 7.7);
		amplitude *= 0.5;
	}
	return sum / max(norm, 0.0001);
}

vec3 cb_warp3(vec3 p, float amp, float freq, vec3 seed_offset) {
	return p + amp * (vec3(
		cb_fbm3(p * freq + seed_offset + vec3(31.7, 0.0, 0.0), 3),
		cb_fbm3(p * freq + seed_offset + vec3(0.0, 47.3, 0.0), 3),
		cb_fbm3(p * freq + seed_offset + vec3(0.0, 0.0, 59.1), 3)
	) - vec3(0.5));
}

// 3D cellular noise. Returns (F1 distance, cell id hash in [0, 1]).
vec2 cb_voronoi3(vec3 p) {
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float best_dist = 8.0;
	float best_id = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 cell = vec3(float(x), float(y), float(z));
				vec3 feature = cell + cb_hash33(ip + cell) - fp;
				float dist = dot(feature, feature);
				if (dist < best_dist) {
					best_dist = dist;
					best_id = cb_hash_lattice(ip + cell);
				}
			}
		}
	}
	return vec2(sqrt(best_dist), best_id);
}

// --- Palette / color --------------------------------------------------------

// IQ cosine palette — identical math to CelestialBodyPalette.gd.
vec3 cb_cosine_palette(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
	return a + b * cos(6.28318530718 * (c * t + d));
}

vec3 cb_rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 cb_hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Pastel discipline backstop: cap saturation, clamp value into a soft window.
vec3 cb_pastelize(vec3 col, float sat_max, float val_min, float val_max) {
	vec3 hsv = cb_rgb2hsv(clamp(col, vec3(0.0), vec3(1.0)));
	hsv.y = min(hsv.y, sat_max);
	hsv.z = clamp(hsv.z, val_min, val_max);
	return cb_hsv2rgb(hsv);
}

vec3 cb_shift_saturation(vec3 col, float amount) {
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	return mix(vec3(luma), col, amount);
}

// --- Shaping ----------------------------------------------------------------

float cb_fresnel(vec3 n, vec3 v, float power) {
	return pow(clamp(1.0 - dot(normalize(n), normalize(v)), 0.0, 1.0), power);
}

// fwidth-self-widening threshold: edges stay soft instead of shimmering as
// the body shrinks on screen. Fragment-only.
float cb_soft_threshold(float value, float threshold, float min_softness) {
	float softness = max(min_softness, fwidth(value) * 1.5);
	return smoothstep(threshold - softness, threshold + softness, value);
}

// Soft 3-step toon ramp over a half-lambert weight w in [0, 1].
float cb_toon_ramp(float w, float step_1, float step_2, float width_1, float width_2, float shadow_floor) {
	float lit_1 = smoothstep(step_1 - width_1, step_1 + width_1, w);
	float lit_2 = smoothstep(step_2 - width_2, step_2 + width_2, w);
	return shadow_floor + (1.0 - shadow_floor) * (0.55 * lit_1 + 0.45 * lit_2);
}

// --- House lighting style ----------------------------------------------------
// Half-lambert wrap -> soft toon ramp; shadow side hue-shifts toward cool
// violet (never black); saturation boost in the terminator band; gentle rim
// light on the day side only. Pure math, independent of Godot lights.
vec3 cb_pastel_light(
	vec3 albedo,
	vec3 world_normal,
	vec3 sun_dir,
	vec3 view_dir,
	vec3 shadow_tint,
	float shadow_floor,
	vec3 rim_color,
	float rim_strength,
	float rim_power
) {
	float d = dot(normalize(world_normal), normalize(sun_dir));
	float w = d * 0.5 + 0.5;
	float ramp = cb_toon_ramp(w, 0.35, 0.62, 0.10, 0.16, shadow_floor);
	vec3 col = mix(albedo * shadow_tint, albedo, ramp);
	float terminator = 1.0 - smoothstep(0.0, 0.25, abs(d));
	col = cb_shift_saturation(col, 1.0 + 0.15 * terminator);
	float rim = cb_fresnel(world_normal, view_dir, rim_power) * smoothstep(0.0, 0.35, d);
	return col + rim_color * rim * rim_strength;
}

// --- Misc --------------------------------------------------------------------

vec3 cb_rotate_y(vec3 p, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

mat3 cb_axis_rotation(vec3 axis, float angle) {
	axis = normalize(axis);
	float s = sin(angle);
	float c = cos(angle);
	float oc = 1.0 - c;
	return mat3(
		vec3(oc * axis.x * axis.x + c, oc * axis.x * axis.y + axis.z * s, oc * axis.z * axis.x - axis.y * s),
		vec3(oc * axis.x * axis.y - axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z + axis.x * s),
		vec3(oc * axis.z * axis.x + axis.y * s, oc * axis.y * axis.z - axis.x * s, oc * axis.z * axis.z + c)
	);
}

// Latitude in [-1, 1] (poles at +/-1) from a model-space unit direction.
float cb_latitude(vec3 dir) {
	return clamp(dir.y, -1.0, 1.0);
}

#endif // CELESTIAL_COMMON_INC
