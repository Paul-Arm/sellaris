shader_type canvas_item;
render_mode unshaded, blend_disabled;
#include "res://scene/StarSystem/design/MapDirectLight.gdshaderinc"
void fragment() {
	float angle = (FRAGCOORD.x - 0.5) / 64.0 * 6.28318530718;
	float radius = 12.0 + floor(FRAGCOORD.y) * 4.0;
	COLOR = vec4(map_direct_light(vec2(cos(angle), sin(angle)) * radius) * 8.0, 1.0);
}
