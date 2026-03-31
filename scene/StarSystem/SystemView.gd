extends Control
class_name SystemView

signal close_requested

const SPECIAL_TYPE_NONE: String = "none"

@onready var title_label: Label = get_node_or_null("HeaderMargin/HeaderRow/HeaderText/Title")
@onready var subtitle_label: Label = get_node_or_null("HeaderMargin/HeaderRow/HeaderText/Subtitle")
@onready var owner_label: Label = get_node_or_null("RightPanel/RightMargin/RightVBox/OwnerLabel")
@onready var summary_label: Label = get_node_or_null("RightPanel/RightMargin/RightVBox/SummaryLabel")
@onready var detail_label: Label = get_node_or_null("RightPanel/RightMargin/RightVBox/DetailLabel")
@onready var close_button: Button = get_node_or_null("HeaderMargin/HeaderRow/CloseButton")
@onready var preview: StarSystemPreview = get_node_or_null("PreviewViewportContainer/PreviewViewport/StarSystemPreview")

var _current_system_id: String = ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if close_button != null:
		close_button.pressed.connect(_on_close_pressed)


func show_system(system_details: Dictionary, neighbor_count: int) -> void:
	_current_system_id = str(system_details.get("id", ""))
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	if system_details.is_empty():
		_set_label_text(title_label, "Unknown System")
		_set_label_text(subtitle_label, "")
		_set_label_text(owner_label, "Owner: Unknown")
		_set_label_text(summary_label, "")
		_set_label_text(detail_label, "")
		if preview != null:
			preview.clear_preview()
		return

	var summary: Dictionary = system_details.get("system_summary", {})
	var star_profile: Dictionary = system_details.get("star_profile", {})
	var owner_name: String = str(system_details.get("owner_name", "Unclaimed"))
	var star_class: String = str(summary.get("star_class", star_profile.get("star_class", "G")))
	var star_count: int = int(summary.get("star_count", star_profile.get("star_count", 1)))
	var special_type: String = str(summary.get("special_type", star_profile.get("special_type", SPECIAL_TYPE_NONE)))
	var special_text: String = ""
	if special_type != SPECIAL_TYPE_NONE:
		special_text = "  Special: %s" % special_type

	_set_label_text(title_label, str(system_details.get("name", _current_system_id)))
	_set_label_text(subtitle_label, "System View")
	_set_label_text(owner_label, "Owner: %s" % owner_name)
	_set_label_text(summary_label, "Star Class: %s  Stars: %d%s\nHyperlane Connections: %d" % [
		star_class,
		star_count,
		special_text,
		neighbor_count,
	])
	_set_label_text(detail_label, "Planets: %d\nAsteroid Belts: %d\nStructures: %d\nRuins: %d\nHabitable Worlds: %d\nColonizable Worlds: %d\nAnomaly Risk: %d%%\n\nShared top bar, debug tools, and drawers stay active in this view." % [
		int(summary.get("planet_count", 0)),
		int(summary.get("asteroid_belt_count", 0)),
		int(summary.get("structure_count", 0)),
		int(summary.get("ruin_count", 0)),
		int(summary.get("habitable_worlds", 0)),
		int(summary.get("colonizable_worlds", 0)),
		int(round(float(summary.get("anomaly_risk", 0.0)) * 100.0)),
	])
	if preview != null:
		preview.set_system_details(system_details)


func hide_view() -> void:
	_current_system_id = ""
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if preview != null:
		preview.clear_preview()


func handle_view_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		handle_cancel_action()
		return
	if preview != null:
		preview.forward_input(event)


func is_open() -> bool:
	return visible


func get_current_system_id() -> String:
	return _current_system_id


func handle_cancel_action() -> bool:
	if not visible:
		return false
	get_viewport().set_input_as_handled()
	return true


func _on_close_pressed() -> void:
	close_requested.emit()


func _set_label_text(label: Label, value: String) -> void:
	if label != null:
		label.text = value
