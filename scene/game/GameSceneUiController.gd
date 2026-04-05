extends Node
class_name GameSceneUiController

const HOVER_PREVIEW_DELAY_SEC: float = 1.0

var _state: GameSceneState = null
var _ui: GameSceneRefs = null
var _runtime_system: GameSceneRuntimeSystem = null
var _view_router: GameViewRouter = null
var _debug_spawner: GalaxyDebugSpawner = null
var _hover_preview_pending_system_id: String = ""
var _hover_preview_ready_system_id: String = ""
var _hover_preview_sequence: int = 0
var _active_preview_system_id: String = ""


func setup(
	state: GameSceneState,
	ui: GameSceneRefs,
	runtime_system: GameSceneRuntimeSystem,
	view_router: GameViewRouter,
	debug_spawner: GalaxyDebugSpawner
) -> void:
	_state = state
	_ui = ui
	_runtime_system = runtime_system
	_view_router = view_router
	_debug_spawner = debug_spawner


func teardown() -> void:
	_reset_hover_preview_state()
	_state = null
	_ui = null
	_runtime_system = null
	_view_router = null
	_debug_spawner = null


func update_info_label() -> void:
	if _state == null or _ui == null:
		return

	var displayed_seed: String = _state.seed_text if not _state.seed_text.is_empty() else str(_state.generated_seed)
	var active_empire_name: String = "None"
	if _state.empires_by_id.has(_state.active_empire_id):
		active_empire_name = str(_state.empires_by_id[_state.active_empire_id].get("name", active_empire_name))

	var inspected_system_id: String = get_inspected_system_id()
	var selected_summary: String = "Selected: None"
	if not inspected_system_id.is_empty() and _state.systems_by_id.has(inspected_system_id):
		var selected_owner: Dictionary = _state.galaxy_state.get_system_owner(inspected_system_id)
		var selected_owner_name: String = "Unclaimed"
		if not selected_owner.is_empty():
			selected_owner_name = str(selected_owner.get("name", selected_owner_name))
		selected_summary = "Selected: %s (%s)" % [_state.systems_by_id[inspected_system_id].get("name", inspected_system_id), selected_owner_name]

	_ui.info_label.text = "Seed: %s\nSystems: %d  Shape: %s  Hyperlanes: %d  Empires: %d\nActive Empire: %s  %s\nPan: WASD / Arrows / Edge / Middle Drag  Orbit: Right Drag  Zoom: Mouse Wheel  Pick Empire: E  Regenerate: R  System View: Left Click  Back: Esc closes overlays and returns to galaxy" % [
		displayed_seed,
		_state.system_positions.size(),
		_state.galaxy_shape.capitalize(),
		_state.hyperlane_density,
		_state.empire_records.size(),
		active_empire_name,
		selected_summary,
	]
	_ui.info_label.visible = not _view_router.is_system_view_open()


func update_system_panel() -> void:
	if _state == null or _ui == null:
		return

	var inspected_system_id: String = get_inspected_system_id()
	_state.selected_system_id = inspected_system_id
	var active_empire_name: String = "None selected"
	_ui.change_empire_button.text = "Choose Empire"
	_ui.claim_system_button.text = "Claim Selected System"
	_ui.claim_system_button.modulate = Color.WHITE

	if _state.empires_by_id.has(_state.active_empire_id):
		var active_empire: Dictionary = _state.empires_by_id[_state.active_empire_id]
		active_empire_name = str(active_empire.get("name", active_empire_name))
		_ui.change_empire_button.text = "Change Empire"
		_ui.claim_system_button.text = "Claim for %s" % active_empire_name
		_ui.claim_system_button.modulate = active_empire.get("color", Color.WHITE)

	_ui.empire_status_label.text = "Active Empire: %s" % active_empire_name

	var selected_system_name: String = "No system selected"
	var selected_owner_name: String = "Unclaimed"
	if not inspected_system_id.is_empty() and _state.systems_by_id.has(inspected_system_id):
		selected_system_name = str(_state.systems_by_id[inspected_system_id].get("name", inspected_system_id))
		var selected_owner_empire_id: String = _state.galaxy_state.get_system_owner_id(inspected_system_id)
		if _state.empires_by_id.has(selected_owner_empire_id):
			selected_owner_name = str(_state.empires_by_id[selected_owner_empire_id].get("name", selected_owner_name))

	update_bottom_category_bar_context(active_empire_name, selected_system_name, selected_owner_name)
	_sync_debug_spawner_defaults(inspected_system_id)
	var bottom_drawer_entries: Dictionary = _runtime_system.build_bottom_drawer_runtime_entries(inspected_system_id)
	_ui.bottom_category_bar.set_runtime_entries(
		bottom_drawer_entries.get("starbases", []),
		bottom_drawer_entries.get("passive_fleets", []),
		bottom_drawer_entries.get("military_fleets", [])
	)

	if inspected_system_id.is_empty() or not _state.systems_by_id.has(inspected_system_id):
		_clear_system_panel_preview()
		_ui.system_panel.visible = false
		_ui.selected_system_title.text = "No system selected"
		_ui.selected_system_meta.text = "Left-click a star system to inspect it. The galaxy map keeps compact summary data for every system, while richer stars, planets, belts, ruins, and structures are resolved on demand for the selected system."
		_ui.system_preview_image.texture = null
		_ui.claim_system_button.disabled = _state.active_empire_id.is_empty()
		_ui.clear_owner_button.disabled = true
		return

	var system_record: Dictionary = _state.systems_by_id[inspected_system_id]
	var owner_empire_id: String = _state.galaxy_state.get_system_owner_id(inspected_system_id)
	var owner_name: String = "Unclaimed"
	if _state.empires_by_id.has(owner_empire_id):
		owner_name = str(_state.empires_by_id[owner_empire_id].get("name", owner_name))

	var system_details: Dictionary = _runtime_system.get_system_details(inspected_system_id)
	var summary: Dictionary = system_details.get("system_summary", system_record.get("system_summary", {}))
	var star_profile: Dictionary = system_details.get("star_profile", system_record.get("star_profile", {}))
	var space_presence: Dictionary = system_details.get("space_presence", {})
	var neighbor_count: int = _state.galaxy_state.get_neighbor_system_ids(inspected_system_id).size()
	var star_count_label: int = int(summary.get("star_count", star_profile.get("star_count", 1)))
	var star_class: String = str(star_profile.get("star_class", "G"))
	var special_type: String = str(star_profile.get("special_type", "none"))
	var special_label: String = ""
	if special_type != "none":
		special_label = "  Special: %s" % special_type

	_ui.selected_system_title.text = str(system_record.get("name", inspected_system_id))
	_ui.selected_system_meta.text = "Owner: %s\nStar Class: %s  Stars: %d%s\nHyperlane Connections: %d\nPlanets: %d  Belts: %d  Structures: %d  Ruins: %d\nLocal Presence: Fleets %d  Mobile %d  Stations %d\nHabitable: %d  Colonizable: %d  Anomaly Risk: %d%%" % [
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
	if _view_router.is_system_view_open() and _view_router.get_current_system_view_id() == inspected_system_id:
		_view_router.refresh_system_view(system_details, neighbor_count)

	_ui.system_panel.visible = not _view_router.is_system_view_open()
	_ui.claim_system_button.disabled = _state.active_empire_id.is_empty() or owner_empire_id == _state.active_empire_id
	_ui.clear_owner_button.disabled = owner_empire_id.is_empty()


func get_inspected_system_id() -> String:
	if _state == null:
		return ""
	if _view_router.is_system_view_open():
		return _view_router.get_current_system_view_id()
	if not _state.pinned_system_id.is_empty():
		return _state.pinned_system_id
	return _state.hovered_system_id


func invalidate_system_panel_snapshot(system_id: String = "") -> void:
	if _state == null:
		return
	if system_id.is_empty():
		_state.system_panel_snapshot_cache.clear()
		_state.system_panel_snapshot_token += 1
		return
	_state.system_panel_snapshot_cache.erase(system_id)
	_state.system_panel_snapshot_token += 1


func update_system_panel_preview(system_id: String, system_details: Dictionary) -> void:
	if _state == null or _ui == null:
		return
	if _state.system_panel_snapshot_cache.has(system_id):
		_ui.system_preview_image.texture = _state.system_panel_snapshot_cache[system_id]
		return

	_ui.system_preview_image.texture = null
	_state.system_panel_snapshot_token += 1
	Callable(self, "_capture_system_panel_snapshot").call_deferred(system_id, system_details, _state.system_panel_snapshot_token)


func _capture_system_panel_snapshot(system_id: String, system_details: Dictionary, request_token: int) -> void:
	if _state == null or _ui == null:
		return
	if request_token != _state.system_panel_snapshot_token:
		return

	_ui.system_snapshot_preview.set_system_details(system_details)
	_ui.system_snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame

	if request_token != _state.system_panel_snapshot_token:
		return

	var snapshot_image: Image = _ui.system_snapshot_viewport.get_texture().get_image()
	if snapshot_image == null or snapshot_image.is_empty():
		return

	var snapshot_texture: ImageTexture = ImageTexture.create_from_image(snapshot_image)
	_state.system_panel_snapshot_cache[system_id] = snapshot_texture
	_ui.system_snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_ui.system_snapshot_preview.clear_preview()

	if _resolve_preview_target_system_id(get_inspected_system_id()) == system_id:
		_ui.system_preview_image.texture = snapshot_texture


func populate_empire_picker() -> void:
	if _state == null or _ui == null:
		return
	_ui.empire_picker_list.clear()

	for empire_index in range(_state.empire_records.size()):
		var empire_record: Dictionary = _state.empire_records[empire_index]
		var empire_id: String = str(empire_record.get("id", ""))
		var controller_kind: String = str(empire_record.get("controller_kind", "unassigned"))
		var item_text: String = "%s  [%s]" % [empire_record.get("name", empire_id), format_controller_kind(controller_kind)]
		_ui.empire_picker_list.add_item(item_text)
		var item_index: int = _ui.empire_picker_list.get_item_count() - 1
		_ui.empire_picker_list.set_item_metadata(item_index, empire_id)
		_ui.empire_picker_list.set_item_custom_fg_color(item_index, empire_record.get("color", Color.WHITE))

		if empire_id == _state.active_empire_id:
			_ui.empire_picker_list.select(item_index)

	_ui.select_empire_button.disabled = get_selected_empire_id_from_picker().is_empty()
	_ui.cancel_empire_picker_button.visible = not _state.empire_picker_requires_selection
	_ui.cancel_empire_picker_button.disabled = _state.empire_picker_requires_selection


func open_empire_picker(requires_selection: bool) -> void:
	if _state == null:
		return
	_state.empire_picker_requires_selection = requires_selection
	populate_empire_picker()
	set_empire_picker_visible(true, requires_selection)


func set_empire_picker_visible(visible_state: bool, requires_selection: bool = false) -> void:
	if _state == null or _ui == null:
		return
	_state.empire_picker_requires_selection = requires_selection
	_ui.empire_picker_overlay.visible = visible_state
	_ui.cancel_empire_picker_button.visible = visible_state and not requires_selection
	_ui.cancel_empire_picker_button.disabled = requires_selection
	refresh_camera_input_block()


func set_settings_overlay_visible(visible_state: bool) -> void:
	if _ui == null:
		return
	_ui.galaxy_hud.set_settings_visible(visible_state)
	refresh_camera_input_block()


func set_loading_state(visible_state: bool, status_text: String = "", progress_ratio: float = 0.0) -> void:
	if _ui == null:
		return
	_ui.loading_overlay.visible = visible_state
	if not status_text.is_empty():
		_ui.loading_status.text = status_text
	_ui.loading_progress.value = clampf(progress_ratio, 0.0, 1.0) * 100.0
	refresh_camera_input_block()


func refresh_camera_input_block() -> void:
	if _state == null or _ui == null or _view_router == null:
		return
	var block_galaxy_camera: bool = _state.is_generating or _ui.loading_overlay.visible or _ui.empire_picker_overlay.visible or _ui.galaxy_hud.is_settings_visible() or _view_router.is_system_view_open()
	_view_router.set_galaxy_camera_input_blocked(block_galaxy_camera)
	var block_shared_ui: bool = _state.is_generating or _ui.loading_overlay.visible or _ui.empire_picker_overlay.visible or _ui.galaxy_hud.is_settings_visible()
	_ui.bottom_category_bar.set_interaction_enabled(not block_shared_ui)


func set_galaxy_presentation_visible(visible_state: bool) -> void:
	if _state == null or _ui == null:
		return
	var nodes: Dictionary = {
		"system_panel": _ui.system_panel,
		"info_label": _ui.info_label,
	}

	if not visible_state:
		_state.galaxy_presentation_visibility.clear()
		for node_key_variant in nodes.keys():
			var node_key: String = str(node_key_variant)
			var node: CanvasItem = nodes[node_key]
			_state.galaxy_presentation_visibility[node_key] = node.visible
			node.visible = false
		return

	for node_key_variant in nodes.keys():
		var node_key: String = str(node_key_variant)
		var node: CanvasItem = nodes[node_key]
		node.visible = bool(_state.galaxy_presentation_visibility.get(node_key, true))


func open_system_view(system_id: String) -> void:
	if _state == null or system_id.is_empty() or not _state.systems_by_id.has(system_id):
		return
	_state.selected_system_id = system_id
	var system_details: Dictionary = _runtime_system.get_system_details(system_id)
	var neighbor_count: int = _state.galaxy_state.get_neighbor_system_ids(system_id).size()
	set_galaxy_presentation_visible(false)
	_view_router.show_system_view(system_details, neighbor_count)
	refresh_camera_input_block()


func close_system_view() -> void:
	if _view_router == null:
		return
	_view_router.show_galaxy_view()
	set_galaxy_presentation_visible(true)
	update_system_panel()
	update_info_label()
	refresh_camera_input_block()


func update_bottom_category_bar_context(active_empire_name: String, selected_system_name: String, selected_owner_name: String) -> void:
	if _ui != null:
		_ui.bottom_category_bar.set_context(active_empire_name, selected_system_name, selected_owner_name)


func get_selected_empire_id_from_picker() -> String:
	if _ui == null or _ui.empire_picker_list.get_selected_items().is_empty():
		return ""
	var selected_index: int = _ui.empire_picker_list.get_selected_items()[0]
	return str(_ui.empire_picker_list.get_item_metadata(selected_index))


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
	if _state == null:
		return

	await get_tree().create_timer(HOVER_PREVIEW_DELAY_SEC).timeout

	if _state == null:
		return
	if request_sequence != _hover_preview_sequence:
		return
	if _hover_preview_pending_system_id != system_id:
		return
	if not _is_hover_preview_candidate(system_id):
		return

	_hover_preview_ready_system_id = system_id
	update_system_panel()


func _resolve_preview_target_system_id(inspected_system_id: String) -> String:
	if inspected_system_id.is_empty():
		return ""
	if _is_preview_interaction_blocked():
		return ""
	if _view_router.is_system_view_open() and _view_router.get_current_system_view_id() == inspected_system_id:
		return inspected_system_id
	if not _state.pinned_system_id.is_empty():
		return inspected_system_id
	if _hover_preview_ready_system_id == inspected_system_id:
		return inspected_system_id
	return ""


func _is_preview_interaction_blocked() -> bool:
	var galaxy_view: GalaxyMapView = _view_router.get_galaxy_view()
	return galaxy_view != null and galaxy_view.is_middle_dragging()


func _is_hover_preview_candidate(inspected_system_id: String) -> bool:
	if inspected_system_id.is_empty():
		return false
	if not _state.systems_by_id.has(inspected_system_id):
		return false
	if _is_preview_interaction_blocked():
		return false
	if _view_router.is_system_view_open():
		return false
	if not _state.pinned_system_id.is_empty():
		return false
	return _state.hovered_system_id == inspected_system_id


func _clear_system_panel_preview() -> void:
	if _state == null or _ui == null:
		return
	if _active_preview_system_id.is_empty() and _ui.system_preview_image.texture == null:
		return
	_active_preview_system_id = ""
	_ui.system_preview_image.texture = null
	_state.system_panel_snapshot_token += 1


func _cancel_hover_preview_delay() -> void:
	_hover_preview_pending_system_id = ""
	_hover_preview_ready_system_id = ""
	_hover_preview_sequence += 1


func _reset_hover_preview_state() -> void:
	_cancel_hover_preview_delay()
	_active_preview_system_id = ""


func _sync_debug_spawner_defaults(inspected_system_id: String) -> void:
	if _debug_spawner == null:
		return
	_debug_spawner.sync_defaults(_state.active_empire_id, inspected_system_id, _state.empire_records, _state.system_records)
