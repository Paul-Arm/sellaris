class_name BuildingHexSlot
extends Control

signal building_dropped(slot_id: String, building_id: String)

var slot_id: String = ""
var building_id: String = ""
var building_name: String = ""
var is_occupied: bool = false

var _label: Label = null
var _hovered: bool = false
var _accent_color: Color = Color(0.56, 0.84, 1.0, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	if _label == null:
		_label = Label.new()
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.add_theme_font_size_override("font_size", 10)
		add_child(_label)
	_update_label()


func configure(slot_data: Dictionary) -> void:
	slot_id = str(slot_data.get("id", "")).strip_edges()
	building_id = str(slot_data.get("building_id", "")).strip_edges()
	building_name = str(slot_data.get("building_name", ""))
	is_occupied = not building_id.is_empty()
	_accent_color = _get_building_accent_color(building_id)
	if _label != null:
		_update_label()
	queue_redraw()


func _draw() -> void:
	var points := _build_hex_points()
	var shadow_points := PackedVector2Array()
	for point in points:
		shadow_points.append(point + Vector2(0.0, 3.0))
	draw_colored_polygon(shadow_points, Color(0.0, 0.0, 0.0, 0.14))

	var fill_color := Color(0.02, 0.045, 0.06, 0.16)
	var stroke_color := Color(0.5, 0.72, 0.86, 0.24)
	if is_occupied:
		fill_color = Color(_accent_color.r * 0.22, _accent_color.g * 0.28, _accent_color.b * 0.32, 0.74)
		stroke_color = Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.84)
	if _hovered:
		fill_color = fill_color.lightened(0.18)
		stroke_color = stroke_color.lightened(0.16)

	draw_colored_polygon(points, fill_color)
	draw_polyline(_closed_points(points), stroke_color, 2.2 if is_occupied else 1.2, true)
	if is_occupied:
		draw_polyline(_closed_points(_scaled_points(points, 0.76)), Color(1.0, 1.0, 1.0, 0.1), 1.0, true)
		draw_circle(size * 0.5 + Vector2(0.0, -18.0), 3.5, Color(_accent_color.r, _accent_color.g, _accent_color.b, 0.68))


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data is not Dictionary:
		return false
	return str((data as Dictionary).get("kind", "")) == "colony_building" and not str((data as Dictionary).get("building_id", "")).strip_edges().is_empty()


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(_at_position, data):
		return
	building_dropped.emit(slot_id, str((data as Dictionary).get("building_id", "")))


func _update_label() -> void:
	if _label == null:
		return
	_label.text = _get_display_name() if is_occupied else "."
	_label.modulate = Color(0.95, 0.99, 1.0, 0.98) if is_occupied else Color(0.66, 0.86, 1.0, 0.24)


func _build_hex_points() -> PackedVector2Array:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.47
	var points := PackedVector2Array()
	for index in range(6):
		var angle := deg_to_rad(60.0 * float(index) - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _scaled_points(points: PackedVector2Array, scale: float) -> PackedVector2Array:
	var center := size * 0.5
	var scaled := PackedVector2Array()
	for point in points:
		scaled.append(center + (point - center) * scale)
	return scaled


func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if points.size() > 0:
		closed.append(points[0])
	return closed


func _set_hovered(value: bool) -> void:
	_hovered = value
	queue_redraw()


func _get_display_name() -> String:
	match building_id:
		"capital_hub":
			return "Capital\nHub"
		"basic_farm":
			return "Farm"
		"basic_reactor":
			return "Reactor"
		"basic_extractor":
			return "Extractor"
	return building_name.replace(" ", "\n")


func _get_building_accent_color(id: String) -> Color:
	match id:
		"capital_hub":
			return Color(0.62, 0.94, 1.0, 1.0)
		"basic_farm":
			return Color(0.54, 0.92, 0.65, 1.0)
		"basic_reactor":
			return Color(0.96, 0.72, 0.34, 1.0)
		"basic_extractor":
			return Color(0.78, 0.8, 0.88, 1.0)
	return Color(0.58, 0.84, 1.0, 1.0)
