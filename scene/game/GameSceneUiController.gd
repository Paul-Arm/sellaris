extends Node
class_name GameSceneUiController

const COLONY_MODAL_SCRIPT := preload("res://scene/game/ColonyModal.gd")
const SHIP_DESIGNER_MODAL_SCRIPT := preload("res://scene/game/ShipDesignerModal.gd")
const RESEARCH_MODAL_SCRIPT := preload("res://scene/game/ResearchModal.gd")
const NOTIFICATION_CENTER_SCRIPT := preload("res://scene/UI/NotificationCenter.gd")
const DEBUG_INFO_PANEL_SCRIPT := preload("res://scene/UI/GalaxyDebugInfoPanel.gd")
const SPACE_ENTITY_DETAILS_PANEL_SCRIPT := preload("res://scene/game/SpaceEntityDetailsPanel.gd")
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
var _colony_modal: Control = null
var _ship_designer_modal: Control = null
var _research_modal: Control = null
var _notification_center: Control = null
var _manage_colony_button: Button = null
var _manage_colony_id: String = ""
var _open_colony_id: String = ""
var _debug_info_panel: GalaxyDebugInfoPanel = null
var _space_entity_panel: SpaceEntityDetailsPanel = null


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
	_ensure_debug_info_panel()
	_ensure_colony_controls()
	_ensure_space_entity_panel()
	if not ColonyManager.colony_updated.is_connected(_on_colony_updated):
		ColonyManager.colony_updated.connect(_on_colony_updated)
	update_debug_reveal_button()
	refresh_empire_command_drawer()


func teardown() -> void:
	_reset_hover_preview_state()
	if ColonyManager.colony_updated.is_connected(_on_colony_updated):
		ColonyManager.colony_updated.disconnect(_on_colony_updated)
	if _colony_modal != null:
		_colony_modal.queue_free()
	if _ship_designer_modal != null:
		_ship_designer_modal.queue_free()
	if _research_modal != null:
		_research_modal.queue_free()
	if _notification_center != null:
		_notification_center.queue_free()
	if _space_entity_panel != null:
		_space_entity_panel.queue_free()
	_colony_modal = null
	_ship_designer_modal = null
	_research_modal = null
	_notification_center = null
	_manage_colony_button = null
	_debug_info_panel = null
	_space_entity_panel = null
	_state = null
	_ui = null
	_runtime_system = null
	_view_router = null
	_debug_spawner = null


func _ensure_debug_info_panel() -> void:
	if _ui == null or _ui.canvas_layer == null or _ui.info_label == null:
		return
	var action_buttons: Array[Button] = []
	if _ui.debug_spawn_toggle_button != null:
		action_buttons.append(_ui.debug_spawn_toggle_button)
	if _ui.debug_reveal_toggle_button != null:
		action_buttons.append(_ui.debug_reveal_toggle_button)
	_debug_info_panel = DEBUG_INFO_PANEL_SCRIPT.install(_ui.canvas_layer, _ui.info_label, action_buttons)
	if _ui.debug_spawn_panel != null:
		_ui.debug_spawn_panel.offset_left = 18.0
		_ui.debug_spawn_panel.offset_top = 262.0
		_ui.debug_spawn_panel.offset_right = 386.0
		_ui.debug_spawn_panel.offset_bottom = 584.0


func _ensure_space_entity_panel() -> void:
	if _ui == null or _ui.canvas_layer == null:
		return
	if is_instance_valid(_space_entity_panel):
		return
	_space_entity_panel = SPACE_ENTITY_DETAILS_PANEL_SCRIPT.new() as SpaceEntityDetailsPanel
	_space_entity_panel.name = "SpaceEntityDetailsPanel"
	_ui.canvas_layer.add_child(_space_entity_panel)
	_space_entity_panel.action_requested.connect(_on_space_entity_panel_action_requested)
	_space_entity_panel.member_selected.connect(_on_space_entity_panel_member_selected)


func update_info_label() -> void:
	if _state == null or _ui == null or _runtime_system == null:
		return

	var displayed_seed: String = _state.seed_text if not _state.seed_text.is_empty() else str(_state.generated_seed)
	var active_empire_name: String = "None"
	if _state.empires_by_id.has(_state.active_empire_id):
		active_empire_name = str(_state.empires_by_id[_state.active_empire_id].get("name", active_empire_name))

	var inspected_system_id: String = get_inspected_system_id()
	var selected_summary: String = "Selected: None"
	var inspected_system_details: Dictionary = {}
	if not inspected_system_id.is_empty() and _state.systems_by_id.has(inspected_system_id):
		inspected_system_details = _runtime_system.get_system_details(inspected_system_id)
	if (
		not inspected_system_id.is_empty()
		and _state.systems_by_id.has(inspected_system_id)
		and not inspected_system_details.is_empty()
	):
		var selected_owner_name: String = str(inspected_system_details.get("owner_name", "Unknown"))
		selected_summary = "Selected: %s (%s)" % [_state.systems_by_id[inspected_system_id].get("name", inspected_system_id), selected_owner_name]

	var command_summary := "Command: None"
	if not _state.selected_space_entity_id.is_empty():
		var command_title := _state.selected_space_entity_title
		if command_title.is_empty():
			command_title = _state.selected_space_entity_id
		var right_click_order := "move"
		var selected_unit: SpaceUnitRuntime = SpaceManager.get_unit(_state.selected_space_entity_id)
		if selected_unit != null and selected_unit.can_explore_systems():
			right_click_order = "explore"
		command_summary = "Command: %s  |  Right-click a hyperlane-reachable system to %s" % [command_title, right_click_order]

	_ui.info_label.text = "Seed %s\nSystems %d  Shape %s  Lanes %d  Empires %d\nEmpire %s\n%s\n%s\nWASD/Arrows pan  RMB orbit  Wheel zoom\nE empire  R regenerate  Click inspect  Esc back" % [
		displayed_seed,
		_state.system_positions.size(),
		_state.galaxy_shape.capitalize(),
		_state.hyperlane_density,
		_state.empire_records.size(),
		active_empire_name,
		selected_summary,
		command_summary,
	]
	_ui.info_label.visible = not _view_router.is_system_view_open()
	if _debug_info_panel != null:
		_debug_info_panel.visible = _ui.info_label.visible


func update_system_panel() -> void:
	if _state == null or _ui == null or _runtime_system == null:
		return

	var inspected_system_id: String = get_inspected_system_id()
	_state.selected_system_id = inspected_system_id
	var active_empire_name: String = "None selected"
	_ui.change_empire_button.text = "Choose Empire"
	_ui.claim_system_button.text = "Claim Selected System"
	_ui.claim_system_button.modulate = Color.WHITE
	_set_manage_colony_button_state("", false)

	if _state.empires_by_id.has(_state.active_empire_id):
		var active_empire: Dictionary = _state.empires_by_id[_state.active_empire_id]
		active_empire_name = str(active_empire.get("name", active_empire_name))
		_ui.change_empire_button.text = "Change Empire"
		_ui.claim_system_button.text = "Claim for %s" % active_empire_name
		_ui.claim_system_button.modulate = active_empire.get("color", Color.WHITE)

	_ui.empire_status_label.text = "Active Empire: %s" % active_empire_name

	var visible_system_details: Dictionary = {}
	if not inspected_system_id.is_empty() and _state.systems_by_id.has(inspected_system_id):
		visible_system_details = _runtime_system.get_system_details(inspected_system_id)

	var selected_system_name: String = "No system selected"
	var selected_owner_name: String = "Unclaimed"
	if not visible_system_details.is_empty():
		selected_system_name = str(_state.systems_by_id[inspected_system_id].get("name", inspected_system_id))
		selected_owner_name = str(visible_system_details.get("owner_name", selected_owner_name))

	update_bottom_category_bar_context(active_empire_name, selected_system_name, selected_owner_name)
	_sync_debug_spawner_defaults(inspected_system_id)
	var bottom_drawer_entries: Dictionary = _runtime_system.build_bottom_drawer_runtime_entries(inspected_system_id)
	_ui.bottom_category_bar.set_runtime_entries(
		bottom_drawer_entries.get("starbases", []),
		bottom_drawer_entries.get("passive_fleets", []),
		bottom_drawer_entries.get("military_fleets", []),
		bottom_drawer_entries.get("planets", [])
	)
	refresh_empire_command_drawer()

	if inspected_system_id.is_empty() or not _state.systems_by_id.has(inspected_system_id):
		_clear_system_panel_preview()
		_ui.system_panel.visible = false
		_ui.selected_system_title.text = "No system selected"
		_ui.selected_system_meta.text = "Left-click a star system to inspect it. The galaxy map keeps compact summary data for every system, while richer stars, planets, belts, ruins, and structures are resolved on demand for the selected system."
		_ui.system_preview_image.texture = null
		_ui.claim_system_button.disabled = true
		_ui.clear_owner_button.disabled = true
		_ui.survey_system_button.disabled = true
		return

	var system_record: Dictionary = _state.systems_by_id[inspected_system_id]
	var owner_empire_id: String = _state.galaxy_state.get_system_owner_id(inspected_system_id)
	var owner_name: String = "Unclaimed"
	if _state.empires_by_id.has(owner_empire_id):
		owner_name = str(_state.empires_by_id[owner_empire_id].get("name", owner_name))

	var system_details: Dictionary = visible_system_details
	if system_details.is_empty():
		_clear_system_panel_preview()
		_ui.system_panel.visible = false
		_set_manage_colony_button_state("", false)
		_ui.survey_system_button.disabled = true
		return

	var summary: Dictionary = system_details.get("system_summary", system_record.get("system_summary", {}))
	var star_profile: Dictionary = system_details.get("star_profile", system_record.get("star_profile", {}))
	var space_presence: Dictionary = system_details.get("space_presence", {})
	var neighbor_count: int = _state.galaxy_state.get_neighbor_system_ids(inspected_system_id).size()
	var intel_label: String = str(system_details.get("intel_label", "Unknown"))
	var intel_level: int = int(system_details.get("intel_level", GalaxyState.INTEL_NONE))
	var has_full_intel: bool = bool(system_details.get("has_full_intel", false))
	var is_redacted: bool = bool(system_details.get("is_redacted", false))
	var show_hyperlane_count: bool = bool(system_details.get("show_hyperlane_count", true))
	var can_survey: bool = bool(system_details.get("can_survey", intel_level >= GalaxyState.INTEL_SENSOR and not has_full_intel))
	var star_count_label: int = int(summary.get("star_count", star_profile.get("star_count", 1)))
	var star_class: String = str(star_profile.get("star_class", "G"))
	var special_type: String = str(star_profile.get("special_type", "none"))
	var special_label: String = ""
	if special_type != "none":
		special_label = "  Special: %s" % special_type

	_ui.selected_system_title.text = str(system_record.get("name", inspected_system_id))
	owner_name = str(system_details.get("owner_name", owner_name))
	if is_redacted:
		var hyperlane_text: String = "Hyperlane Connections: Unknown"
		if show_hyperlane_count:
			hyperlane_text = "Hyperlane Connections: %d" % neighbor_count
		_ui.selected_system_meta.text = "Owner: %s\nIntel: %s\n%s\nDetailed bodies, local presence, and anomaly data require exploration or a survey." % [
			owner_name,
			intel_label,
			hyperlane_text,
		]
	else:
		_ui.selected_system_meta.text = "Owner: %s\nIntel: %s\nStar Class: %s  Stars: %d%s\nHyperlane Connections: %d\nPlanets: %d  Belts: %d  Structures: %d  Ruins: %d\nLocal Presence: Fleets %d  Mobile %d  Stations %d  Builds %d\nHabitable: %d  Colonizable: %d  Anomaly Risk: %d%%  Known: %d" % [
			owner_name,
			intel_label,
			star_class,
			star_count_label,
			special_label,
			neighbor_count,
			int(summary.get("planet_count", 0)),
			int(summary.get("asteroid_belt_count", 0)),
			int(summary.get("structure_count", 0)),
			int(summary.get("ruin_count", 0)),
			int(space_presence.get("fleet_count", 0)),
			int(space_presence.get("mobile_unit_count", 0)),
			int(space_presence.get("station_count", 0)),
			int(space_presence.get("construction_project_count", 0)),
			int(summary.get("habitable_worlds", 0)),
			int(summary.get("colonizable_worlds", 0)),
			int(round(float(summary.get("anomaly_risk", 0.0)) * 100.0)),
			int(system_details.get("known_anomaly_count", 0)),
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
		_sync_selected_builder_to_system_view()

	var manageable_colony_id := ""
	if has_full_intel:
		manageable_colony_id = _runtime_system.get_manageable_colony_id_for_system(inspected_system_id)
	_set_manage_colony_button_state(manageable_colony_id, not manageable_colony_id.is_empty())
	_ui.system_panel.visible = not _view_router.is_system_view_open()
	_ui.claim_system_button.disabled = _state.active_empire_id.is_empty() or owner_empire_id == _state.active_empire_id or not has_full_intel
	_ui.clear_owner_button.disabled = owner_empire_id.is_empty() or not has_full_intel
	_ui.survey_system_button.text = "Survey Complete" if has_full_intel else "Survey System"
	_ui.survey_system_button.disabled = _state.active_empire_id.is_empty() or not can_survey or has_full_intel


func get_inspected_system_id() -> String:
	if _state == null:
		return ""
	if _view_router.is_system_view_open():
		return _view_router.get_current_system_view_id()
	return _state.selected_system_panel_id


func update_selection_panel() -> void:
	_ensure_space_entity_panel()
	_sync_selected_builder_to_system_view()
	if _space_entity_panel == null or _state == null:
		return

	if _state.selected_space_entity_id.is_empty():
		_space_entity_panel.close()
		return

	match _state.selected_space_entity_kind:
		"fleet":
			_open_space_entity_panel_for_fleet(_state.selected_space_entity_id)
		SpaceUnitClass.UNIT_KIND_SHIP, SpaceUnitClass.UNIT_KIND_CREATURE, "unit":
			_open_space_entity_panel_for_unit(_state.selected_space_entity_id)
		_:
			_space_entity_panel.close()


func select_space_entity(selection_kind: String, record_id: String, title: String = "") -> void:
	if _state == null:
		return
	_state.selected_space_entity_kind = selection_kind
	_state.selected_space_entity_id = record_id
	_state.selected_space_entity_title = title
	if not record_id.is_empty():
		_state.selected_system_panel_id = ""
	_sync_galaxy_space_selection(selection_kind, record_id)
	update_selection_panel()
	update_system_panel()
	update_info_label()


func clear_space_entity_selection() -> void:
	select_space_entity("", "", "")


func _sync_galaxy_space_selection(selection_kind: String, record_id: String) -> void:
	if _view_router == null:
		return
	var galaxy_view := _view_router.get_galaxy_view()
	if galaxy_view != null:
		galaxy_view.set_selected_space_entity(selection_kind, record_id)


func _open_space_entity_panel_for_fleet(fleet_id: String) -> void:
	var fleet: SpaceFleetRuntime = SpaceManager.get_fleet(fleet_id)
	if fleet == null:
		_space_entity_panel.close()
		return
	var context := _build_space_entity_context(
		fleet.owner_empire_id,
		fleet.current_system_id,
		fleet.destination_system_id
	)
	context["fleet_id"] = fleet.fleet_id
	_space_entity_panel.open_fleet(fleet.fleet_id, context)


func _open_space_entity_panel_for_unit(unit_id: String) -> void:
	var unit: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
	if unit == null:
		_space_entity_panel.close()
		return
	var context := _build_space_entity_context(
		unit.owner_empire_id,
		unit.current_system_id,
		unit.destination_system_id
	)
	context["unit_id"] = unit.unit_id
	_space_entity_panel.open_ship(unit.unit_id, context)


func _build_space_entity_context(owner_empire_id: String, system_id: String, destination_system_id: String = "") -> Dictionary:
	var owner_names: Dictionary = {}
	if _state != null:
		for empire_id_variant in _state.empires_by_id.keys():
			var empire_id := str(empire_id_variant)
			var empire: Dictionary = _state.empires_by_id[empire_id]
			owner_names[empire_id] = str(empire.get("name", empire_id))

	var system_names: Dictionary = {}
	if _state != null:
		for system_id_variant in _state.systems_by_id.keys():
			var known_system_id := str(system_id_variant)
			var system_record: Dictionary = _state.systems_by_id[known_system_id]
			system_names[known_system_id] = str(system_record.get("name", known_system_id))

	return {
		"active_empire_id": _state.active_empire_id if _state != null else "",
		"owner_empire_id": owner_empire_id,
		"owner_name": _get_empire_display_name(owner_empire_id),
		"system_id": system_id,
		"system_name": _get_system_display_name(system_id),
		"destination_system_id": destination_system_id,
		"destination_system_name": _get_system_display_name(destination_system_id),
		"owner_names": owner_names,
		"system_names": system_names,
		"can_command": _can_command_owner(owner_empire_id),
		"can_survey_system": _can_survey_system(system_id),
	}


func _on_space_entity_panel_action_requested(action_id: String, payload: Dictionary) -> void:
	var selection_kind := _state.selected_space_entity_kind if _state != null else ""
	var selection_id := _state.selected_space_entity_id if _state != null else ""
	match action_id:
		"toggle_unit_evasion":
			SpaceManager.set_unit_evasion_mode(str(payload.get("unit_id", "")), bool(payload.get("active", false)))
		"toggle_fleet_evasion":
			SpaceManager.set_fleet_evasion_mode(str(payload.get("fleet_id", "")), bool(payload.get("active", false)))
		"set_unit_stance":
			SpaceManager.set_unit_stance(str(payload.get("unit_id", "")), str(payload.get("stance", "")))
		"set_fleet_stance":
			SpaceManager.set_fleet_stance(str(payload.get("fleet_id", "")), str(payload.get("stance", "")))
		"trigger_unit_ability":
			SpaceManager.queue_unit_ability_command(str(payload.get("unit_id", "")), str(payload.get("slot_id", "")))
		"build_ship":
			var ship_build_data: Dictionary = {}
			var ship_design_id := str(payload.get("design_id", ""))
			if not ship_design_id.is_empty():
				ship_build_data["design_id"] = ship_design_id
			SpaceManager.request_build_ship(str(payload.get("unit_id", "")), str(payload.get("class_id", "")), ship_build_data)
		"build_target":
			var unit_id := str(payload.get("unit_id", ""))
			var unit: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
			if unit != null:
				selection_kind = SpaceUnitClass.UNIT_KIND_SHIP
				selection_id = unit.unit_id
				_state.selected_space_entity_kind = selection_kind
				_state.selected_space_entity_id = selection_id
				_state.selected_space_entity_title = unit.display_name
				_state.selected_system_panel_id = ""
				_sync_galaxy_space_selection(selection_kind, selection_id)
				_sync_selected_builder_to_system_view()
		"survey_system":
			var survey_system_id := str(payload.get("system_id", ""))
			if _runtime_system != null and not survey_system_id.is_empty():
				_runtime_system.survey_system_for_active_empire(survey_system_id)
		"explore_system":
			var explore_unit_id := str(payload.get("unit_id", ""))
			var explore_system_id := str(payload.get("system_id", ""))
			if _runtime_system != null and not explore_unit_id.is_empty() and not explore_system_id.is_empty():
				_runtime_system.request_explore_system_for_unit(explore_unit_id, explore_system_id)
		"split_member":
			var split_unit_id := str(payload.get("unit_id", ""))
			var new_fleet := SpaceManager.split_unit_to_new_fleet(split_unit_id)
			if new_fleet != null:
				selection_kind = "fleet"
				selection_id = new_fleet.fleet_id
				_state.selected_space_entity_kind = selection_kind
				_state.selected_space_entity_id = selection_id
				_state.selected_space_entity_title = new_fleet.display_name
				_state.selected_system_panel_id = ""
				_sync_galaxy_space_selection(selection_kind, selection_id)
		"remove_member":
			var removed_unit_id := str(payload.get("unit_id", ""))
			if SpaceManager.remove_unit_from_fleet(removed_unit_id):
				var removed_unit: SpaceUnitRuntime = SpaceManager.get_unit(removed_unit_id)
				if removed_unit != null:
					selection_kind = SpaceUnitClass.UNIT_KIND_SHIP
					selection_id = removed_unit.unit_id
					_state.selected_space_entity_kind = selection_kind
					_state.selected_space_entity_id = selection_id
					_state.selected_space_entity_title = removed_unit.display_name
					_state.selected_system_panel_id = ""
					_sync_galaxy_space_selection(selection_kind, selection_id)
		"reinforce_fleet":
			var reinforced := SpaceManager.debug_reinforce_fleet(
				str(payload.get("fleet_id", "")),
				str(payload.get("template_unit_id", ""))
			)
			if reinforced != null:
				selection_kind = "fleet"
				selection_id = str(payload.get("fleet_id", ""))
	_select_open_system_view_runtime_entity(selection_kind, selection_id)
	update_system_panel()
	update_selection_panel()
	update_info_label()


func _on_space_entity_panel_member_selected(selection_kind: String, record_id: String) -> void:
	var title := record_id
	var unit: SpaceUnitRuntime = SpaceManager.get_unit(record_id)
	if unit != null:
		title = unit.display_name
	select_space_entity(selection_kind, record_id, title)


func _select_open_system_view_runtime_entity(selection_kind: String, record_id: String) -> void:
	if _view_router == null:
		return
	var system_view := _view_router.get_system_view()
	if system_view == null or not system_view.is_open():
		return
	system_view.select_runtime_entity(selection_kind, record_id, false)


func _can_command_owner(owner_empire_id: String) -> bool:
	return _state == null or _state.active_empire_id.is_empty() or owner_empire_id == _state.active_empire_id


func _can_survey_system(system_id: String) -> bool:
	if _runtime_system == null or system_id.is_empty():
		return false
	var details := _runtime_system.get_system_details(system_id)
	if details.is_empty():
		return false
	return bool(details.get("can_survey", false)) and not bool(details.get("has_full_intel", false))


func _sync_selected_builder_to_system_view() -> void:
	if _view_router == null or _state == null:
		return
	var system_view := _view_router.get_system_view()
	if system_view == null:
		return
	var builder_unit_id := ""
	match _state.selected_space_entity_kind:
		SpaceUnitClass.UNIT_KIND_SHIP, SpaceUnitClass.UNIT_KIND_CREATURE, "unit":
			var unit: SpaceUnitRuntime = SpaceManager.get_unit(_state.selected_space_entity_id)
			if unit != null and unit.can_build_units():
				builder_unit_id = unit.unit_id
	system_view.set_selected_builder_unit_id(builder_unit_id)


func _get_empire_display_name(empire_id: String) -> String:
	if _state != null and _state.empires_by_id.has(empire_id):
		return str(_state.empires_by_id[empire_id].get("name", empire_id))
	return "Unclaimed" if empire_id.is_empty() else empire_id


func _get_system_display_name(system_id: String) -> String:
	if system_id.is_empty():
		return ""
	if _state != null and _state.systems_by_id.has(system_id):
		return str(_state.systems_by_id[system_id].get("name", system_id))
	return system_id


func _format_runtime_token(value: String) -> String:
	var trimmed_value: String = value.strip_edges()
	if trimmed_value.is_empty():
		return "Unassigned"
	return trimmed_value.replace("_", " ").capitalize()


func _format_string_list(values_variant: Variant, max_items: int) -> String:
	var values: PackedStringArray = PackedStringArray()
	if values_variant is PackedStringArray:
		values = values_variant
	elif values_variant is Array:
		for value_variant in values_variant:
			var value_text: String = str(value_variant).strip_edges()
			if value_text.is_empty():
				continue
			values.append(value_text)
	else:
		return ""

	if values.is_empty():
		return ""

	var display_values: Array[String] = []
	for value_index in range(mini(values.size(), max_items)):
		display_values.append(_format_runtime_token(values[value_index]))
	var result: String = ", ".join(display_values)
	if values.size() > max_items:
		result += " +%d more" % (values.size() - max_items)
	return result


func _format_decimal(value: float) -> String:
	var rounded_value: float = snappedf(value, 0.01)
	if is_equal_approx(rounded_value, round(rounded_value)):
		return str(int(round(rounded_value)))
	return str(rounded_value)


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
	if DisplayServer.get_name() == "headless":
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
	var modal_visible := is_colony_modal_visible() or is_ship_designer_visible() or is_research_modal_visible()
	var block_galaxy_camera: bool = _state.is_generating or _ui.loading_overlay.visible or _ui.empire_picker_overlay.visible or _ui.galaxy_hud.is_settings_visible() or _view_router.is_system_view_open() or modal_visible
	_view_router.set_galaxy_camera_input_blocked(block_galaxy_camera)
	var block_shared_ui: bool = _state.is_generating or _ui.loading_overlay.visible or _ui.empire_picker_overlay.visible or _ui.galaxy_hud.is_settings_visible() or modal_visible
	_ui.bottom_category_bar.set_interaction_enabled(not block_shared_ui)
	if _ui.empire_command_drawer != null:
		_ui.empire_command_drawer.call("set_interaction_enabled", not block_shared_ui)


func set_galaxy_presentation_visible(visible_state: bool) -> void:
	if _state == null or _ui == null:
		return
	var nodes: Dictionary = {
		"system_panel": _ui.system_panel,
		"info_label": _ui.info_label,
	}
	if _debug_info_panel != null:
		nodes["debug_info_panel"] = _debug_info_panel

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
	if not _runtime_system.can_open_system_view(system_id):
		update_system_panel()
		return
	_state.selected_system_id = system_id
	var system_details: Dictionary = _runtime_system.get_system_details(system_id)
	var neighbor_count: int = _state.galaxy_state.get_neighbor_system_ids(system_id).size()
	set_galaxy_presentation_visible(false)
	_view_router.show_system_view(system_details, neighbor_count)
	_sync_selected_builder_to_system_view()
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


func refresh_empire_command_drawer() -> void:
	if _ui == null or _runtime_system == null or _ui.empire_command_drawer == null:
		return
	_ui.empire_command_drawer.call("set_anomaly_entries", _runtime_system.build_empire_anomaly_entries())
	_ui.empire_command_drawer.call("set_research_summary", _build_research_drawer_summary())


func _build_research_drawer_summary() -> String:
	if _state == null or _state.active_empire_id.is_empty() or ResearchManager == null or not ResearchManager.is_bootstrapped():
		return ""
	var lines: Array[String] = []
	for overview in ResearchManager.get_domains_overview(_state.active_empire_id):
		var domain_name := str(overview.get("display_name", overview.get("domain_id", "")))
		var active_projects: Array = overview.get("active_projects", [])
		if active_projects.is_empty():
			lines.append("%s: Slot frei" % domain_name)
			continue
		var project_parts: Array[String] = []
		for project_variant in active_projects:
			if project_variant is not Dictionary:
				continue
			var project: Dictionary = project_variant
			var total := maxi(int(project.get("total_cost_milliunits", 1)), 1)
			var percent := clampi(int(float(project.get("invested_milliunits", 0)) * 100.0 / float(total)), 0, 100)
			project_parts.append("%s %d%%" % [str(project.get("display_name", project.get("tech_id", ""))), percent])
		lines.append("%s: %s" % [domain_name, ", ".join(project_parts)])
	return "\n".join(lines)


func is_colony_modal_visible() -> bool:
	return _colony_modal != null and _colony_modal.visible


func is_ship_designer_visible() -> bool:
	return _ship_designer_modal != null and _ship_designer_modal.visible


func open_ship_designer_modal() -> void:
	if _state == null or _ui == null or _ui.canvas_layer == null:
		return
	var empire_id := _state.active_empire_id.strip_edges()
	if empire_id.is_empty():
		return
	if _ship_designer_modal == null:
		_ship_designer_modal = SHIP_DESIGNER_MODAL_SCRIPT.new() as Control
		_ui.canvas_layer.add_child(_ship_designer_modal)
		_ship_designer_modal.close_requested.connect(_on_ship_designer_close_requested)
	_ship_designer_modal.open(empire_id)
	refresh_camera_input_block()


func close_ship_designer_modal() -> void:
	if _ship_designer_modal == null or not _ship_designer_modal.visible:
		return
	_ship_designer_modal.close()


func _on_ship_designer_close_requested() -> void:
	refresh_camera_input_block()
	update_system_panel()
	update_selection_panel()


func is_research_modal_visible() -> bool:
	return _research_modal != null and _research_modal.visible


func open_research_modal() -> void:
	if _state == null or _ui == null or _ui.canvas_layer == null:
		return
	var empire_id := _state.active_empire_id.strip_edges()
	if empire_id.is_empty():
		return
	if _research_modal == null:
		_research_modal = RESEARCH_MODAL_SCRIPT.new() as Control
		_ui.canvas_layer.add_child(_research_modal)
		_research_modal.close_requested.connect(_on_research_modal_close_requested)
	_research_modal.open(empire_id)
	refresh_camera_input_block()


func close_research_modal() -> void:
	if _research_modal == null or not _research_modal.visible:
		return
	_research_modal.close()


func _on_research_modal_close_requested() -> void:
	refresh_camera_input_block()
	refresh_empire_command_drawer()
	update_system_panel()
	update_selection_panel()


func post_notification(data: Dictionary) -> String:
	_ensure_notification_center()
	if _notification_center == null:
		return ""
	return _notification_center.post_notification(data)


func _ensure_notification_center() -> void:
	if _notification_center != null or _ui == null or _ui.canvas_layer == null:
		return
	_notification_center = NOTIFICATION_CENTER_SCRIPT.new() as Control
	_notification_center.name = "NotificationCenter"
	_ui.canvas_layer.add_child(_notification_center)
	_notification_center.notification_activated.connect(_on_notification_activated)


func _on_notification_activated(_notification_id: String, action: Dictionary) -> void:
	match str(action.get("type", "")):
		"open_system":
			var system_id := str(action.get("system_id", ""))
			if not system_id.is_empty():
				close_colony_modal()
				close_ship_designer_modal()
				open_system_view(system_id)
		"select_space_entity":
			var selection_kind := str(action.get("selection_kind", ""))
			var selection_id := str(action.get("selection_id", ""))
			var system_id := str(action.get("system_id", ""))
			if selection_kind.is_empty() or selection_id.is_empty():
				return
			close_colony_modal()
			close_ship_designer_modal()
			if not system_id.is_empty():
				open_system_view(system_id)
			_state.selected_space_entity_kind = selection_kind
			_state.selected_space_entity_id = selection_id
			_state.selected_system_panel_id = ""
			_sync_galaxy_space_selection(selection_kind, selection_id)
			_select_open_system_view_runtime_entity(selection_kind, selection_id)
			update_selection_panel()
			update_info_label()


func close_colony_modal() -> void:
	if _colony_modal == null or not _colony_modal.visible:
		return
	_colony_modal.close()


func open_colony_modal(colony_id: String) -> void:
	if _runtime_system == null or colony_id.is_empty():
		return
	_ensure_colony_controls()
	var colony_details := _runtime_system.get_colony_details(colony_id)
	if colony_details.is_empty():
		return
	_open_colony_id = colony_id
	_colony_modal.open_details(colony_details)
	refresh_camera_input_block()


func get_selected_empire_id_from_picker() -> String:
	if _ui == null or _ui.empire_picker_list.get_selected_items().is_empty():
		return ""
	var selected_index: int = _ui.empire_picker_list.get_selected_items()[0]
	return str(_ui.empire_picker_list.get_item_metadata(selected_index))


func format_controller_kind(controller_kind: String) -> String:
	match controller_kind:
		"player_local", "local_player":
			return "Player"
		"player_remote", "remote_player":
			return "Remote Player"
		"ai":
			return "AI"
		_:
			return "Unassigned"


func update_debug_reveal_button() -> void:
	if _state == null or _ui == null or _ui.debug_reveal_toggle_button == null:
		return
	_ui.debug_reveal_toggle_button.text = "Hide Galaxy" if _state.debug_reveal_galaxy else "Reveal Galaxy"


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
	if not _runtime_system.can_open_system_view(inspected_system_id):
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
	if not _runtime_system.can_open_system_view(inspected_system_id):
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


func _ensure_colony_controls() -> void:
	if _ui == null:
		return

	if _manage_colony_button == null and _ui.claim_system_button != null:
		_manage_colony_button = Button.new()
		_manage_colony_button.text = "Manage Colony"
		_manage_colony_button.visible = false
		_manage_colony_button.disabled = true
		_manage_colony_button.pressed.connect(_on_manage_colony_pressed)
		var panel_box := _ui.claim_system_button.get_parent() as VBoxContainer
		if panel_box != null:
			panel_box.add_child(_manage_colony_button)
			panel_box.move_child(_manage_colony_button, _ui.claim_system_button.get_index())

	if _colony_modal == null and _ui.canvas_layer != null:
		_colony_modal = COLONY_MODAL_SCRIPT.new() as Control
		_ui.canvas_layer.add_child(_colony_modal)
		_colony_modal.close_requested.connect(_on_colony_modal_close_requested)
		_colony_modal.assign_requested.connect(_on_colony_modal_assign_requested)
		_colony_modal.unassign_requested.connect(_on_colony_modal_unassign_requested)
		_colony_modal.job_cap_changed.connect(_on_colony_modal_job_cap_changed)
		_colony_modal.building_place_requested.connect(_on_colony_modal_building_place_requested)


func _set_manage_colony_button_state(colony_id: String, enabled: bool) -> void:
	_manage_colony_id = colony_id.strip_edges()
	if _manage_colony_button == null:
		return
	_manage_colony_button.visible = enabled
	_manage_colony_button.disabled = not enabled
	if enabled:
		var details := _runtime_system.get_colony_details(_manage_colony_id) if _runtime_system != null else {}
		var colony_name := str(details.get("name", "Colony"))
		_manage_colony_button.text = "Manage %s" % colony_name
	else:
		_manage_colony_button.text = "Manage Colony"


func _on_manage_colony_pressed() -> void:
	if _manage_colony_id.is_empty():
		return
	open_colony_modal(_manage_colony_id)


func _on_colony_modal_close_requested() -> void:
	_open_colony_id = ""
	refresh_camera_input_block()


func _on_colony_modal_assign_requested(colony_id: String, pop_unit_id: String, job_id: String) -> void:
	if _runtime_system == null:
		return
	if _runtime_system.assign_colony_pop_to_job(colony_id, pop_unit_id, job_id):
		_refresh_open_colony_modal()


func _on_colony_modal_unassign_requested(colony_id: String, pop_unit_id: String) -> void:
	if _runtime_system == null:
		return
	if _runtime_system.unassign_colony_pop_from_job(colony_id, pop_unit_id):
		_refresh_open_colony_modal()


func _on_colony_modal_job_cap_changed(colony_id: String, job_id: String, cap: int) -> void:
	if _runtime_system == null:
		return
	if _runtime_system.set_colony_job_cap(colony_id, job_id, cap):
		_refresh_open_colony_modal()


func _on_colony_modal_building_place_requested(colony_id: String, slot_id: String, building_id: String) -> void:
	if _runtime_system == null:
		return
	_runtime_system.place_colony_building(colony_id, slot_id, building_id)
	_refresh_open_colony_modal()


func _on_colony_updated(colony_id: String) -> void:
	if colony_id == _open_colony_id:
		_refresh_open_colony_modal()
	update_system_panel()


func _refresh_open_colony_modal() -> void:
	if _colony_modal == null or _open_colony_id.is_empty() or _runtime_system == null:
		return
	var details := _runtime_system.get_colony_details(_open_colony_id)
	if details.is_empty():
		close_colony_modal()
		return
	_colony_modal.open_details(details)
