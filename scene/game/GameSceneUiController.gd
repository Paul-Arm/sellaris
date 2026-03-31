extends RefCounted
class_name GameSceneUiController

var _host: Node = null


func bind(host: Node) -> void:
	_host = host


func unbind() -> void:
	_host = null


func update_info_label() -> void:
	if _host == null:
		return

	var displayed_seed: String = _host.seed_text if not _host.seed_text.is_empty() else str(_host.generated_seed)
	var active_empire_name: String = "None"
	if _host.empires_by_id.has(_host.active_empire_id):
		active_empire_name = str(_host.empires_by_id[_host.active_empire_id].get("name", active_empire_name))

	var inspected_system_id: String = get_inspected_system_id()
	var selected_summary: String = "Selected: None"
	if not inspected_system_id.is_empty() and _host.systems_by_id.has(inspected_system_id):
		var selected_owner: Dictionary = _host.galaxy_state.get_system_owner(inspected_system_id)
		var selected_owner_name: String = "Unclaimed"
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
	_host.info_label.visible = not _host.is_system_view_open()


func update_system_panel() -> void:
	if _host == null:
		return

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
		_host.system_panel.visible = false
		_host.selected_system_title.text = "No system selected"
		_host.selected_system_meta.text = "Left-click a star system to inspect it. The galaxy map keeps compact summary data for every system, while richer stars, planets, belts, ruins, and structures are resolved on demand for the selected system."
		_host.system_preview_image.texture = null
		_host.claim_system_button.disabled = _host.active_empire_id.is_empty()
		_host.clear_owner_button.disabled = true
		return

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
	update_system_panel_preview(inspected_system_id, system_details)
	if _host.is_system_view_open() and _host.get_current_system_view_id() == inspected_system_id:
		_host.refresh_system_view(system_details, neighbor_count)

	_host.system_panel.visible = not _host.is_system_view_open()
	_host.claim_system_button.disabled = _host.active_empire_id.is_empty() or owner_empire_id == _host.active_empire_id
	_host.clear_owner_button.disabled = owner_empire_id.is_empty()


func get_inspected_system_id() -> String:
	if _host == null:
		return ""
	if _host.is_system_view_open():
		return _host.get_current_system_view_id()
	if not _host.pinned_system_id.is_empty():
		return _host.pinned_system_id
	return _host.hovered_system_id


func invalidate_system_panel_snapshot(system_id: String = "") -> void:
	if _host == null:
		return
	if system_id.is_empty():
		_host._system_panel_snapshot_cache.clear()
		_host._system_panel_snapshot_token += 1
		return
	_host._system_panel_snapshot_cache.erase(system_id)
	_host._system_panel_snapshot_token += 1


func update_system_panel_preview(system_id: String, system_details: Dictionary) -> void:
	if _host == null:
		return
	if _host._system_panel_snapshot_cache.has(system_id):
		_host.system_preview_image.texture = _host._system_panel_snapshot_cache[system_id]
		return

	_host.system_preview_image.texture = null
	_host._system_panel_snapshot_token += 1
	Callable(self, "_capture_system_panel_snapshot").call_deferred(system_id, system_details, _host._system_panel_snapshot_token)


func _capture_system_panel_snapshot(system_id: String, system_details: Dictionary, request_token: int) -> void:
	if _host == null:
		return
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

	var snapshot_texture: ImageTexture = ImageTexture.create_from_image(snapshot_image)
	_host._system_panel_snapshot_cache[system_id] = snapshot_texture
	_host.system_snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_host.system_snapshot_preview.clear_preview()

	if get_inspected_system_id() == system_id:
		_host.system_preview_image.texture = snapshot_texture


func populate_empire_picker() -> void:
	if _host == null:
		return
	_host.empire_picker_list.clear()

	for empire_index in range(_host.empire_records.size()):
		var empire_record: Dictionary = _host.empire_records[empire_index]
		var empire_id: String = str(empire_record.get("id", ""))
		var controller_kind: String = str(empire_record.get("controller_kind", "unassigned"))
		var item_text: String = "%s  [%s]" % [empire_record.get("name", empire_id), format_controller_kind(controller_kind)]
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
	if _host == null:
		return
	_host._empire_picker_requires_selection = requires_selection
	populate_empire_picker()
	set_empire_picker_visible(true, requires_selection)


func set_empire_picker_visible(visible_state: bool, requires_selection: bool = false) -> void:
	if _host == null:
		return
	_host._empire_picker_requires_selection = requires_selection
	_host.empire_picker_overlay.visible = visible_state
	_host.cancel_empire_picker_button.visible = visible_state and not requires_selection
	_host.cancel_empire_picker_button.disabled = requires_selection
	refresh_camera_input_block()


func set_settings_overlay_visible(visible_state: bool) -> void:
	if _host == null:
		return
	_host.galaxy_hud.set_settings_visible(visible_state)
	refresh_camera_input_block()


func set_loading_state(visible_state: bool, status_text: String = "", progress_ratio: float = 0.0) -> void:
	if _host == null:
		return
	_host.loading_overlay.visible = visible_state
	if not status_text.is_empty():
		_host.loading_status.text = status_text
	_host.loading_progress.value = clampf(progress_ratio, 0.0, 1.0) * 100.0
	refresh_camera_input_block()


func refresh_camera_input_block() -> void:
	if _host == null:
		return
	var block_galaxy_camera: bool = _host._is_generating or _host.loading_overlay.visible or _host.empire_picker_overlay.visible or _host.galaxy_hud.is_settings_visible() or _host.is_system_view_open()
	_host.set_galaxy_camera_input_blocked(block_galaxy_camera)
	var block_shared_ui: bool = _host._is_generating or _host.loading_overlay.visible or _host.empire_picker_overlay.visible or _host.galaxy_hud.is_settings_visible()
	_host.bottom_category_bar.set_interaction_enabled(not block_shared_ui)


func set_galaxy_presentation_visible(visible_state: bool) -> void:
	if _host == null:
		return
	var nodes: Dictionary = {
		"system_panel": _host.system_panel,
		"info_label": _host.info_label,
	}

	if not visible_state:
		_host._galaxy_presentation_visibility.clear()
		for node_key_variant in nodes.keys():
			var node_key: String = str(node_key_variant)
			var node: CanvasItem = nodes[node_key]
			_host._galaxy_presentation_visibility[node_key] = node.visible
			node.visible = false
		return

	for node_key_variant in nodes.keys():
		var node_key: String = str(node_key_variant)
		var node: CanvasItem = nodes[node_key]
		node.visible = bool(_host._galaxy_presentation_visibility.get(node_key, true))


func open_system_view(system_id: String) -> void:
	if _host == null:
		return
	if system_id.is_empty() or not _host.systems_by_id.has(system_id):
		return
	_host.selected_system_id = system_id
	var system_details: Dictionary = _host.get_system_details(system_id)
	var neighbor_count: int = _host.galaxy_state.get_neighbor_system_ids(system_id).size()
	set_galaxy_presentation_visible(false)
	_host.show_system_view(system_details, neighbor_count)
	refresh_camera_input_block()


func close_system_view() -> void:
	if _host == null:
		return
	_host.show_galaxy_view()
	set_galaxy_presentation_visible(true)
	update_system_panel()
	update_info_label()
	refresh_camera_input_block()


func update_bottom_category_bar_context(active_empire_name: String, selected_system_name: String, selected_owner_name: String) -> void:
	if _host != null:
		_host.bottom_category_bar.set_context(active_empire_name, selected_system_name, selected_owner_name)


func get_selected_empire_id_from_picker() -> String:
	if _host == null or _host.empire_picker_list.get_selected_items().is_empty():
		return ""
	var selected_index: int = _host.empire_picker_list.get_selected_items()[0]
	return str(_host.empire_picker_list.get_item_metadata(selected_index))


func format_controller_kind(controller_kind: String) -> String:
	match controller_kind:
		"player_local":
			return "Player"
		"player_remote":
			return "Remote Player"
		"ai":
			return "AI"
		_:
			return "Unassigned"
