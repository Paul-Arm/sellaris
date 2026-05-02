class_name BuildingPaletteCard
extends PanelContainer

var building_data: Dictionary = {}


func configure(data: Dictionary) -> void:
	building_data = data.duplicate(true)
	var can_place := bool(building_data.get("can_place", false))
	add_theme_stylebox_override("panel", _make_card_style(can_place))
	modulate = Color(1.0, 1.0, 1.0, 1.0) if can_place else Color(0.64, 0.68, 0.72, 0.76)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_place else Control.CURSOR_FORBIDDEN
	tooltip_text = str(building_data.get("unavailable_reason", "")) if not bool(building_data.get("can_place", false)) else str(building_data.get("description", ""))


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not bool(building_data.get("can_place", false)):
		return null
	var building_id := str(building_data.get("id", "")).strip_edges()
	if building_id.is_empty():
		return null

	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(170, 48)
	preview.add_theme_stylebox_override("panel", _make_drag_preview_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	preview.add_child(margin)
	var label := Label.new()
	label.text = str(building_data.get("display_name", building_id))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	margin.add_child(label)
	set_drag_preview(preview)

	return {
		"kind": "colony_building",
		"building_id": building_id,
		"display_name": str(building_data.get("display_name", building_id)),
	}


func _make_card_style(can_place: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.066, 0.078, 0.94) if can_place else Color(0.038, 0.043, 0.05, 0.9)
	style.border_color = Color(0.5, 0.82, 0.96, 0.48) if can_place else Color(0.28, 0.36, 0.42, 0.42)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 3.0)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _make_drag_preview_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.12, 0.15, 0.96)
	style.border_color = Color(0.72, 0.94, 1.0, 0.78)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 3.0)
	return style
