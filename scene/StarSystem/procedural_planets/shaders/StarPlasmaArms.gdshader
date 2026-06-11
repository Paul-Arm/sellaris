// True-3D solar prominence: shades the half-torus arc tube from
// CelestialMeshLibrary.get_prominence_arc(). The arc grows out of the star
// surface from its feet, holds, and collapses again (lifecycle in-shader);
// plasma flows along the tube and a vertex wobble keeps the arm flexing.
// One material instance per arm with its own phase. UV.x = along the arc
// (0 foot -> 0.5 apex -> 1 foot), UV.y = around the tube.
//
// Alpha-mix on purpose (NOT additive): additive arcs vanish in front of the
// HDR-bright disc, which made the feet look disconnected. Mixed arcs read as
// filaments against the disc and as glowing plasma against space.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;

#include "celestial_common.gdshaderinc"

uniform vec4 plasma_color : source_color = vec4(1.0, 0.82, 0.5, 0.85);
uniform vec4 plasma_tip_color : source_color = vec4(1.0, 0.6, 0.55, 1.0);
// Eruption cycles per second: each cycle = burst -> hold -> collapse -> rest.
uniform float life_speed = 0.08;
uniform float flow_speed = 1.0;
uniform float noise_scale = 3.0;
uniform float wobble_amount = 0.16;
uniform float phase_offset = 0.0;
uniform float intensity = 1.6;

varying vec2 v_uv;
varying float v_life;
varying float v_burst;

void vertex() {
	v_uv = UV;
	// Eruption envelope: fast pop with overshoot, flickering hold, collapse,
	// dormant pause — instead of a gentle sine breath. Inlined because
	// varyings cannot be written through out-parameters of helper functions.
	float cycle = fract(TIME * life_speed + phase_offset * 0.061);
	float rise = smoothstep(0.0, 0.055, cycle);
	float fall = 1.0 - smoothstep(0.48, 0.7, cycle);
	float pop = (cycle - 0.075) / 0.05;
	v_burst = exp(-pop * pop) * 0.35;
	v_life = clamp(rise * fall + v_burst, 0.0, 1.3);

	// Flexible flame motion: displace along the tube normal, strongest at
	// the apex, anchored (still) at the feet — extra shake during the burst.
	float arch = sin(UV.x * 3.14159265);
	float wobble = cb_fbm3(vec3(UV.x * 3.0 - TIME * 0.85, UV.y * 0.5, phase_offset * 0.13), 3) - 0.5;
	VERTEX += NORMAL * wobble * wobble_amount * arch * (1.0 + v_burst * 2.0);
}

void fragment() {
	// 0 at the feet, 1 at the apex.
	float arch = sin(v_uv.x * 3.14159265);

	// The arc grows from its feet at the eruption pop and sinks back during
	// the collapse; fragments above the current growth height vanish.
	float grown = smoothstep(arch - 0.22, arch + 0.05, v_life * 1.05);

	// Plasma streaming along the tube.
	float plasma = cb_fbm3(vec3(v_uv.x * noise_scale * 2.0 - TIME * flow_speed, v_uv.y * 1.5, phase_offset), 4);
	plasma = 0.5 + 0.5 * plasma;

	vec3 col = mix(plasma_color.rgb, plasma_tip_color.rgb, arch);
	// Slightly HDR so arcs bloom against space while staying visible (a bit
	// darker than the disc) when they cross in front of the star; brightness
	// spikes during the burst.
	ALBEDO = col * (0.9 + 0.7 * plasma) * intensity * mix(1.0, 0.8, arch) * (1.0 + v_burst * 1.6);
	ALPHA = grown * clamp(0.55 + 0.5 * plasma, 0.0, 1.0) * plasma_color.a;
}
