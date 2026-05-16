extends Control
class_name SystemBodyGlyph

var _body_kind: String = "unknown"
var _body_record: Dictionary = {}
var _accent_color: Color = Color(0.62, 0.9, 1.0, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(body_kind: String, body_record: Dictionary, fallback_color: Color = Color(0.62, 0.9, 1.0, 1.0)) -> void:
	_body_kind = body_kind.strip_edges()
	_body_record = body_record.duplicate(true)
	var color_variant: Variant = _body_record.get("color", fallback_color)
	_accent_color = color_variant if color_variant is Color else fallback_color
	queue_redraw()


func _draw() -> void:
	if size.x <= 2.0 or size.y <= 2.0:
		return

	var rect := Rect2(Vector2.ZERO, size)
	var center := rect.get_center()
	var radius := minf(size.x, size.y) * 0.32
	draw_rect(rect, Color(0.025, 0.04, 0.052, 0.38), true)

	match _body_kind:
		"star":
			_draw_star(center, radius)
		"asteroid_belt":
			_draw_asteroid_belt(center, radius)
		"structure":
			_draw_structure(center, radius)
		"ruin":
			_draw_ruin(center, radius)
		"station":
			_draw_station(center, radius)
		"fleet", "ship", "unit", "creature":
			_draw_unit(center, radius)
		_:
			_draw_unknown(center, radius)


func _draw_star(center: Vector2, radius: float) -> void:
	for ring_index in range(3):
		var ring_radius := radius * (1.4 - float(ring_index) * 0.24)
		draw_circle(center, ring_radius, Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.08 + float(ring_index) * 0.04))
	draw_circle(center, radius * 0.82, Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.95))
	draw_circle(center - Vector2(radius * 0.18, radius * 0.22), radius * 0.28, Color(1.0, 0.98, 0.84, 0.7))


func _draw_asteroid_belt(center: Vector2, radius: float) -> void:
	draw_arc(center, radius * 1.25, -0.15 * PI, 1.15 * PI, 56, Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.34), 2.0, true)
	draw_arc(center, radius * 0.84, 0.85 * PI, 1.95 * PI, 44, Color(0.82, 0.78, 0.7, 0.25), 1.5, true)
	var seed_offset: int = absi(str(_body_record.get("id", _body_record.get("name", "belt"))).hash()) % 19
	for rock_index in range(18):
		var angle := TAU * float(rock_index) / 18.0 + float(seed_offset) * 0.017
		var rock_position := center + Vector2(cos(angle) * radius * 1.25, sin(angle) * radius * 0.52)
		var rock_radius := 2.0 + float((rock_index + seed_offset) % 4)
		draw_circle(rock_position, rock_radius, Color(0.72, 0.68, 0.62, 0.88))


func _draw_structure(center: Vector2, radius: float) -> void:
	var frame_color := Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.88)
	var muted_color := Color(0.86, 0.94, 1.0, 0.32)
	draw_line(center + Vector2(-radius, -radius * 0.42), center + Vector2(radius, radius * 0.42), muted_color, 3.0, true)
	draw_line(center + Vector2(-radius, radius * 0.42), center + Vector2(radius, -radius * 0.42), muted_color, 3.0, true)
	draw_rect(Rect2(center - Vector2(radius * 0.5, radius * 0.5), Vector2(radius, radius)), Color(0.04, 0.08, 0.1, 0.82), true)
	draw_rect(Rect2(center - Vector2(radius * 0.5, radius * 0.5), Vector2(radius, radius)), frame_color, false, 2.0)
	draw_circle(center, radius * 0.16, Color(1.0, 0.92, 0.76, 0.95))


func _draw_ruin(center: Vector2, radius: float) -> void:
	var shard_color := Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.78)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-radius * 0.85, radius * 0.46),
		center + Vector2(-radius * 0.28, -radius * 0.78),
		center + Vector2(0.05, radius * 0.22),
	]), shard_color)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(radius * 0.12, radius * 0.64),
		center + Vector2(radius * 0.34, -radius * 0.52),
		center + Vector2(radius * 0.92, radius * 0.22),
	]), Color(0.8, 0.86, 0.92, 0.54))
	draw_line(center + Vector2(-radius * 0.95, radius * 0.7), center + Vector2(radius * 0.92, radius * 0.7), Color(1.0, 0.78, 0.6, 0.34), 2.0, true)


func _draw_station(center: Vector2, radius: float) -> void:
	var line_color := Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.88)
	draw_arc(center, radius * 0.9, 0.0, TAU, 64, Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.28), 2.0, true)
	draw_line(center + Vector2(-radius, 0.0), center + Vector2(radius, 0.0), line_color, 3.0, true)
	draw_line(center + Vector2(0.0, -radius), center + Vector2(0.0, radius), line_color, 3.0, true)
	draw_circle(center, radius * 0.28, Color(0.07, 0.11, 0.13, 0.92))
	draw_circle(center, radius * 0.18, Color(0.86, 0.96, 1.0, 0.92))


func _draw_unit(center: Vector2, radius: float) -> void:
	var ship_color := Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.9)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -radius * 0.95),
		center + Vector2(radius * 0.58, radius * 0.7),
		center + Vector2(0.0, radius * 0.36),
		center + Vector2(-radius * 0.58, radius * 0.7),
	]), ship_color)
	draw_line(center + Vector2(0.0, -radius * 0.58), center + Vector2(0.0, radius * 0.38), Color(0.05, 0.08, 0.1, 0.52), 2.0, true)


func _draw_unknown(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.32))
	draw_arc(center, radius * 0.72, -0.2 * PI, 1.25 * PI, 40, Color(0.92, 0.96, 1.0, 0.72), 2.0, true)
