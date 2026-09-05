extends Control
class_name GalaxyHudChrome

## Quiet, full-width command rail. No frame-by-frame redraw while idle.
var accent_color: Color = ObservatoryStyle.ACCENT
var _cluster_left: float = -1.0
var _cluster_right: float = -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_accent(next_accent_color: Color) -> void:
	accent_color = next_accent_color
	queue_redraw()

func set_cluster_bounds(left_edge: float, right_edge: float) -> void:
	_cluster_left = left_edge
	_cluster_right = right_edge
	queue_redraw()

func _draw() -> void:
	if size.x < 360.0 or size.y < 32.0:
		return
	var h := minf(size.y, 58.0)
	draw_rect(Rect2(0, 0, size.x, h), Color(0.016, 0.029, 0.044, 0.97))
	draw_line(Vector2(0, h), Vector2(size.x, h), ObservatoryStyle.EDGE, 1.0)
	draw_line(Vector2(18, h), Vector2(124, h), accent_color, 2.0)
	if _cluster_left > 145.0 and _cluster_right > _cluster_left:
		draw_line(Vector2(_cluster_left - 12, 14), Vector2(_cluster_left - 12, h - 14), ObservatoryStyle.EDGE, 1.0)
