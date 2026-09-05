extends RefCounted
class_name ObservatoryStyle

## Shared visual tokens. Semantic warning/empire colors remain with callers.
const SURFACE := Color(0.026, 0.044, 0.064, 0.96)
const EDGE := Color(0.16, 0.28, 0.33, 0.85)
const ACCENT := Color(0.38, 0.86, 0.74)
const GOLD := Color(0.86, 0.73, 0.46)
const TEXT := Color(0.88, 0.94, 0.94)
const MUTED := Color(0.49, 0.67, 0.72)

static func panel(fill: Color = SURFACE, edge: Color = EDGE, radius: int = 3, border: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE.lerp(fill, 0.22)
	style.bg_color.a = maxf(fill.a, 0.92)
	style.border_color = EDGE.lerp(edge, 0.45)
	style.set_border_width_all(border)
	style.set_corner_radius_all(mini(radius, 3))
	return style
