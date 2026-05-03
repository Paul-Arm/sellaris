extends Control
class_name BottomCategoryChrome

var accent_color: Color = Color(0.56, 0.84, 1.0, 1.0)
var expanded_amount: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func set_state(next_accent_color: Color, is_expanded: bool) -> void:
	accent_color = next_accent_color
	expanded_amount = 1.0 if is_expanded else 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if visible and expanded_amount > 0.01:
		queue_redraw()


func _draw() -> void:
	if size.x < 64.0 or size.y < 28.0:
		return

	var points := _build_tray_points(Vector2.ZERO)
	var shadow_points := _build_tray_points(Vector2(0.0, 8.0))
	var base_alpha := lerpf(0.74, 0.9, expanded_amount)
	var edge_alpha := lerpf(0.2, 0.48, expanded_amount)

	draw_colored_polygon(shadow_points, Color(0.0, 0.0, 0.0, 0.28))
	draw_colored_polygon(points, Color(0.018, 0.03, 0.04, base_alpha))
	draw_polyline(_closed_points(points), Color(0.28, 0.52, 0.66, edge_alpha), 1.5, true)

	var accent := accent_color
	_draw_top_rails(accent)

	var left_wing := PackedVector2Array([
		Vector2(20.0, size.y * 0.5),
		Vector2(56.0, 14.0),
		Vector2(74.0, 18.0),
		Vector2(42.0, size.y - 18.0),
	])
	var right_wing := PackedVector2Array([
		Vector2(size.x - 20.0, size.y * 0.5),
		Vector2(size.x - 56.0, 14.0),
		Vector2(size.x - 74.0, 18.0),
		Vector2(size.x - 42.0, size.y - 18.0),
	])
	draw_colored_polygon(left_wing, Color(accent.r, accent.g, accent.b, 0.07))
	draw_colored_polygon(right_wing, Color(accent.r, accent.g, accent.b, 0.07))

	_draw_corner_node(Vector2(42.0, size.y - 18.0), accent)
	_draw_corner_node(Vector2(size.x - 42.0, size.y - 18.0), accent)

	if expanded_amount > 0.01:
		var pulse := 0.35 + sin(_time * TAU * 0.35) * 0.18
		draw_circle(
			Vector2(size.x * 0.5, size.y - 9.0),
			2.0 + pulse,
			Color(accent.r, accent.g, accent.b, 0.2 * expanded_amount)
		)


func _build_tray_points(offset: Vector2) -> PackedVector2Array:
	var top_y := 9.0
	var bottom_y := size.y - 5.0
	return PackedVector2Array([
		Vector2(50.0, top_y) + offset,
		Vector2(size.x - 50.0, top_y) + offset,
		Vector2(size.x - 14.0, 31.0) + offset,
		Vector2(size.x - 34.0, bottom_y) + offset,
		Vector2(size.x * 0.58, bottom_y + 4.0) + offset,
		Vector2(size.x * 0.42, bottom_y + 4.0) + offset,
		Vector2(34.0, bottom_y) + offset,
		Vector2(14.0, 31.0) + offset,
	])


func _draw_top_rails(color: Color) -> void:
	var rail_color := Color(color.r, color.g, color.b, 0.48)
	var ghost_color := Color(0.78, 0.92, 1.0, 0.1)
	draw_line(Vector2(62.0, 13.0), Vector2(size.x * 0.34, 13.0), rail_color, 2.0, true)
	draw_line(Vector2(size.x * 0.66, 13.0), Vector2(size.x - 62.0, 13.0), rail_color, 2.0, true)
	draw_line(Vector2(84.0, 18.0), Vector2(size.x * 0.31, 18.0), ghost_color, 1.0, true)
	draw_line(Vector2(size.x * 0.69, 18.0), Vector2(size.x - 84.0, 18.0), ghost_color, 1.0, true)


func _draw_corner_node(center: Vector2, color: Color) -> void:
	draw_circle(center, 4.0, Color(color.r, color.g, color.b, 0.42))
	draw_circle(center, 1.8, Color(0.86, 0.96, 1.0, 0.72))


func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if not points.is_empty():
		closed.append(points[0])
	return closed
