extends Node

const NOTIFICATION_CENTER_SCRIPT: Script = preload("res://scene/UI/NotificationCenter.gd")
const BATTLE_OVERVIEW_SCRIPT: Script = preload("res://scene/UI/BattleOverviewPanel.gd")
const PANEL_SCRIPT: Script = preload("res://scene/game/SpaceEntityDetailsPanel.gd")

const EMPIRE_A := "empire_notify_a"
const EMPIRE_B := "empire_notify_b"
const SYSTEM_ID := "sys_notify"


func _ready() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("Notification center smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	await _run_notification_center_checks(failures)
	await _run_battle_overview_checks(failures)


func _run_notification_center_checks(failures: Array[String]) -> void:
	var center := NOTIFICATION_CENTER_SCRIPT.new() as NotificationCenter
	add_child(center)
	await get_tree().process_frame

	# Invalid data is rejected.
	_expect(center.post_notification({}).is_empty(), "empty notification data should be rejected", failures)
	_expect(center.post_notification({"message": "no title"}).is_empty(), "notification without title should be rejected", failures)

	# All four importance levels post; level is clamped and queryable.
	var ids: Array[String] = []
	for importance in range(1, 5):
		var notification_id := center.post_notification({
			"title": "Stufe %d" % importance,
			"message": "Testnachricht",
			"importance": importance,
		})
		_expect(not notification_id.is_empty(), "level %d notification should post" % importance, failures)
		ids.append(notification_id)
	_expect(center.get_notification_count() == 4, "all four levels should be stacked, got %d" % center.get_notification_count(), failures)
	_expect(center.get_notification_importance(ids[3]) == 4, "importance should round-trip", failures)

	# Manual dismissal works and emits the signal.
	var dismissed_ids: Array[String] = []
	center.notification_dismissed.connect(func(notification_id: String) -> void:
		dismissed_ids.append(notification_id)
	)
	_expect(center.dismiss_notification(ids[0]), "dismissing an existing notification should succeed", failures)
	_expect(not center.dismiss_notification(ids[0]), "double dismissal should fail", failures)
	_expect(dismissed_ids == [ids[0]], "dismissal should emit the notification id", failures)
	_expect(center.get_notification_count() == 3, "dismissed notification should leave the stack", failures)

	# Auto-expiry: short lifetimes for low levels, level 4 persists.
	center.clear_notifications()
	center.set_importance_lifetimes({1: 0.15, 2: 0.15, 3: 0.15, 4: 0.0})
	var expiring_id := center.post_notification({"title": "Fluechtig", "importance": 1})
	var persistent_id := center.post_notification({"title": "Kritisch", "importance": 4})
	await get_tree().create_timer(0.5).timeout
	_expect(not center.has_notification(expiring_id), "low-importance notification should auto-expire", failures)
	_expect(center.has_notification(persistent_id), "level 4 notification should persist until dismissed", failures)

	# Click activation emits the action payload and removes the card.
	var activations: Array[Dictionary] = []
	center.notification_activated.connect(func(notification_id: String, action: Dictionary) -> void:
		activations.append({"id": notification_id, "action": action})
	)
	var actionable_id := center.post_notification({
		"title": "Gefecht",
		"importance": 3,
		"action": {"type": "open_system", "system_id": SYSTEM_ID},
	})
	center.call("_on_card_activated", actionable_id)
	_expect(activations.size() == 1, "card activation should emit once", failures)
	if activations.size() == 1:
		_expect(str(activations[0].get("action", {}).get("system_id", "")) == SYSTEM_ID, "activation should carry the action payload", failures)
	_expect(not center.has_notification(actionable_id), "activated notification should be removed", failures)

	# Cards without an action do not emit on click.
	center.call("_on_card_activated", persistent_id)
	_expect(activations.size() == 1, "action-less cards should not emit activations", failures)

	# Custom UI content is embedded into the card.
	var custom_control := Label.new()
	custom_control.name = "CustomNotificationContent"
	custom_control.text = "Eigene UI"
	var custom_id := center.post_notification({
		"title": "Mit eigener UI",
		"importance": 2,
		"custom_content": custom_control,
	})
	await get_tree().process_frame
	_expect(not custom_id.is_empty() and center.find_child("CustomNotificationContent", true, false) != null, "custom content control should be embedded", failures)

	center.queue_free()
	await get_tree().process_frame


func _run_battle_overview_checks(failures: Array[String]) -> void:
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()
	SpaceManager.reset_runtime_state(true)
	EconomyManager.bootstrap(PackedStringArray([EMPIRE_A, EMPIRE_B]), {"generated_seed": 7, "systems": []})
	SpaceManager.bootstrap_empires(PackedStringArray([EMPIRE_A, EMPIRE_B]))

	var own_a := SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_A, SYSTEM_ID, {"unit_id": "own_a", "local_position": Vector3.ZERO})
	var own_b := SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_A, SYSTEM_ID, {"unit_id": "own_b", "local_position": Vector3(2.0, 0.0, 0.0)})
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_B, SYSTEM_ID, {"unit_id": "enemy_a", "local_position": Vector3(8.0, 0.0, 0.0)})
	var fleet := SpaceManager.create_fleet(EMPIRE_A, SYSTEM_ID, PackedStringArray(["own_a", "own_b"]), {"display_name": "Eigene Flotte"})
	_expect(own_a != null and own_b != null and fleet != null, "battle overview scenario should spawn", failures)
	if fleet == null:
		return

	SpaceManager._on_sim_day_tick({})
	var battle_id := SpaceManager.get_battle_id_for_system(SYSTEM_ID)
	_expect(not battle_id.is_empty(), "scenario should start a battle", failures)

	# Standalone reusable panel renders sides, members, and the event log.
	var overview := BATTLE_OVERVIEW_SCRIPT.new() as BattleOverviewPanel
	add_child(overview)
	await get_tree().process_frame
	overview.show_battle(battle_id)
	await get_tree().process_frame
	_expect(overview.visible, "battle overview should be visible for an active battle", failures)
	var content := overview.find_child("BattleContent", true, false) as VBoxContainer
	_expect(content != null and content.get_child_count() > 4, "battle overview should render side bars, members, and log", failures)
	_expect(overview.find_child("BattleMember_enemy_a", true, false) != null, "battle overview should list battle members", failures)
	overview.show_battle("")
	_expect(not overview.visible, "battle overview should hide without a battle", failures)
	overview.queue_free()

	# The entity details panel embeds the battle section for fighting fleets.
	var panel := PANEL_SCRIPT.new() as SpaceEntityDetailsPanel
	add_child(panel)
	await get_tree().process_frame
	var context := {
		"active_empire_id": EMPIRE_A,
		"can_command": true,
		"owner_names": {EMPIRE_A: "Eigenes Imperium", EMPIRE_B: "Feind"},
		"system_names": {SYSTEM_ID: "Notify-System"},
	}
	panel.open_fleet(fleet.fleet_id, context)
	await get_tree().process_frame
	_expect(panel.find_child("BattleOverviewSection", true, false) != null, "fleet in battle should show the battle overview section", failures)

	panel.open_ship("enemy_a", context)
	await get_tree().process_frame
	_expect(panel.find_child("BattleOverviewSection", true, false) != null, "unit in battle should show the battle overview section", failures)

	# Out-of-battle entities show no battle section.
	var idle_unit := SpaceManager.spawn_unit(SpaceManager.SCIENCE_SHIP_CLASS_ID, EMPIRE_A, "sys_idle", {"unit_id": "idle_a"})
	_expect(idle_unit != null, "idle unit should spawn", failures)
	panel.open_ship("idle_a", context)
	await get_tree().process_frame
	_expect(panel.find_child("BattleOverviewSection", true, false) == null, "idle unit should not show a battle overview", failures)

	panel.queue_free()
	await get_tree().process_frame
	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
