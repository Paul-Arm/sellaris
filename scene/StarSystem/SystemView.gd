extends Control
class_name SystemView

signal close_requested
signal build_order_requested(builder_unit_id: String, system_id: String, body_context: Dictionary, build_class_id: String)
signal colony_open_requested(colony_id: String)
signal body_colonize_requested(system_id: String, body_context: Dictionary)
signal anomaly_research_requested(system_id: String, anomaly_id: String)
signal runtime_entity_selected(selection_data: Dictionary)

const SPECIAL_TYPE_NONE: String = "none"
const POPUP_OFFSET: Vector2 = Vector2(18.0, -18.0)
const POPUP_MARGIN: float = 20.0
const BODY_DETAILS_PANEL_SCRIPT: Script = preload("res://scene/StarSystem/SystemBodyDetailsPanel.gd")

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
var _current_system_details: Dictionary = {}
var _body_details_panel = null
var _build_menu: PopupMenu = null
var _build_menu_builder_unit_id: String = ""
var _build_menu_body_context: Dictionary = {}
var _build_menu_options: Array[Dictionary] = []
var _suppress_runtime_entity_selection_signal: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if close_button != null:
		close_button.pressed.connect(_on_close_pressed)
	if preview != null and not preview.selection_changed.is_connected(_on_preview_selection_changed):
		preview.selection_changed.connect(_on_preview_selection_changed)
	if preview != null and not preview.movement_order_requested.is_connected(_on_preview_movement_order_requested):
		preview.movement_order_requested.connect(_on_preview_movement_order_requested)
	if preview != null and not preview.build_menu_requested.is_connected(_on_preview_build_menu_requested):
		preview.build_menu_requested.connect(_on_preview_build_menu_requested)
	_ensure_body_details_panel()
	_ensure_build_menu()
	_hide_selection_popup()


func _process(_delta: float) -> void:
	pass


func show_system(system_details: Dictionary, neighbor_count: int) -> void:
	_current_system_id = str(system_details.get("id", ""))
	_current_system_details = system_details.duplicate(true)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hide_selection_popup()
	_hide_body_details_panel()
	_hide_build_menu()

	if system_details.is_empty():
		_current_system_details.clear()
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
	_set_label_text(detail_label, "Planets: %d\nAsteroid Belts: %d\nStructures: %d\nRuins: %d\nHabitable Worlds: %d\nColonizable Worlds: %d\nAnomaly Risk: %d%%\nKnown Anomalies: %d\n\nLeft-click bodies to inspect them while right-drag, middle-drag, and mouse wheel keep controlling the camera." % [
		int(summary.get("planet_count", 0)),
		int(summary.get("asteroid_belt_count", 0)),
		int(summary.get("structure_count", 0)),
		int(summary.get("ruin_count", 0)),
		int(summary.get("habitable_worlds", 0)),
		int(summary.get("colonizable_worlds", 0)),
		int(round(float(summary.get("anomaly_risk", 0.0)) * 100.0)),
		int(system_details.get("known_anomaly_count", 0)),
	])
	_set_label_text(detail_label, "Planets: %d\nAsteroid Belts: %d\nStructures: %d\nRuins: %d\nHabitable Worlds: %d\nColonizable Worlds: %d\nAnomaly Risk: %d%%\nKnown Anomalies: %d\n\nLeft-click bodies to inspect them while right-drag, middle-drag, and mouse wheel keep controlling the camera." % [
		int(summary.get("planet_count", 0)),
		int(summary.get("asteroid_belt_count", 0)),
		int(summary.get("structure_count", 0)),
		int(summary.get("ruin_count", 0)),
		int(summary.get("habitable_worlds", 0)),
		int(summary.get("colonizable_worlds", 0)),
		int(round(float(summary.get("anomaly_risk", 0.0)) * 100.0)),
		int(system_details.get("known_anomaly_count", 0)),
	])
	if preview != null:
		_suppress_runtime_entity_selection_signal = true
		preview.set_system_details(system_details)
		_suppress_runtime_entity_selection_signal = false


func refresh_runtime(system_details: Dictionary, neighbor_count: int) -> void:
	if not visible or str(system_details.get("id", "")) != _current_system_id:
		show_system(system_details, neighbor_count)
		return
	_current_system_details = system_details.duplicate(true)
	_update_system_labels(system_details, neighbor_count)
	if preview != null:
		_suppress_runtime_entity_selection_signal = true
		if _body_details_panel != null and _body_details_panel.is_showing():
			preview.set_system_details(system_details)
		else:
			preview.refresh_runtime_placeholders(system_details)
		_suppress_runtime_entity_selection_signal = false


func play_combat_events(events: Array) -> void:
	if not visible or preview == null:
		return
	preview.play_combat_events(events)


func hide_view() -> void:
	_current_system_id = ""
	_current_system_details.clear()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_selection_popup()
	_hide_body_details_panel()
	_hide_build_menu()
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
	if _build_menu != null and _build_menu.visible:
		_build_menu.hide()
		get_viewport().set_input_as_handled()
		return true
	if preview != null:
		preview.clear_selection()
	_hide_selection_popup()
	_hide_body_details_panel()
	get_viewport().set_input_as_handled()
	return true


func _on_close_pressed() -> void:
	close_requested.emit()


func _on_preview_selection_changed(selection_data: Dictionary) -> void:
	_handle_preview_selection_changed(selection_data)


func _on_preview_movement_order_requested(selection_data: Dictionary, target_local_position: Vector3) -> void:
	var record_id: String = str(selection_data.get("record_id", ""))
	if record_id.is_empty():
		return

	match str(selection_data.get("selection_kind", "")):
		"fleet":
			SpaceManager.issue_fleet_move(record_id, target_local_position)
		SpaceUnitClass.UNIT_KIND_SHIP, SpaceUnitClass.UNIT_KIND_CREATURE, "unit":
			var unit: SpaceUnitRuntime = SpaceManager.get_unit(record_id)
			if unit == null:
				return
			if not unit.fleet_id.is_empty():
				SpaceManager.issue_fleet_move(unit.fleet_id, target_local_position)
				return
			SpaceManager.issue_unit_move(record_id, target_local_position)


func set_selected_builder_unit_id(unit_id: String) -> void:
	if preview != null:
		preview.set_external_selected_builder_unit_id(unit_id)


func select_runtime_entity(selection_kind: String, record_id: String, notify_selection: bool = true) -> bool:
	if preview == null:
		return false
	_suppress_runtime_entity_selection_signal = not notify_selection
	var selected := preview.select_runtime_entity(selection_kind, record_id)
	_suppress_runtime_entity_selection_signal = false
	if not selected:
		_hide_body_details_panel()
	return selected


func _on_preview_build_menu_requested(
	builder_unit_id: String,
	body_context: Dictionary,
	options: Array[Dictionary],
	preview_screen_position: Vector2
) -> void:
	_ensure_build_menu()
	if _build_menu == null:
		return
	_build_menu_builder_unit_id = builder_unit_id
	_build_menu_body_context = body_context.duplicate(true)
	_build_menu_options = options.duplicate(true)
	_build_menu.clear()
	_set_preview_camera_blocked(true)

	for option_index in range(_build_menu_options.size()):
		var option := _build_menu_options[option_index]
		var label := "%s  (%d days)" % [
			str(option.get("display_name", option.get("class_id", ""))),
			int(option.get("build_time_days", 0)),
		]
		_build_menu.add_item(label, option_index)
		_build_menu.set_item_metadata(option_index, str(option.get("class_id", "")))

	var popup_position := get_global_position() + _preview_to_view_position(preview_screen_position)
	_build_menu.position = Vector2i(roundi(popup_position.x), roundi(popup_position.y))
	_build_menu.popup()


func _on_build_menu_id_pressed(id: int) -> void:
	if id < 0 or id >= _build_menu_options.size():
		return
	var option := _build_menu_options[id]
	var build_class_id := str(option.get("class_id", ""))
	if build_class_id.is_empty():
		return
	build_order_requested.emit(
		_build_menu_builder_unit_id,
		_current_system_id,
		_build_menu_body_context.duplicate(true),
		build_class_id
	)
	_build_menu.hide()


func _handle_preview_selection_changed(selection_data: Dictionary) -> void:
	_hide_selection_popup()
	if selection_data.is_empty():
		_hide_body_details_panel()
		if not _suppress_runtime_entity_selection_signal:
			runtime_entity_selected.emit({})
		return

	if _is_runtime_space_entity_selection(selection_data):
		_hide_body_details_panel()
		if not _suppress_runtime_entity_selection_signal:
			runtime_entity_selected.emit(_build_runtime_entity_selection_data(selection_data))
		return

	if not _suppress_runtime_entity_selection_signal:
		runtime_entity_selected.emit({})
	var existing_colony_id := _get_existing_colony_id_for_selection(selection_data)
	if not existing_colony_id.is_empty():
		_hide_body_details_panel()
		if preview != null:
			preview.clear_selection()
		colony_open_requested.emit(existing_colony_id)
		return

	_ensure_body_details_panel()
	if _body_details_panel == null:
		return
	_body_details_panel.open_details(selection_data, _current_system_details, _build_body_action_state(selection_data))


func _is_runtime_space_entity_selection(selection_data: Dictionary) -> bool:
	match str(selection_data.get("selection_kind", "")):
		"fleet", SpaceUnitClass.UNIT_KIND_SHIP, SpaceUnitClass.UNIT_KIND_CREATURE, "unit":
			return true
		_:
			return false


func _build_runtime_entity_selection_data(selection_data: Dictionary) -> Dictionary:
	var result := selection_data.duplicate(true)
	var context: Dictionary = result.get("context", {}) if result.get("context", {}) is Dictionary else {}
	var record_id := str(context.get("body_id", context.get("host_id", ""))).strip_edges()
	if record_id.is_empty():
		record_id = _record_id_from_selection_id(str(result.get("selection_id", "")))
	result["record_id"] = record_id
	result["system_id"] = str(context.get("system_id", _current_system_id))
	return result


func _ensure_body_details_panel() -> void:
	if is_instance_valid(_body_details_panel):
		return
	_body_details_panel = BODY_DETAILS_PANEL_SCRIPT.new()
	_body_details_panel.name = "SystemBodyDetailsPanel"
	add_child(_body_details_panel)
	if not _body_details_panel.close_requested.is_connected(_on_body_details_panel_close_requested):
		_body_details_panel.close_requested.connect(_on_body_details_panel_close_requested)
	if not _body_details_panel.colonize_requested.is_connected(_on_body_details_panel_colonize_requested):
		_body_details_panel.colonize_requested.connect(_on_body_details_panel_colonize_requested)
	if not _body_details_panel.anomaly_research_requested.is_connected(_on_body_details_panel_anomaly_research_requested):
		_body_details_panel.anomaly_research_requested.connect(_on_body_details_panel_anomaly_research_requested)


func _hide_body_details_panel() -> void:
	if _body_details_panel != null:
		_body_details_panel.hide_details()


func _on_body_details_panel_close_requested() -> void:
	if preview != null:
		preview.clear_selection()
	else:
		_hide_body_details_panel()


func _on_body_details_panel_colonize_requested(system_id: String, body_context: Dictionary) -> void:
	if preview != null:
		preview.clear_selection()
	_hide_body_details_panel()
	body_colonize_requested.emit(system_id, body_context.duplicate(true))


func _on_body_details_panel_anomaly_research_requested(system_id: String, anomaly_id: String) -> void:
	anomaly_research_requested.emit(system_id, anomaly_id)


func _build_body_action_state(selection_data: Dictionary) -> Dictionary:
	var body_record := _resolve_selection_body_record(selection_data)
	var context: Dictionary = selection_data.get("context", {}) if selection_data.get("context", {}) is Dictionary else {}
	var body_kind := str(context.get("body_type", selection_data.get("selection_kind", body_record.get("type", "")))).strip_edges()
	var existing_colony_id := _get_existing_colony_id_for_selection(selection_data)
	var is_habitable_planet := body_kind == "planet" and _is_colonizable_body_record(body_record)
	var show_colonize := is_habitable_planet and existing_colony_id.is_empty()
	var can_colonize := show_colonize
	var reason := ""

	if show_colonize:
		var active_empire_id := str(_current_system_details.get("active_empire_id", "")).strip_edges()
		var owner_empire_id := str(_current_system_details.get("owner_empire_id", "")).strip_edges()
		if active_empire_id.is_empty():
			can_colonize = false
			reason = "Kein aktives Reich ausgewaehlt."
		elif owner_empire_id != active_empire_id:
			can_colonize = false
			reason = "System gehoert nicht deinem Reich."
		elif not bool(_current_system_details.get("has_full_intel", false)):
			can_colonize = false
			reason = "Volle Sensordaten erforderlich."

	return {
		"show_colonize": show_colonize,
		"can_colonize": can_colonize,
		"colonize_reason": reason,
		"existing_colony_id": existing_colony_id,
	}


func _get_existing_colony_id_for_selection(selection_data: Dictionary) -> String:
	var host_context := _resolve_selection_host_context(selection_data)
	var host_kind := str(host_context.get("host_kind", "")).strip_edges()
	var host_id := str(host_context.get("host_id", "")).strip_edges()
	var system_id := str(host_context.get("system_id", "")).strip_edges()
	if host_kind.is_empty() or host_id.is_empty():
		return ""
	return ColonyManager.get_colony_id_for_host(host_kind, host_id, system_id)


func _resolve_selection_host_context(selection_data: Dictionary) -> Dictionary:
	var context: Dictionary = selection_data.get("context", {}) if selection_data.get("context", {}) is Dictionary else {}
	var host_kind := str(context.get("host_kind", "")).strip_edges()
	var host_id := str(context.get("host_id", "")).strip_edges()
	var body_kind := str(context.get("body_type", selection_data.get("selection_kind", ""))).strip_edges()
	var body_id := str(context.get("body_id", "")).strip_edges()
	if host_id.is_empty():
		host_id = body_id

	if host_kind.is_empty():
		match body_kind:
			"planet", "asteroid_belt", "structure", "ruin", "star":
				host_kind = ColonyRuntime.HOST_KIND_ORBITAL
			"station":
				host_kind = ColonyRuntime.HOST_KIND_SPACE_UNIT
			_:
				host_kind = ""

	if host_id.is_empty() and body_kind == "station":
		host_id = _record_id_from_selection_id(str(selection_data.get("selection_id", "")))

	return {
		"system_id": str(context.get("system_id", _current_system_id)).strip_edges(),
		"host_kind": host_kind,
		"host_id": host_id,
	}


func _record_id_from_selection_id(selection_id: String) -> String:
	var parts := selection_id.split(":", false, 1)
	if parts.size() < 2:
		return ""
	return str(parts[1]).strip_edges()


func _resolve_selection_body_record(selection_data: Dictionary) -> Dictionary:
	var context: Dictionary = selection_data.get("context", {}) if selection_data.get("context", {}) is Dictionary else {}
	var context_record: Variant = context.get("body_record", {})
	if context_record is Dictionary and not (context_record as Dictionary).is_empty():
		return (context_record as Dictionary).duplicate(true)

	var body_id := str(context.get("body_id", context.get("host_id", ""))).strip_edges()
	var body_kind := str(context.get("body_type", selection_data.get("selection_kind", ""))).strip_edges()
	for star_variant in _current_system_details.get("stars", []):
		if star_variant is not Dictionary:
			continue
		var star: Dictionary = star_variant
		if body_kind == "star" and (body_id.is_empty() or str(star.get("id", star.get("name", ""))) == body_id):
			return star.duplicate(true)
	for orbital_variant in _current_system_details.get("orbitals", []):
		if orbital_variant is not Dictionary:
			continue
		var orbital: Dictionary = orbital_variant
		if str(orbital.get("id", orbital.get("name", ""))) == body_id:
			return orbital.duplicate(true)
	return {}


func _is_colonizable_body_record(body_record: Dictionary) -> bool:
	if str(body_record.get("type", "")) != "planet":
		return false
	if bool(body_record.get("is_colonizable", false)):
		return true
	var habitability_points := 0
	if body_record.has("habitability_points"):
		habitability_points = int(body_record.get("habitability_points", 0))
	elif body_record.has("habitability"):
		habitability_points = int(round(clampf(float(body_record.get("habitability", 0.0)), 0.0, 1.0) * 100.0))
	return habitability_points >= 45


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


func _preview_to_view_position(preview_screen_position: Vector2) -> Vector2:
	if preview_container == null or preview_viewport == null:
		return preview_screen_position
	if preview_viewport.size.x <= 0 or preview_viewport.size.y <= 0:
		return preview_screen_position
	var viewport_scale := Vector2(
		preview_container.size.x / float(preview_viewport.size.x),
		preview_container.size.y / float(preview_viewport.size.y)
	)
	return preview_container.position + Vector2(
		preview_screen_position.x * viewport_scale.x,
		preview_screen_position.y * viewport_scale.y
	)


func _ensure_build_menu() -> void:
	if is_instance_valid(_build_menu):
		return
	_build_menu = PopupMenu.new()
	_build_menu.name = "BuildMenu"
	_build_menu.hide()
	add_child(_build_menu)
	_build_menu.id_pressed.connect(_on_build_menu_id_pressed)
	_build_menu.popup_hide.connect(_on_build_menu_hidden)


func _hide_selection_popup() -> void:
	if selection_popup != null:
		selection_popup.visible = false


func _hide_build_menu() -> void:
	if _build_menu != null:
		_build_menu.hide()
	_set_preview_camera_blocked(false)


func _on_build_menu_hidden() -> void:
	_set_preview_camera_blocked(false)


func _set_preview_camera_blocked(blocked: bool) -> void:
	if preview != null and preview.has_method("set_camera_input_blocked"):
		preview.call("set_camera_input_blocked", blocked)


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


func _update_system_labels(system_details: Dictionary, neighbor_count: int) -> void:
	if system_details.is_empty():
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
