extends Control
class_name SystemView

signal close_requested

const SPECIAL_TYPE_NONE: String = "none"
const POPUP_OFFSET: Vector2 = Vector2(18.0, -18.0)
const POPUP_MARGIN: float = 20.0

@onready var title_label: Label = get_node_or_null("HeaderMargin/HeaderRow/HeaderText/Title")
@onready var subtitle_label: Label = get_node_or_null("HeaderMargin/HeaderRow/HeaderText/Subtitle")
@onready var owner_label: Label = get_node_or_null("RightPanel/RightMargin/RightVBox/OwnerLabel")
@onready var summary_label: Label = get_node_or_null("RightPanel/RightMargin/RightVBox/SummaryLabel")
@onready var detail_label: Label = get_node_or_null("RightPanel/RightMargin/RightVBox/DetailLabel")
@onready var close_button: Button = get_node_or_null("HeaderMargin/HeaderRow/CloseButton")
@onready var preview_container: Control = get_node_or_null("PreviewViewportContainer")
@onready var preview_viewport: SubViewport = get_node_or_null("PreviewViewportContainer/PreviewViewport")
@onready var preview: StarSystemPreview = get_node_or_null("PreviewViewportContainer/PreviewViewport/StarSystemPreview")
@onready var selection_popup: PanelContainer = get_node_or_null("SelectionPopup")
@onready var selection_popup_title: Label = get_node_or_null("SelectionPopup/PopupMargin/PopupVBox/PopupTitle")
@onready var selection_popup_subtitle: Label = get_node_or_null("SelectionPopup/PopupMargin/PopupVBox/PopupSubtitle")
@onready var selection_popup_body: Label = get_node_or_null("SelectionPopup/PopupMargin/PopupVBox/PopupBody")

var _current_system_id: String = ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if close_button != null:
		close_button.pressed.connect(_on_close_pressed)
	if preview != null and not preview.selection_changed.is_connected(_on_preview_selection_changed):
		preview.selection_changed.connect(_on_preview_selection_changed)
	_hide_selection_popup()


func _process(_delta: float) -> void:
	if not visible or selection_popup == null or preview == null:
		return
	if not preview.has_selection():
		_hide_selection_popup()
		return
	_update_selection_popup(preview.get_selection_popup_state())


func show_system(system_details: Dictionary, neighbor_count: int) -> void:
	_current_system_id = str(system_details.get("id", ""))
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hide_selection_popup()

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
	_set_label_text(detail_label, "Planets: %d\nAsteroid Belts: %d\nStructures: %d\nRuins: %d\nHabitable Worlds: %d\nColonizable Worlds: %d\nAnomaly Risk: %d%%\n\nLeft-click bodies to inspect them while right-drag, middle-drag, and mouse wheel keep controlling the camera." % [
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
	_hide_selection_popup()
	if preview != null:
		preview.clear_preview()


func handle_view_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		handle_cancel_action()
		return
	if event is InputEventMouse and _is_pointer_blocked_by_ui():
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


func _on_preview_selection_changed(selection_data: Dictionary) -> void:
	_update_selection_popup(selection_data)


func _update_selection_popup(selection_data: Dictionary) -> void:
	if selection_popup == null:
		return
	if selection_data.is_empty():
		_hide_selection_popup()
		return

	_set_label_text(selection_popup_title, str(selection_data.get("title", "Selection")))
	_set_label_text(selection_popup_subtitle, str(selection_data.get("subtitle", "")))
	_set_label_text(selection_popup_body, str(selection_data.get("body_text", "")))
	selection_popup.visible = true
	selection_popup.size = selection_popup.get_combined_minimum_size()
	_position_selection_popup(selection_data.get("screen_position", Vector2.ZERO))


func _position_selection_popup(preview_screen_position: Vector2) -> void:
	if selection_popup == null or preview_container == null or preview_viewport == null:
		return
	if preview_viewport.size.x <= 0 or preview_viewport.size.y <= 0:
		return

	var viewport_scale := Vector2(
		preview_container.size.x / float(preview_viewport.size.x),
		preview_container.size.y / float(preview_viewport.size.y)
	)
	var popup_anchor: Vector2 = preview_container.position + Vector2(
		preview_screen_position.x * viewport_scale.x,
		preview_screen_position.y * viewport_scale.y
	)
	var popup_size: Vector2 = selection_popup.get_combined_minimum_size()
	selection_popup.size = popup_size

	var popup_position: Vector2 = popup_anchor + POPUP_OFFSET
	var min_position: Vector2 = Vector2(POPUP_MARGIN, POPUP_MARGIN)
	var max_position: Vector2 = Vector2(
		maxf(min_position.x, size.x - popup_size.x - POPUP_MARGIN),
		maxf(min_position.y, size.y - popup_size.y - POPUP_MARGIN)
	)
	popup_position.x = clampf(popup_position.x, min_position.x, max_position.x)
	popup_position.y = clampf(popup_position.y, min_position.y, max_position.y)
	selection_popup.position = popup_position


func _hide_selection_popup() -> void:
	if selection_popup != null:
		selection_popup.visible = false


func _is_pointer_blocked_by_ui() -> bool:
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	if hovered_control == null:
		return false
	return not _is_control_within(hovered_control, preview_container)


func _is_control_within(control: Control, ancestor: Node) -> bool:
	if control == null or ancestor == null:
		return false
	var current: Node = control
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _set_label_text(label: Label, value: String) -> void:
	if label != null:
		label.text = value
