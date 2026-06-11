extends Node

const DESIGNER_MODAL_SCRIPT: Script = preload("res://scene/game/ShipDesignerModal.gd")
const PANEL_SCRIPT: Script = preload("res://scene/game/SpaceEntityDetailsPanel.gd")

const EMPIRE_ID := "empire_designer"
const SYSTEM_ID := "sys_designer"


func _ready() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("Ship designer smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()
	SpaceManager.reset_runtime_state(true)
	EconomyManager.bootstrap(PackedStringArray([EMPIRE_ID]), {"generated_seed": 7, "systems": []})
	SpaceManager.bootstrap_empires(PackedStringArray([EMPIRE_ID]))

	await _run_designer_modal_checks(failures)
	await _run_shipyard_panel_checks(failures)

	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)


func _run_designer_modal_checks(failures: Array[String]) -> void:
	var modal := DESIGNER_MODAL_SCRIPT.new() as ShipDesignerModal
	add_child(modal)
	await get_tree().process_frame

	modal.open(EMPIRE_ID)
	await get_tree().process_frame
	_expect(modal.visible, "designer modal should open", failures)

	var hull_list := modal.find_child("HullList", true, false) as ItemList
	_expect(hull_list != null and hull_list.item_count >= 6, "designer should list all hulls with design slots, got %d" % (hull_list.item_count if hull_list != null else -1), failures)

	modal.call("_select_hull", SpaceManager.CORVETTE_CLASS_ID)
	await get_tree().process_frame
	var default_design_id := SpaceManager.get_default_ship_design_id(EMPIRE_ID, SpaceManager.CORVETTE_CLASS_ID)
	_expect(modal.get_selected_design_id() == default_design_id, "selecting a hull should load its default design", failures)

	# Component palette filters locked components.
	var utility_select := modal.find_child("SlotSelect_utility_1", true, false) as OptionButton
	_expect(utility_select != null, "utility slot should expose a component dropdown", failures)
	if utility_select != null:
		_expect(not _option_button_has_metadata(utility_select, "shockwave_emitter"), "locked shockwave emitter should not appear in the palette", failures)
	SpaceManager.unlock_ship_component(EMPIRE_ID, "shockwave_emitter")
	modal.call("_select_hull", SpaceManager.CORVETTE_CLASS_ID)
	await get_tree().process_frame
	utility_select = modal.find_child("SlotSelect_utility_1", true, false) as OptionButton
	_expect(utility_select != null and _option_button_has_metadata(utility_select, "shockwave_emitter"), "unlocked shockwave emitter should appear in the palette", failures)

	# Dropdown selection updates the draft and the live preview.
	var weapon_select := modal.find_child("SlotSelect_weapon_2", true, false) as OptionButton
	_expect(weapon_select != null, "weapon slot should expose a component dropdown", failures)
	if weapon_select != null:
		var laser_index := _option_button_index_for_metadata(weapon_select, "basic_laser")
		_expect(laser_index > 0, "weapon palette should offer the basic laser", failures)
		if laser_index > 0:
			weapon_select.select(laser_index)
			weapon_select.item_selected.emit(laser_index)
			await get_tree().process_frame

	# Create a new design via the modal's save flow.
	modal.call("_load_design", "")
	await get_tree().process_frame
	modal.set("_draft_assignments", {
		"weapon_1": "basic_laser",
		"defense_1": "basic_armor_plating",
		"utility_1": "shockwave_emitter",
		"drive": "basic_drive",
	})
	var name_edit := modal.find_child("DesignNameEdit", true, false) as LineEdit
	if name_edit != null:
		name_edit.text = "Sturm Korvette"
	modal.call("_refresh_preview")
	await get_tree().process_frame
	var save_button := modal.find_child("SaveDesignButton", true, false) as Button
	_expect(save_button != null and not save_button.disabled, "valid draft should enable saving", failures)
	modal.call("_on_save_pressed")
	await get_tree().process_frame

	var new_design_id := modal.get_selected_design_id()
	_expect(not new_design_id.is_empty() and new_design_id != default_design_id, "saving should create a new design", failures)
	var saved_design: Dictionary = SpaceManager.get_ship_design(new_design_id)
	_expect(str(saved_design.get("display_name", "")) == "Sturm Korvette", "saved design should keep its name", failures)
	_expect(str(saved_design.get("slot_assignments", {}).get("utility_1", "")) == "shockwave_emitter", "saved design should keep slot assignments", failures)

	# Invalid draft (missing required drive) blocks saving.
	modal.call("_load_design", "")
	modal.set("_draft_assignments", {"weapon_1": "basic_laser"})
	modal.call("_refresh_preview")
	await get_tree().process_frame
	save_button = modal.find_child("SaveDesignButton", true, false) as Button
	_expect(save_button != null and save_button.disabled, "draft without required drive should block saving", failures)
	var errors_label := modal.find_child("ErrorsLabel", true, false) as Label
	_expect(errors_label != null and errors_label.text.contains("Pflichtslot"), "missing required slot should surface a translated error", failures)

	# Default switching and deletion.
	_expect(SpaceManager.set_default_ship_design(new_design_id), "new design should become the default", failures)
	_expect(SpaceManager.get_default_ship_design_id(EMPIRE_ID, SpaceManager.CORVETTE_CLASS_ID) == new_design_id, "default mapping should point at the new design", failures)
	_expect(SpaceManager.remove_ship_design(new_design_id) == false, "default design should not be removable", failures)
	_expect(SpaceManager.remove_ship_design(default_design_id), "old non-default design should be removable", failures)
	_expect(SpaceManager.get_ship_design(default_design_id).is_empty(), "removed design should be gone", failures)

	modal.close()
	await get_tree().process_frame
	_expect(not modal.visible, "designer modal should close", failures)
	modal.queue_free()
	await get_tree().process_frame


func _run_shipyard_panel_checks(failures: Array[String]) -> void:
	# The surviving design mounts a shockwave emitter, which costs exotic gases
	# (starting stockpile is zero) — grant some so the build is affordable.
	EconomyManager.grant_resources(EMPIRE_ID, [{"resource_id": "exotic_gases", "milliunits": 50000}])
	var station := SpaceManager.spawn_unit(SpaceManager.BASIC_STATION_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {
		"unit_id": "designer_station",
		"local_position": Vector3.ZERO,
	})
	_expect(station != null, "shipyard station should spawn", failures)
	if station == null:
		return

	var options := SpaceManager.get_ship_build_options(station.unit_id)
	_expect(options.size() == 1, "shipyard should offer one option per corvette design, got %d" % options.size(), failures)
	if not options.is_empty():
		_expect(bool(options[0].get("is_default_design", false)), "remaining design should be flagged as default", failures)

	var panel := PANEL_SCRIPT.new() as SpaceEntityDetailsPanel
	add_child(panel)
	await get_tree().process_frame
	var context := {
		"active_empire_id": EMPIRE_ID,
		"can_command": true,
		"owner_names": {EMPIRE_ID: "Designer Empire"},
		"system_names": {SYSTEM_ID: "Designer System"},
	}
	panel.open_ship(station.unit_id, context)
	await get_tree().process_frame

	_expect(panel.find_child("BuildTargetButton", true, false) == null, "stationary shipyard should not expose the body-builder action", failures)
	var build_buttons: Array[Button] = []
	for child in _find_actions_box_children(panel):
		if child is Button and str(child.name).begins_with("BuildShipButton_"):
			build_buttons.append(child)
	_expect(build_buttons.size() == 1, "shipyard panel should expose one build button per design, got %d" % build_buttons.size(), failures)

	var received_actions: Array[Dictionary] = []
	panel.action_requested.connect(func(action_id: String, payload: Dictionary) -> void:
		received_actions.append({"action_id": action_id, "payload": payload})
	)
	if not build_buttons.is_empty():
		_expect(not build_buttons[0].disabled, "affordable build option should be enabled", failures)
		build_buttons[0].pressed.emit()
	_expect(received_actions.size() == 1 and str(received_actions[0].get("action_id", "")) == "build_ship", "build button should request ship construction", failures)
	if received_actions.size() == 1:
		var payload: Dictionary = received_actions[0].get("payload", {})
		var project_id := SpaceManager.request_build_ship(
			str(payload.get("unit_id", "")),
			str(payload.get("class_id", "")),
			{"design_id": str(payload.get("design_id", ""))}
		)
		_expect(not project_id.is_empty(), "requested ship build should start a construction project", failures)

	panel.refresh()
	await get_tree().process_frame
	_expect(panel.find_child("ShipyardBusyButton", true, false) != null, "busy shipyard should show the active project state", failures)

	panel.queue_free()
	await get_tree().process_frame


func _find_actions_box_children(panel: Control) -> Array:
	var actions_box := panel.find_child("ActionsBox", true, false) as VBoxContainer
	if actions_box == null:
		return []
	return actions_box.get_children()


func _option_button_has_metadata(select: OptionButton, metadata_value: String) -> bool:
	return _option_button_index_for_metadata(select, metadata_value) >= 0


func _option_button_index_for_metadata(select: OptionButton, metadata_value: String) -> int:
	for index in range(select.item_count):
		if str(select.get_item_metadata(index)) == metadata_value:
			return index
	return -1


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
