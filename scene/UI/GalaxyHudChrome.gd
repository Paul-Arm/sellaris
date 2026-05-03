extends Control
class_name GalaxyHudChrome

var accent_color: Color = Color(0.56, 0.84, 1.0, 1.0)
var _cluster_left: float = -1.0
var _cluster_right: float = -1.0
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func set_accent(next_accent_color: Color) -> void:
	accent_color = next_accent_color
	queue_redraw()


func set_cluster_bounds(left_edge: float, right_edge: float) -> void:
	_cluster_left = left_edge
	_cluster_right = right_edge
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if visible:
		queue_redraw()


func _draw() -> void:
	if size.x < 360.0 or size.y < 32.0:
		return

	var panel_height: float = minf(size.y, 56.0)
	var right_edge := size.x - 14.0
	var left_edge := _cluster_left
	if left_edge < 0.0 or _cluster_right <= left_edge:
		var max_cluster_width := maxf(260.0, size.x - 40.0)
		var min_cluster_width := minf(840.0, max_cluster_width)
		var cluster_width := clampf(size.x * 0.78, min_cluster_width, max_cluster_width)
		left_edge = right_edge - cluster_width
	else:
		right_edge = _cluster_right
	left_edge = clampf(left_edge, 18.0, maxf(18.0, size.x - 280.0))
	right_edge = clampf(right_edge, left_edge + 260.0, size.x - 14.0)
	var tray_points := _build_tray_points(left_edge, right_edge, panel_height, Vector2.ZERO)
	var shadow_points := _build_tray_points(left_edge, right_edge, panel_height, Vector2(0.0, 5.0))

	draw_colored_polygon(shadow_points, Color(0.0, 0.0, 0.0, 0.22))
	draw_colored_polygon(tray_points, Color(0.018, 0.03, 0.04, 0.74))
	draw_polyline(_closed_points(tray_points), Color(0.28, 0.52, 0.66, 0.34), 1.4, true)

	var accent := accent_color
	var rail_y := 7.0
	draw_line(Vector2(18.0, rail_y), Vector2(left_edge - 28.0, rail_y), Color(accent.r, accent.g, accent.b, 0.18), 1.2, true)
	draw_line(Vector2(left_edge + 46.0, rail_y), Vector2(right_edge - 38.0, rail_y), Color(accent.r, accent.g, accent.b, 0.44), 2.0, true)
	draw_line(Vector2(left_edge + 76.0, rail_y + 5.0), Vector2(right_edge - 72.0, rail_y + 5.0), Color(0.78, 0.92, 1.0, 0.1), 1.0, true)

	var pulse := 0.32 + sin(_time * TAU * 0.45) * 0.18
	_draw_node(Vector2(left_edge + 36.0, panel_height - 10.0), accent, pulse)
	_draw_node(Vector2(right_edge - 34.0, panel_height - 10.0), accent, pulse)

	var slash_color := Color(accent.r, accent.g, accent.b, 0.08)
	draw_line(Vector2(left_edge + 22.0, panel_height - 4.0), Vector2(left_edge + 86.0, 13.0), slash_color, 3.0, true)
	draw_line(Vector2(right_edge - 22.0, panel_height - 4.0), Vector2(right_edge - 86.0, 13.0), slash_color, 3.0, true)


func _build_tray_points(left_edge: float, right_edge: float, height: float, offset: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(left_edge + 48.0, 2.0) + offset,
		Vector2(right_edge - 22.0, 2.0) + offset,
		Vector2(right_edge, 15.0) + offset,
		Vector2(right_edge - 18.0, height - 5.0) + offset,
		Vector2(left_edge + 20.0, height - 5.0) + offset,
		Vector2(left_edge, 16.0) + offset,
	])


func _draw_node(center: Vector2, color: Color, pulse: float) -> void:
	draw_circle(center, 4.2 + pulse, Color(color.r, color.g, color.b, 0.16))
	draw_circle(center, 2.0, Color(0.88, 0.97, 1.0, 0.7))


func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if not points.is_empty():
		closed.append(points[0])
	return closed
