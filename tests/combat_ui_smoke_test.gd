extends Node

const PANEL_SCRIPT: Script = preload("res://scene/game/SpaceEntityDetailsPanel.gd")
const EFFECTS_RENDERER_SCRIPT: Script = preload("res://scene/StarSystem/SystemCombatEffectsRenderer.gd")

const EMPIRE_ID := "empire_combat_ui"
const SYSTEM_ID := "sys_combat_ui"


class EffectsHostStub:
	extends Node3D

	var effects_root: Node3D = null

	func _ready() -> void:
		effects_root = Node3D.new()
		effects_root.name = "RuntimeEffects"
		add_child(effects_root)

	func get_runtime_effects_root() -> Node3D:
		return effects_root


func _ready() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("Combat UI smoke test passed.")
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

	await _run_panel_checks(failures)
	await _run_effects_renderer_checks(failures)

	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)


func _run_panel_checks(failures: Array[String]) -> void:
	SpaceManager.unlock_ship_component(EMPIRE_ID, "shockwave_emitter")
	var design_id := SpaceManager.create_ship_design(EMPIRE_ID, SpaceManager.CORVETTE_CLASS_ID, {
		"weapon_1": "basic_laser",
		"defense_1": "basic_shield_emitter",
		"utility_1": "shockwave_emitter",
		"drive": "basic_drive",
	}, {"display_name": "UI Test Corvette"})
	_expect(not design_id.is_empty(), "panel test design should validate: %s" % ", ".join(SpaceManager.get_last_ship_design_errors()), failures)

	var corvette := SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {
		"unit_id": "ui_corvette",
		"design_id": design_id,
		"display_name": "UI Corvette",
	})
	_expect(corvette != null, "panel test corvette should spawn", failures)
	if corvette == null:
		return

	var panel := PANEL_SCRIPT.new() as SpaceEntityDetailsPanel
	add_child(panel)
	await get_tree().process_frame

	var context := {
		"active_empire_id": EMPIRE_ID,
		"can_command": true,
		"owner_names": {EMPIRE_ID: "Combat UI Empire"},
		"system_names": {SYSTEM_ID: "Combat UI System"},
	}
	panel.open_ship(corvette.unit_id, context)
	await get_tree().process_frame

	var stance_button := panel.find_child("StanceButton", true, false) as Button
	_expect(stance_button != null, "combat unit should expose a stance toggle", failures)
	if stance_button != null:
		_expect(stance_button.text.contains("Aggressiv"), "combat unit should default to aggressive stance label, got '%s'" % stance_button.text, failures)
		_expect(not stance_button.disabled, "stance toggle should be enabled for commandable units", failures)

	var ability_button := panel.find_child("AbilityButton_utility_1", true, false) as Button
	_expect(ability_button != null, "manual ability should expose a button", failures)
	if ability_button != null:
		_expect(not ability_button.disabled, "ability button should be enabled while off cooldown", failures)

	var received_actions: Array[Dictionary] = []
	panel.action_requested.connect(func(action_id: String, payload: Dictionary) -> void:
		received_actions.append({"action_id": action_id, "payload": payload})
	)
	if stance_button != null:
		stance_button.pressed.emit()
	if ability_button != null:
		ability_button.pressed.emit()
	_expect(received_actions.size() == 2, "buttons should emit actions, got %d" % received_actions.size(), failures)
	if received_actions.size() == 2:
		_expect(str(received_actions[0].get("action_id", "")) == "set_unit_stance", "stance button should request stance change", failures)
		_expect(str(received_actions[0].get("payload", {}).get("stance", "")) == SpaceUnitRuntime.STANCE_PASSIVE, "aggressive unit should toggle to passive", failures)
		_expect(str(received_actions[1].get("action_id", "")) == "trigger_unit_ability", "ability button should request ability trigger", failures)
		_expect(str(received_actions[1].get("payload", {}).get("slot_id", "")) == "utility_1", "ability action should carry the slot id", failures)

	# Queued ability + stance change reflect in a refreshed panel.
	SpaceManager.set_unit_stance(corvette.unit_id, SpaceUnitRuntime.STANCE_PASSIVE)
	SpaceManager.queue_unit_ability_command(corvette.unit_id, "utility_1")
	panel.refresh()
	await get_tree().process_frame
	stance_button = panel.find_child("StanceButton", true, false) as Button
	ability_button = panel.find_child("AbilityButton_utility_1", true, false) as Button
	_expect(stance_button != null and stance_button.text.contains("Passiv"), "stance label should reflect the passive stance after refresh", failures)
	_expect(ability_button != null and ability_button.disabled, "pending ability command should disable the ability button", failures)

	panel.queue_free()
	await get_tree().process_frame


func _run_effects_renderer_checks(failures: Array[String]) -> void:
	var host := EffectsHostStub.new()
	add_child(host)
	await get_tree().process_frame

	var renderer := EFFECTS_RENDERER_SCRIPT.new() as SystemCombatEffectsRenderer
	renderer.bind(host)

	var events: Array[Dictionary] = [
		{
			"type": "shot",
			"system_id": SYSTEM_ID,
			"hit": true,
			"hull_damage": 8,
			"attacker_position": {"x": 0.0, "y": 0.0, "z": 0.0},
			"target_position": {"x": 6.0, "y": 0.0, "z": 2.0},
		},
		{
			"type": "kill",
			"system_id": SYSTEM_ID,
			"position": {"x": 6.0, "y": 0.0, "z": 2.0},
		},
		{
			"type": "ability",
			"system_id": SYSTEM_ID,
			"effect_id": "shockwave",
			"radius": 10.0,
			"position": {"x": 1.0, "y": 0.0, "z": 1.0},
		},
		{
			"type": "shot",
			"system_id": "sys_other",
			"hit": true,
			"attacker_position": {"x": 0.0, "y": 0.0, "z": 0.0},
			"target_position": {"x": 3.0, "y": 0.0, "z": 0.0},
		},
	]
	renderer.play_events(events, SYSTEM_ID)
	var effect_count := host.get_runtime_effects_root().get_child_count()
	_expect(effect_count == 3, "renderer should spawn one effect per matching event, got %d" % effect_count, failures)

	renderer.play_events([{"type": "battle_started", "system_id": SYSTEM_ID}], SYSTEM_ID)
	_expect(host.get_runtime_effects_root().get_child_count() == 3, "non-visual events should not spawn effects", failures)

	renderer.unbind()
	host.queue_free()
	await get_tree().process_frame


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
