extends SceneTree

const ANOMALY_POOL_SCRIPT: Script = preload("res://core/anomaly/AnomalyPool.gd")
const GALAXY_STATE_SCRIPT: Script = preload("res://scene/galaxy/GalaxyState.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Anomaly pool test passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _run(failures: Array[String]) -> void:
	var system_details := {
		"id": "sys_alpha",
		"name": "Alpha",
		"stars": [{
			"id": "star_00",
			"name": "Alpha",
			"kind": "star",
			"anomaly_component": {
				"mode": "fixed",
				"fixed_anomaly_ids": ["drifting_probe"],
			},
		}],
		"orbitals": [
			{
				"id": "planet_00",
				"name": "Alpha I",
				"type": "planet",
				"anomaly_component": {
					"mode": "fixed",
					"fixed_anomaly_ids": ["quiet_vault"],
				},
			},
			{
				"id": "planet_01",
				"name": "Alpha II",
				"type": "planet",
				"anomaly_component": {
					"mode": "fixed",
					"fixed_anomaly_ids": ["quiet_vault"],
				},
			},
			{
				"id": "belt_00",
				"name": "Alpha Belt",
				"type": "asteroid_belt",
				"anomaly_component": {
					"mode": "fixed",
					"fixed_anomaly_ids": ["singing_vein"],
				},
			},
		],
	}

	var records_a: Array[Dictionary] = ANOMALY_POOL_SCRIPT.build_spawn_records(101, [system_details])
	var records_b: Array[Dictionary] = ANOMALY_POOL_SCRIPT.build_spawn_records(101, [system_details])
	_expect(JSON.stringify(records_a) == JSON.stringify(records_b), "anomaly spawn records should be deterministic for the same seed and bodies", failures)
	_expect(records_a.size() == 3, "fixed pool should create three anomaly records after once-per-game de-duplication", failures)
	_expect(_count_definition(records_a, "quiet_vault") == 1, "once-per-game definition should spawn at most once", failures)
	_expect(_count_definition(records_a, "drifting_probe") == 1, "once-per-player definition should keep one physical record on this body", failures)
	_expect(_count_definition(records_a, "singing_vein") == 1, "repeatable definition should spawn on the belt", failures)

	var state := GALAXY_STATE_SCRIPT.new() as GalaxyState
	state.load_from_layout({
		"seed": 101,
		"systems": [{
			"id": "sys_alpha",
			"name": "Alpha",
			"position": Vector3.ZERO,
			"system_summary": {},
			"star_profile": {},
		}],
		"links": [],
		"hyperlane_graph": {},
		"anomalies": records_a,
	})
	state.set_empires([{"id": "empire_a", "name": "Empire A"}])

	var discovered := state.discover_anomalies_for_empire("sys_alpha", "empire_a", 12, "survey", "science_01")
	_expect(discovered.size() == 3, "survey should discover visible anomalies for the empire", failures)
	var visible := state.get_system_anomalies("sys_alpha", "empire_a", true)
	_expect(visible.size() == 3, "visible anomaly list should include discovered anomalies", failures)
	_expect(not str(visible[0].get("lore", "")).is_empty(), "discovered anomalies should carry deterministic lore", failures)

	var anomaly_id := str(visible[0].get("anomaly_id", ""))
	var outcome: Dictionary = ANOMALY_POOL_SCRIPT.pick_outcome(
		str(visible[0].get("definition_id", "")),
		anomaly_id,
		"empire_a",
		int(visible[0].get("spawn_seed", 0))
	)
	_expect(not outcome.is_empty(), "definition should provide a research outcome", failures)
	_expect(state.mark_anomaly_researched(anomaly_id, "empire_a", outcome, "Test outcome", 14), "researched state should be recorded", failures)
	_expect(str(state.get_anomaly_empire_state(anomaly_id, "empire_a").get("status", "")) == ANOMALY_POOL_SCRIPT.STATUS_RESEARCHED, "researched anomaly should report researched status", failures)


func _count_definition(records: Array[Dictionary], definition_id: String) -> int:
	var count := 0
	for record in records:
		if str(record.get("definition_id", "")) == definition_id:
			count += 1
	return count


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
