extends Node

const EMPIRE_A := "empire_det_a"
const EMPIRE_B := "empire_det_b"
const SYSTEM_ID := "sys_det"
const GALAXY_SEED := 7
const SIM_DAYS := 120

var _collected_events: Array[Dictionary] = []


func _ready() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Combat determinism test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	var first_run := _run_scenario()
	var second_run := _run_scenario()

	_expect(not first_run.get("events_json", "").is_empty(), "scenario should produce combat events", failures)
	_expect(int(first_run.get("event_count", 0)) > 10, "scenario should produce a meaningful event stream, got %d events" % int(first_run.get("event_count", 0)), failures)
	_expect(
		first_run.get("events_json", "") == second_run.get("events_json", "x"),
		"identical scenarios must produce identical combat event logs (%d vs %d events)" % [int(first_run.get("event_count", 0)), int(second_run.get("event_count", 0))],
		failures
	)
	_expect(
		first_run.get("survivors", "") == second_run.get("survivors", "x"),
		"identical scenarios must produce identical survivors (%s vs %s)" % [first_run.get("survivors", ""), second_run.get("survivors", "")],
		failures
	)
	_expect(
		first_run.get("survivor_state", "") == second_run.get("survivor_state", "x"),
		"identical scenarios must leave survivors with identical hull/shield state",
		failures
	)
	_cleanup()


func _run_scenario() -> Dictionary:
	_cleanup()
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()
	SpaceManager.reset_runtime_state(true)
	EconomyManager.bootstrap(PackedStringArray([EMPIRE_A, EMPIRE_B]), {
		"generated_seed": GALAXY_SEED,
		"systems": [],
	})
	SpaceManager.bootstrap_empires(PackedStringArray([EMPIRE_A, EMPIRE_B]))

	_collected_events = []
	SpaceManager.combat_events.connect(_on_combat_events)

	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_A, SYSTEM_ID, {"unit_id": "det_a1", "local_position": Vector3.ZERO})
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_A, SYSTEM_ID, {"unit_id": "det_a2", "local_position": Vector3(2.0, 0.0, 0.0)})
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_B, SYSTEM_ID, {"unit_id": "det_b1", "local_position": Vector3(8.0, 0.0, 0.0)})
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_B, SYSTEM_ID, {"unit_id": "det_b2", "local_position": Vector3(8.0, 0.0, 3.0)})

	for _day in range(SIM_DAYS):
		SpaceManager._on_sim_day_tick({})

	SpaceManager.combat_events.disconnect(_on_combat_events)

	var survivor_ids: Array[String] = []
	var survivor_state := ""
	for unit_id in ["det_a1", "det_a2", "det_b1", "det_b2"]:
		var unit: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
		if unit == null:
			continue
		survivor_ids.append(unit_id)
		survivor_state += "%s:%d/%d|" % [unit_id, unit.current_hull_points, unit.current_shield_points]

	return {
		"events_json": JSON.stringify(_collected_events),
		"event_count": _collected_events.size(),
		"survivors": ",".join(survivor_ids),
		"survivor_state": survivor_state,
	}


func _on_combat_events(events: Array[Dictionary]) -> void:
	for event in events:
		_collected_events.append(event.duplicate(true))


func _cleanup() -> void:
	if SpaceManager.combat_events.is_connected(_on_combat_events):
		SpaceManager.combat_events.disconnect(_on_combat_events)
	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
