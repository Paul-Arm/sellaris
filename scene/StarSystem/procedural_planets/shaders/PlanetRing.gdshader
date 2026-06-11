// Planetary rings on the shared annulus mesh (UV.y = radial 0 inner -> 1
// outer). Radial fbm banding, one seeded Cassini-style gap, soft edge fades
// and an analytic cylinder shadow where the planet (at the model origin)
// blocks the sun — no shadow mapping, hue-shifted instead of black.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "celestial_common.gdshaderinc"

uniform vec3 palette_a = vec3(0.7, 0.66, 0.6);
uniform vec3 palette_b = vec3(0.12, 0.1, 0.1);
uniform vec3 palette_c = vec3(0.6, 0.6, 0.6);
uniform vec3 palette_d = vec3(0.1, 0.15, 0.2);
uniform float band_frequency = 9.0;
uniform float band_seed = 0.0;
uniform float ring_inner_fraction = 0.1;
uniform float ring_outer_fraction = 1.0;
uniform float gap_position = 0.55;
uniform float gap_width = 0.07;
uniform float gap_depth = 0.85;
uniform float ring_opacity = 0.68;
uniform float planet_radius = 1.0;
uniform float pastel_sat_max = 0.25;
uniform float pastel_val_min = 0.4;
uniform float pastel_val_max = 0.9;
uniform vec3 shadow_tint : source_color = vec3(0.6, 0.62, 0.88);

varying vec3 v_world_pos;
varying vec2 v_uv;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
}

void fragment() {
	float band_pos = (v_uv.y - ring_inner_fraction) / max(ring_outer_fraction - ring_inner_fraction, 0.001);
	if (band_pos < 0.0 || band_pos > 1.0) {
		discard;
	}

	float bands = cb_fbm3(vec3(band_pos * band_frequency, band_seed * 37.0, band_seed * 11.0), 4);
	float density = smoothstep(0.28, 0.5, bands);
	float edge_fade = smoothstep(0.0, 0.08, band_pos) * (1.0 - smoothstep(0.9, 1.0, band_pos));
	float gap_delta = (band_pos - gap_position) / max(gap_width, 0.001);
	float gap = 1.0 - gap_depth * exp(-gap_delta * gap_delta);

	vec3 col = cb_cosine_palette(0.3 + 0.5 * bands, palette_a, palette_b, palette_c, palette_d);
	col = cb_pastelize(col, pastel_sat_max, pastel_val_min, pastel_val_max);

	vec3 sun_dir = cb_resolve_sun_dir(v_world_pos);
	// Rings scatter light through: wrap on the absolute plane-normal angle.
	vec3 ring_normal = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float w = abs(dot(ring_normal, sun_dir)) * 0.6 + 0.4;
	float ramp = cb_toon_ramp(w, 0.35, 0.62, 0.10, 0.16, 0.4);
	col = mix(col * shadow_tint, col, ramp);

	// Analytic planet shadow: distance from the anti-sun axis through the
	// planet center (model origin), soft penumbra, never black.
	vec3 planet_center = MODEL_MATRIX[3].xyz;
	vec3 rel = v_world_pos - planet_center;
	float along = dot(rel, -sun_dir);
	float radial = length(rel + sun_dir * along);
	float shade = (1.0 - smoothstep(planet_radius * 0.85, planet_radius * 1.1, radial)) * step(0.0, along);
	col = mix(col, col * shadow_tint * 0.45, shade);

	ALBEDO = col;
	ALPHA = density * edge_fade * gap * ring_opacity;
}
