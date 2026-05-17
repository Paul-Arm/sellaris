extends SceneTree

const ANOMALY_POOL_SCRIPT: Script = preload("res://core/anomaly/AnomalyPool.gd")
const GALAXY_STATE_SCRIPT: Script = preload("res://scene/galaxy/GalaxyState.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Empire anomaly menu state test passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _run(failures: Array[String]) -> void:
	var discovered_record: Dictionary = ANOMALY_POOL_SCRIPT.normalize_anomaly_record({
		"anomaly_id": "anom_alpha_vault",
		"definition_id": "quiet_vault",
		"system_id": "sys_alpha",
		"system_name": "Alpha",
		"body_id": "planet_00",
		"body_name": "Alpha I",
		"state_by_empire_id": {
			"empire_a": ANOMALY_POOL_SCRIPT.build_discovery_state(
				{"anomaly_id": "anom_alpha_vault", "definition_id": "quiet_vault", "spawn_seed": 1},
				"empire_a",
				4
			),
		},
	})
	var researched_record: Dictionary = ANOMALY_POOL_SCRIPT.normalize_anomaly_record({
		"anomaly_id": "anom_beta_vein",
		"definition_id": "singing_vein",
		"system_id": "sys_beta",
		"system_name": "Beta",
		"body_id": "belt_00",
		"body_name": "Beta Belt",
		"state_by_empire_id": {
			"empire_a": ANOMALY_POOL_SCRIPT.build_researched_state(
				ANOMALY_POOL_SCRIPT.build_discovery_state(
					{"anomaly_id": "anom_beta_vein", "definition_id": "singing_vein", "spawn_seed": 2},
					"empire_a",
					6
				),
				{"type": "monthly_resources"},
				"Monatlich: +2 Matter",
				8
			),
		},
	})
	var hidden_record: Dictionary = ANOMALY_POOL_SCRIPT.normalize_anomaly_record({
		"anomaly_id": "anom_hidden_probe",
		"definition_id": "drifting_probe",
		"system_id": "sys_gamma",
		"system_name": "Gamma",
		"body_id": "star_00",
		"body_name": "Gamma",
	})

	var state := GALAXY_STATE_SCRIPT.new() as GalaxyState
	state.load_from_layout({
		"seed": 42,
		"systems": [
			{"id": "sys_alpha", "name": "Alpha", "position": Vector3.ZERO, "system_summary": {}, "star_profile": {}},
			{"id": "sys_beta", "name": "Beta", "position": Vector3.RIGHT, "system_summary": {}, "star_profile": {}},
			{"id": "sys_gamma", "name": "Gamma", "position": Vector3.LEFT, "system_summary": {}, "star_profile": {}},
		],
		"links": [],
		"hyperlane_graph": {},
		"anomalies": [hidden_record, researched_record, discovered_record],
	})
	state.set_empires([{"id": "empire_a", "name": "Empire A"}, {"id": "empire_b", "name": "Empire B"}])

	var visible_a := state.get_visible_anomalies_for_empire("empire_a")
	_expect(visible_a.size() == 2, "empire_a should see discovered and researched anomalies only", failures)
	_expect(str(visible_a[0].get("anomaly_id", "")) != "anom_hidden_probe", "hidden anomalies should not leak into the empire list", failures)
	_expect(_contains_anomaly(visible_a, "anom_alpha_vault"), "discovered anomaly should be present", failures)
	_expect(_contains_anomaly(visible_a, "anom_beta_vein"), "researched anomaly should remain present", failures)
	_expect(state.get_visible_anomalies_for_empire("empire_b").is_empty(), "other empires should not see empire_a anomalies", failures)


func _contains_anomaly(records: Array[Dictionary], anomaly_id: String) -> bool:
	for record in records:
		if str(record.get("anomaly_id", "")) == anomaly_id:
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
