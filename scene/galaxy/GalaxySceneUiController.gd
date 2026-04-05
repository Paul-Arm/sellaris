extends RefCounted

const HOVER_PREVIEW_DELAY_SEC: float = 1.0

var _host: Node
var _hover_preview_pending_system_id: String = ""
var _hover_preview_ready_system_id: String = ""
var _hover_preview_sequence: int = 0
var _active_preview_system_id: String = ""


func bind(host: Node) -> void:
	_host = host


func unbind() -> void:
	_reset_hover_preview_state()
	_host = null


func update_info_label() -> void:
	var displayed_seed: String = _host.seed_text if not _host.seed_text.is_empty() else str(_host.generated_seed)
	var active_empire_name: String = "None"
	if _host.empires_by_id.has(_host.active_empire_id):
		active_empire_name = str(_host.empires_by_id[_host.active_empire_id].get("name", active_empire_name))

	var inspected_system_id: String = get_inspected_system_id()
	var selected_summary: String = "Selected: None"
	if not inspected_system_id.is_empty() and _host.systems_by_id.has(inspected_system_id):
		var selected_owner: Dictionary = _host.galaxy_state.get_system_owner(inspected_system_id)
		var selected_owner_name := "Unclaimed"
		if not selected_owner.is_empty():
			selected_owner_name = str(selected_owner.get("name", selected_owner_name))
		selected_summary = "Selected: %s (%s)" % [_host.systems_by_id[inspected_system_id].get("name", inspected_system_id), selected_owner_name]

	_host.info_label.text = "Seed: %s\nSystems: %d  Shape: %s  Hyperlanes: %d  Empires: %d\nActive Empire: %s  %s\nPan: WASD / Arrows / Edge / Middle Drag  Orbit: Right Drag  Zoom: Mouse Wheel  Pick Empire: E  Regenerate: R  System View: Left Click  Back: Esc closes overlays and returns to galaxy" % [
		displayed_seed,
		_host.system_positions.size(),
		_host.galaxy_shape.capitalize(),
		_host.hyperlane_density,
		_host.empire_records.size(),
		active_empire_name,
		selected_summary,
	]


func update_system_panel() -> void:
	var inspected_system_id: String = get_inspected_system_id()
	_host.selected_system_id = inspected_system_id
	var active_empire_name: String = "None selected"
	_host.change_empire_button.text = "Choose Empire"
	_host.claim_system_button.text = "Claim Selected System"
	_host.claim_system_button.modulate = Color.WHITE

	if _host.empires_by_id.has(_host.active_empire_id):
		var active_empire: Dictionary = _host.empires_by_id[_host.active_empire_id]
		active_empire_name = str(active_empire.get("name", active_empire_name))
		_host.change_empire_button.text = "Change Empire"
		_host.claim_system_button.text = "Claim for %s" % active_empire_name
		_host.claim_system_button.modulate = active_empire.get("color", Color.WHITE)

	_host.empire_status_label.text = "Active Empire: %s" % active_empire_name

	var selected_system_name: String = "No system selected"
	var selected_owner_name: String = "Unclaimed"
	if not inspected_system_id.is_empty() and _host.systems_by_id.has(inspected_system_id):
		selected_system_name = str(_host.systems_by_id[inspected_system_id].get("name", inspected_system_id))
		var selected_owner_empire_id: String = _host.galaxy_state.get_system_owner_id(inspected_system_id)
		if _host.empires_by_id.has(selected_owner_empire_id):
			selected_owner_name = str(_host.empires_by_id[selected_owner_empire_id].get("name", selected_owner_name))

	update_bottom_category_bar_context(active_empire_name, selected_system_name, selected_owner_name)

	if inspected_system_id.is_empty() or not _host.systems_by_id.has(inspected_system_id):
		_clear_system_panel_preview()
		_host.system_panel.visible = false
		_host.selected_system_title.text = "No system selected"
		_host.selected_system_meta.text = "Left-click a star system to inspect it. The galaxy map keeps compact summary data for every system, while richer stars, planets, belts, ruins, and structures are resolved on demand for the selected system."
		_host.system_preview_image.texture = null
		_host.claim_system_button.disabled = _host.active_empire_id.is_empty()
		_host.clear_owner_button.disabled = true
		return

	_host.system_panel.visible = true

	var system_record: Dictionary = _host.systems_by_id[inspected_system_id]
	var owner_empire_id: String = _host.galaxy_state.get_system_owner_id(inspected_system_id)
	var owner_name: String = "Unclaimed"
	if _host.empires_by_id.has(owner_empire_id):
		owner_name = str(_host.empires_by_id[owner_empire_id].get("name", owner_name))

	var system_details: Dictionary = _host.get_system_details(inspected_system_id)
	var summary: Dictionary = system_details.get("system_summary", system_record.get("system_summary", {}))
	var star_profile: Dictionary = system_details.get("star_profile", system_record.get("star_profile", {}))
	var space_presence: Dictionary = system_details.get("space_presence", {})
	var neighbor_count: int = _host.galaxy_state.get_neighbor_system_ids(inspected_system_id).size()
	var star_count_label: int = int(summary.get("star_count", star_profile.get("star_count", 1)))
	var star_class: String = str(star_profile.get("star_class", "G"))
	var special_type: String = str(star_profile.get("special_type", "none"))
	var special_label: String = ""
	if special_type != "none":
		special_label = "  Special: %s" % special_type

	_host.selected_system_title.text = str(system_record.get("name", inspected_system_id))
	_host.selected_system_meta.text = "Owner: %s\nStar Class: %s  Stars: %d%s\nHyperlane Connections: %d\nPlanets: %d  Belts: %d  Structures: %d  Ruins: %d\nLocal Presence: Fleets %d  Mobile %d  Stations %d\nHabitable: %d  Colonizable: %d  Anomaly Risk: %d%%" % [
		owner_name,
		star_class,
		star_count_label,
		special_label,
		neighbor_count,
		int(summary.get("planet_count", 0)),
		int(summary.get("asteroid_belt_count", 0)),
		int(summary.get("structure_count", 0)),
		int(summary.get("ruin_count", 0)),
		int(space_presence.get("fleet_count", 0)),
		int(space_presence.get("mobile_ship_count", 0)),
		int(space_presence.get("station_count", 0)),
		int(summary.get("habitable_worlds", 0)),
		int(summary.get("colonizable_worlds", 0)),
		int(round(float(summary.get("anomaly_risk", 0.0)) * 100.0)),
	]
	_refresh_hover_preview_tracking(inspected_system_id)
	var preview_system_id: String = _resolve_preview_target_system_id(inspected_system_id)
	if preview_system_id.is_empty():
		_clear_system_panel_preview()
	else:
		_active_preview_system_id = preview_system_id
		update_system_panel_preview(preview_system_id, system_details)
	if _host.system_view.is_open() and _host.system_view.get_current_system_id() == inspected_system_id:
		_host.system_view.show_system(system_details, neighbor_count)
	_host.claim_system_button.disabled = _host.active_empire_id.is_empty() or owner_empire_id == _host.active_empire_id
	_host.clear_owner_button.disabled = owner_empire_id.is_empty()


func get_inspected_system_id() -> String:
	if not _host.pinned_system_id.is_empty():
		return _host.pinned_system_id
	return _host.hovered_system_id


func invalidate_system_panel_snapshot(system_id: String = "") -> void:
	if system_id.is_empty():
		_host._system_panel_snapshot_cache.clear()
		_host._system_panel_snapshot_token += 1
		return
	_host._system_panel_snapshot_cache.erase(system_id)
	_host._system_panel_snapshot_token += 1


func update_system_panel_preview(system_id: String, system_details: Dictionary) -> void:
	if _host._system_panel_snapshot_cache.has(system_id):
		_host.system_preview_image.texture = _host._system_panel_snapshot_cache[system_id]
		return

	_host.system_preview_image.texture = null
	_host._system_panel_snapshot_token += 1
	Callable(self, "_capture_system_panel_snapshot").call_deferred(system_id, system_details, _host._system_panel_snapshot_token)


func _capture_system_panel_snapshot(system_id: String, system_details: Dictionary, request_token: int) -> void:
	if request_token != _host._system_panel_snapshot_token:
		return

	_host.system_snapshot_preview.set_system_details(system_details)
	_host.system_snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await _host.get_tree().process_frame

	if request_token != _host._system_panel_snapshot_token:
		return

	var snapshot_image: Image = _host.system_snapshot_viewport.get_texture().get_image()
	if snapshot_image == null or snapshot_image.is_empty():
		return

	var snapshot_texture := ImageTexture.create_from_image(snapshot_image)
	_host._system_panel_snapshot_cache[system_id] = snapshot_texture
	_host.system_snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_host.system_snapshot_preview.clear_preview()

	if _resolve_preview_target_system_id(get_inspected_system_id()) == system_id:
		_host.system_preview_image.texture = snapshot_texture


func _refresh_hover_preview_tracking(inspected_system_id: String) -> void:
	if not _is_hover_preview_candidate(inspected_system_id):
		_cancel_hover_preview_delay()
		return

	if _hover_preview_ready_system_id == inspected_system_id:
		_hover_preview_pending_system_id = inspected_system_id
		return

	if _hover_preview_pending_system_id == inspected_system_id:
		return

	_hover_preview_pending_system_id = inspected_system_id
	_hover_preview_ready_system_id = ""
	_hover_preview_sequence += 1
	var request_sequence: int = _hover_preview_sequence
	Callable(self, "_complete_hover_preview_delay").call_deferred(inspected_system_id, request_sequence)


func _complete_hover_preview_delay(system_id: String, request_sequence: int) -> void:
	if _host == null:
		return

	await _host.get_tree().create_timer(HOVER_PREVIEW_DELAY_SEC).timeout

	if _host == null:
		return
	if request_sequence != _hover_preview_sequence:
		return
	if _hover_preview_pending_system_id != system_id:
		return
	if not _is_hover_preview_candidate(system_id):
		return

	_hover_preview_ready_system_id = system_id
	_host._update_system_panel()


func _resolve_preview_target_system_id(inspected_system_id: String) -> String:
	if inspected_system_id.is_empty():
		return ""
	if _is_preview_interaction_blocked():
		return ""
	if _host.system_view.is_open() and _host.system_view.get_current_system_id() == inspected_system_id:
		return inspected_system_id
	if not _host.pinned_system_id.is_empty():
		return inspected_system_id
	if _hover_preview_ready_system_id == inspected_system_id:
		return inspected_system_id
	return ""


func _is_preview_interaction_blocked() -> bool:
	return _host.camera_rig != null and _host.camera_rig.has_method("is_middle_dragging") and _host.camera_rig.is_middle_dragging()


func _is_hover_preview_candidate(inspected_system_id: String) -> bool:
	if inspected_system_id.is_empty():
		return false
	if not _host.systems_by_id.has(inspected_system_id):
		return false
	if _is_preview_interaction_blocked():
		return false
	if _host.system_view.is_open():
		return false
	if not _host.pinned_system_id.is_empty():
		return false
	return _host.hovered_system_id == inspected_system_id


func _clear_system_panel_preview() -> void:
	if _host == null:
		return
	if _active_preview_system_id.is_empty() and _host.system_preview_image.texture == null:
		return
	_active_preview_system_id = ""
	_host.system_preview_image.texture = null
	_host._system_panel_snapshot_token += 1


func _cancel_hover_preview_delay() -> void:
	_hover_preview_pending_system_id = ""
	_hover_preview_ready_system_id = ""
	_hover_preview_sequence += 1


func _reset_hover_preview_state() -> void:
	_cancel_hover_preview_delay()
	_active_preview_system_id = ""


func populate_empire_picker() -> void:
	_host.empire_picker_list.clear()

	for empire_index in range(_host.empire_records.size()):
		var empire_record: Dictionary = _host.empire_records[empire_index]
		var empire_id: String = str(empire_record.get("id", ""))
		var controller_kind: String = str(empire_record.get("controller_kind", "unassigned"))
		var item_text := "%s  [%s]" % [empire_record.get("name", empire_id), format_controller_kind(controller_kind)]
		_host.empire_picker_list.add_item(item_text)
		var item_index: int = _host.empire_picker_list.get_item_count() - 1
		_host.empire_picker_list.set_item_metadata(item_index, empire_id)
		_host.empire_picker_list.set_item_custom_fg_color(item_index, empire_record.get("color", Color.WHITE))

		if empire_id == _host.active_empire_id:
			_host.empire_picker_list.select(item_index)

	_host.select_empire_button.disabled = get_selected_empire_id_from_picker().is_empty()
	_host.cancel_empire_picker_button.visible = not _host._empire_picker_requires_selection
	_host.cancel_empire_picker_button.disabled = _host._empire_picker_requires_selection


func open_empire_picker(requires_selection: bool) -> void:
	_host._empire_picker_requires_selection = requires_selection
	populate_empire_picker()
	set_empire_picker_visible(true, requires_selection)


func set_empire_picker_visible(visible_state: bool, requires_selection: bool = false) -> void:
	_host._empire_picker_requires_selection = requires_selection
	_host.empire_picker_overlay.visible = visible_state
	_host.cancel_empire_picker_button.visible = visible_state and not requires_selection
	_host.cancel_empire_picker_button.disabled = requires_selection
	refresh_camera_input_block()


func set_settings_overlay_visible(visible_state: bool) -> void:
	_host.galaxy_hud.set_settings_visible(visible_state)
	refresh_camera_input_block()


func set_loading_state(visible_state: bool, status_text: String = "", progress_ratio: float = 0.0) -> void:
	_host.loading_overlay.visible = visible_state
	if not status_text.is_empty():
		_host.loading_status.text = status_text
	_host.loading_progress.value = clampf(progress_ratio, 0.0, 1.0) * 100.0
	refresh_camera_input_block()


func refresh_camera_input_block() -> void:
	if _host.camera_rig.has_method("set_input_blocked"):
		_host.camera_rig.set_input_blocked(_host._is_generating or _host.loading_overlay.visible or _host.empire_picker_overlay.visible or _host.galaxy_hud.is_settings_visible() or _host.system_view.is_open())
	_host.bottom_category_bar.set_interaction_enabled(not (_host._is_generating or _host.loading_overlay.visible or _host.empire_picker_overlay.visible or _host.galaxy_hud.is_settings_visible() or _host.system_view.is_open()))


func set_galaxy_presentation_visible(visible_state: bool) -> void:
	var nodes := {
		"stars": _host.stars,
		"hyperlanes": _host.hyperlanes,
		"runtime_placeholders": _host.runtime_placeholders,
		"system_panel": _host.system_panel,
		"bottom_category_bar": _host.bottom_category_bar,
		"info_label": _host.info_label,
		"galaxy_hud": _host.galaxy_hud,
	}

	if not visible_state:
		_host._galaxy_presentation_visibility.clear()
		for node_key in nodes.keys():
			var node = nodes[node_key]
			_host._galaxy_presentation_visibility[node_key] = node.visible
			node.visible = false
		return

	for node_key in nodes.keys():
		var node = nodes[node_key]
		node.visible = bool(_host._galaxy_presentation_visibility.get(node_key, true))


func open_system_view(system_id: String) -> void:
	if system_id.is_empty() or not _host.systems_by_id.has(system_id):
		return
	_host.selected_system_id = system_id
	var system_details: Dictionary = _host.get_system_details(system_id)
	var neighbor_count: int = _host.galaxy_state.get_neighbor_system_ids(system_id).size()
	set_galaxy_presentation_visible(false)
	_host.system_view.show_system(system_details, neighbor_count)
	refresh_camera_input_block()


func close_system_view() -> void:
	_host.system_view.hide_view()
	set_galaxy_presentation_visible(true)
	refresh_camera_input_block()


func update_bottom_category_bar_context(active_empire_name: String, selected_system_name: String, selected_owner_name: String) -> void:
	_host.bottom_category_bar.set_context(active_empire_name, selected_system_name, selected_owner_name)


func get_selected_empire_id_from_picker() -> String:
	var selected_items: PackedInt32Array = _host.empire_picker_list.get_selected_items()
	if selected_items.size() == 0:
		return ""
	return str(_host.empire_picker_list.get_item_metadata(int(selected_items[0])))


func format_controller_kind(controller_kind: String) -> String:
	match controller_kind:
		"local_player":
			return "Local Player"
		"remote_player":
			return "Remote Player"
		"ai":
			return "AI"
		_:
			return "Open"
