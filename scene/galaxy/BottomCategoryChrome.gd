extends Control
class_name BottomCategoryChrome

var accent_color: Color = ObservatoryStyle.ACCENT
var expanded_amount: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_state(next_accent_color: Color, is_expanded: bool) -> void:
	accent_color = next_accent_color
	expanded_amount = 1.0 if is_expanded else 0.0
	queue_redraw()

func _draw() -> void:
	if size.x < 64.0 or size.y < 28.0:
		return
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color(0.018, 0.032, 0.046, 0.97))
	draw_rect(bounds, ObservatoryStyle.EDGE, false, 1.0)
	draw_line(Vector2(0, 0), Vector2(size.x, 0), Color(accent_color, 0.35), 1.0)
	draw_line(Vector2(20, 0), Vector2(120, 0), accent_color, 2.0)
	if expanded_amount > 0.0:
		draw_line(Vector2(20, size.y - 8), Vector2(size.x - 20, size.y - 8), ObservatoryStyle.EDGE, 1.0)
