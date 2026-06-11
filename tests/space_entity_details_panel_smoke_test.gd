extends Node

const PANEL_SCRIPT: Script = preload("res://scene/game/SpaceEntityDetailsPanel.gd")
const UI_CONTROLLER_SCRIPT: Script = preload("res://scene/game/GameSceneUiController.gd")
const VIEW_SYSTEM_SCRIPT: Script = preload("res://scene/game/systems/GameSceneViewSystem.gd")
const SYSTEM_VIEW_SCRIPT: Script = preload("res://scene/StarSystem/SystemView.gd")
const SYSTEM_VIEW_SCENE: PackedScene = preload("res://scene/StarSystem/SystemView.tscn")

class LockedActionEmitter:
	extends Button
	signal clearing_requested


func _ready() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("Space entity details panel smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	SpaceManager.reset_runtime_state(true)

	var science_ship := SpaceManager.spawn_unit(SpaceManager.SCIENCE_SHIP_CLASS_ID, "empire_test", "sys_alpha", {
		"unit_id": "science_panel",
		"display_name": "ISS Panel Science",
	})
	var builder_ship := SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, "empire_test", "sys_alpha", {
		"unit_id": "builder_panel",
		"display_name": "ISS Panel Builder",
	})
	var scout_ship := SpaceManager.spawn_unit(SpaceManager.SCIENCE_SHIP_CLASS_ID, "empire_test", "sys_alpha", {
		"unit_id": "scout_panel",
		"display_name": "ISS Panel Scout",
	})
	_expect(science_ship != null and builder_ship != null and scout_ship != null, "test ships should spawn", failures)
	if science_ship == null or builder_ship == null or scout_ship == null:
		return

	var panel := PANEL_SCRIPT.new() as SpaceEntityDetailsPanel
	add_child(panel)
	await get_tree().process_frame

	var context := {
		"active_empire_id": "empire_test",
		"owner_empire_id": "empire_test",
		"owner_name": "Test Empire",
		"system_id": "sys_alpha",
		"system_name": "Alpha",
		"can_command": true,
		"can_survey_system": true,
		"owner_names": {"empire_test": "Test Empire"},
		"system_names": {"sys_alpha": "Alpha"},
	}

	panel.open_ship(science_ship.unit_id, context)
	await get_tree().process_frame
	_expect(panel.visible, "ship panel should be visible after opening a ship", failures)
	_expect(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "panel root should not block map input", failures)
	var card := panel.find_child("EntityDetailsCard", true, false) as PanelContainer
	_expect(card != null and card.mouse_filter == Control.MOUSE_FILTER_STOP, "panel card should catch only its own mouse input", failures)
	_expect(_label_text(panel, "TitleLabel") == "ISS Panel Science", "ship panel should show the ship title", failures)
	_expect(panel.find_child("ExploreSystemButton", true, false) != null, "science ship should expose exploration action", failures)
	_expect(panel.find_child("BuildTargetButton", true, false) == null, "science ship should not expose builder action", failures)

	panel.open_ship(builder_ship.unit_id, context)
	await get_tree().process_frame
	_expect(_label_text(panel, "TitleLabel") == "ISS Panel Builder", "builder panel should refresh title", failures)
	_expect(panel.find_child("BuildTargetButton", true, false) != null, "builder ship should expose build target action", failures)
	_expect(panel.find_child("ExploreSystemButton", true, false) == null, "builder ship should not expose science action", failures)
	var action_refresh_state := {"count": 0}
	var actions_box := panel.find_child("ActionsBox", true, false) as VBoxContainer
	_expect(actions_box != null, "ship panel should expose actions box", failures)
	if actions_box != null:
		var locked_emitter := LockedActionEmitter.new()
		locked_emitter.name = "LockedActionEmitter"
		actions_box.add_child(locked_emitter)
		locked_emitter.clearing_requested.connect(func() -> void:
			action_refresh_state["count"] = int(action_refresh_state.get("count", 0)) + 1
			panel.open_ship(builder_ship.unit_id, context)
		)
		locked_emitter.emit_signal("clearing_requested")
		await get_tree().process_frame
		_expect(int(action_refresh_state.get("count", 0)) == 1, "panel should refresh safely while an action button signal is still emitting (count %d)" % int(action_refresh_state.get("count", 0)), failures)
		# Builder ship actions: stance toggle + evasion toggle + build target.
		_expect(actions_box != null and actions_box.get_child_count() == 3, "panel action refresh should replace old action buttons immediately (count %d)" % (actions_box.get_child_count() if actions_box != null else -1), failures)

	var fleet := SpaceManager.create_fleet("empire_test", "sys_alpha", [science_ship.unit_id, builder_ship.unit_id], {
		"display_name": "Panel Fleet",
	})
	_expect(fleet != null and fleet.unit_ids.size() == 2, "test fleet should contain two ships", failures)
	if fleet != null:
		panel.open_fleet(fleet.fleet_id, context)
		await get_tree().process_frame
		_expect(_label_text(panel, "TitleLabel") == "Panel Fleet", "fleet panel should show fleet title", failures)
		var members_box := panel.find_child("FleetMembersVBox", true, false) as VBoxContainer
		_expect(members_box != null and members_box.visible and members_box.get_child_count() == 2, "fleet panel should list all members", failures)
		_expect(panel.find_child("ReinforceFleetButton", true, false) != null, "fleet panel should expose reinforce action", failures)
		_expect(panel.find_child("SplitButton", true, false) != null, "fleet panel should expose split action", failures)
		_expect(panel.find_child("RemoveMemberButton", true, false) != null, "fleet panel should expose remove action", failures)
		await _assert_system_view_runtime_selection_is_not_echoed(fleet.fleet_id, failures)

	var single_fleet := SpaceManager.create_fleet("empire_test", "sys_alpha", [scout_ship.unit_id], {
		"display_name": "Single Scout Fleet",
	})
	_expect(single_fleet != null, "single ship fleet should be created", failures)
	if single_fleet != null:
		panel.open_fleet(single_fleet.fleet_id, context)
		await get_tree().process_frame
		_expect(_label_text(panel, "TitleLabel") == "ISS Panel Scout", "single-member fleet should resolve to ship panel", failures)
		var single_members_box := panel.find_child("FleetMembersVBox", true, false) as VBoxContainer
		_expect(single_members_box != null and not single_members_box.visible, "single-member fleet should hide member list", failures)

	panel.close()
	await get_tree().process_frame
	_expect(not panel.visible, "panel close should hide the panel", failures)
	panel.free()

	var system_view := SYSTEM_VIEW_SCRIPT.new() as SystemView
	add_child(system_view)
	var runtime_selection_events: Array[Dictionary] = []
	system_view.runtime_entity_selected.connect(func(selection_data: Dictionary) -> void:
		runtime_selection_events.append(selection_data.duplicate(true))
	)
	var runtime_selection := {
		"selection_kind": "fleet",
		"selection_id": "fleet:panel_fleet",
		"context": {"system_id": "sys_alpha"},
	}
	system_view.set("_suppress_runtime_entity_selection_signal", true)
	system_view.call("_handle_preview_selection_changed", {})
	_expect(runtime_selection_events.is_empty(), "system view refresh should not echo empty selection signals", failures)
	system_view.call("_handle_preview_selection_changed", runtime_selection)
	_expect(runtime_selection_events.is_empty(), "system view refresh should not echo runtime selection signals", failures)
	system_view.set("_suppress_runtime_entity_selection_signal", false)
	system_view.call("_handle_preview_selection_changed", {})
	_expect(runtime_selection_events.size() == 1 and runtime_selection_events[0].is_empty(), "system view should still emit user-driven empty selections", failures)
	runtime_selection_events.clear()
	system_view.call("_handle_preview_selection_changed", runtime_selection)
	_expect(
		runtime_selection_events.size() == 1 and str(runtime_selection_events[0].get("record_id", "")) == "panel_fleet",
		"system view should still emit user-driven runtime selections",
		failures
	)
	system_view.free()
	SpaceManager.reset_runtime_state(true)


func _assert_system_view_runtime_selection_is_not_echoed(fleet_id: String, failures: Array[String]) -> void:
	var system_view := SYSTEM_VIEW_SCENE.instantiate() as SystemView
	add_child(system_view)
	await get_tree().process_frame

	var runtime_selection_events: Array[Dictionary] = []
	system_view.runtime_entity_selected.connect(func(selection_data: Dictionary) -> void:
		runtime_selection_events.append(selection_data.duplicate(true))
	)

	var system_details := {
		"id": "sys_alpha",
		"name": "Alpha",
		"generated_seed": 9,
		"has_full_intel": true,
		"owner_empire_id": "empire_test",
		"owner_name": "Test Empire",
		"active_empire_id": "empire_test",
		"stars": [],
		"orbitals": [],
		"system_summary": {},
		"star_profile": {},
		"space_renderables": SpaceManager.build_system_renderables("sys_alpha"),
	}
	system_view.show_system(system_details, 0)
	await get_tree().process_frame
	runtime_selection_events.clear()

	var selected_without_notify := system_view.select_runtime_entity("fleet", fleet_id, false)
	await get_tree().process_frame
	_expect(selected_without_notify, "programmatic system-view runtime selection should find the fleet", failures)
	_expect(runtime_selection_events.is_empty(), "programmatic system-view runtime selection should not emit a selection echo", failures)

	system_details["space_renderables"] = SpaceManager.build_system_renderables("sys_alpha")
	system_view.refresh_runtime(system_details, 0)
	await get_tree().process_frame
	_expect(runtime_selection_events.is_empty(), "system-view runtime refresh should not emit a selection echo", failures)

	var selected_with_notify := system_view.select_runtime_entity("fleet", fleet_id, true)
	await get_tree().process_frame
	_expect(selected_with_notify, "user-driven system-view runtime selection should find the fleet", failures)
	_expect(runtime_selection_events.size() == 1, "user-driven system-view runtime selection should emit once", failures)
	system_view.free()


func _label_text(root: Node, label_name: String) -> String:
	var label := root.find_child(label_name, true, false) as Label
	if label == null:
		return ""
	return label.text


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
