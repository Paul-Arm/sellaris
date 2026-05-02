class_name BuildingHexSlot
extends Control

signal building_dropped(slot_id: String, building_id: String)

var slot_id: String = ""
var building_id: String = ""
var building_name: String = ""
var is_occupied: bool = false

var _label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	if _label == null:
		_label = Label.new()
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.add_theme_font_size_override("font_size", 11)
		add_child(_label)
	_update_label()


func configure(slot_data: Dictionary) -> void:
	slot_id = str(slot_data.get("id", "")).strip_edges()
	building_id = str(slot_data.get("building_id", "")).strip_edges()
	building_name = str(slot_data.get("building_name", ""))
	is_occupied = not building_id.is_empty()
	if _label != null:
		_update_label()
	queue_redraw()


func _draw() -> void:
	var points := _build_hex_points()
	var fill_color := Color(0.16, 0.24, 0.31, 0.46)
	var stroke_color := Color(0.65, 0.86, 1.0, 0.42)
	if is_occupied:
		fill_color = Color(0.18, 0.42, 0.53, 0.82)
		stroke_color = Color(0.82, 0.96, 1.0, 0.86)
	draw_colored_polygon(points, fill_color)
	draw_polyline(_closed_points(points), stroke_color, 2.0, true)


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
	_label.text = building_name if is_occupied else "+"
	_label.modulate = Color(0.92, 0.98, 1.0, 0.98) if is_occupied else Color(0.78, 0.9, 1.0, 0.55)


func _build_hex_points() -> PackedVector2Array:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.48
	var points := PackedVector2Array()
	for index in range(6):
		var angle := deg_to_rad(60.0 * float(index) - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if points.size() > 0:
		closed.append(points[0])
	return closed
