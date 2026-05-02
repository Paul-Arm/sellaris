class_name BuildingPaletteCard
extends PanelContainer

var building_data: Dictionary = {}


func configure(data: Dictionary) -> void:
	building_data = data.duplicate(true)
	modulate = Color(1.0, 1.0, 1.0, 1.0) if bool(building_data.get("can_place", false)) else Color(0.62, 0.66, 0.7, 0.72)
	tooltip_text = str(building_data.get("unavailable_reason", "")) if not bool(building_data.get("can_place", false)) else str(building_data.get("description", ""))


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not bool(building_data.get("can_place", false)):
		return null
	var building_id := str(building_data.get("id", "")).strip_edges()
	if building_id.is_empty():
		return null

	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(170, 48)
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
