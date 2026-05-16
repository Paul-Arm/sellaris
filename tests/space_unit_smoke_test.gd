extends Node

const DEBUG_CORVETTE_CLASS_ID := "debug_corvette"
const DEBUG_STATION_CLASS_ID := "debug_station"


func _ready() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Space unit smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	SpaceManager.reset_runtime_state(true)
	_register_debug_unit_classes()

	_expect(SpaceManager.has_unit_class(SpaceManager.SCIENCE_SHIP_CLASS_ID), "science_ship class should be registered", failures)
	_expect(SpaceManager.has_unit_class(DEBUG_CORVETTE_CLASS_ID), "debug corvette class should be registered", failures)
	_expect(SpaceManager.has_unit_class(DEBUG_STATION_CLASS_ID), "debug station class should be registered", failures)

	var science_a := SpaceManager.spawn_unit(SpaceManager.SCIENCE_SHIP_CLASS_ID, "empire_test", "sys_alpha", {
		"display_name": "ISS Curie",
		"local_position": Vector3.ZERO,
	})
	var science_b := SpaceManager.spawn_unit(SpaceManager.SCIENCE_SHIP_CLASS_ID, "empire_test", "sys_alpha", {
		"display_name": "ISS Faraday",
		"local_position": Vector3(2.0, 0.0, 0.0),
	})
	var science_c := SpaceManager.spawn_unit(SpaceManager.SCIENCE_SHIP_CLASS_ID, "empire_test", "sys_alpha", {
		"display_name": "ISS Hopper",
		"local_position": Vector3(4.0, 0.0, 0.0),
	})
	var station := SpaceManager.spawn_unit(DEBUG_STATION_CLASS_ID, "empire_test", "sys_alpha", {
		"display_name": "Anchor One",
		"local_position": Vector3(0.0, 0.0, 8.0),
	})

	_expect(science_a != null and science_a.is_mobile(), "science ship A should spawn mobile", failures)
	_expect(science_b != null and science_b.is_mobile(), "science ship B should spawn mobile", failures)
	_expect(science_c != null and science_c.is_mobile(), "science ship C should spawn mobile", failures)
	_expect(station != null and station.is_stationary(), "debug station should spawn stationary", failures)
	if station != null:
		_expect(not SpaceManager.issue_unit_move(station.unit_id, Vector3(5.0, 0.0, 5.0)), "station should reject unit move orders", failures)
	if science_c != null:
		_expect(SpaceManager.issue_unit_hyperlane_move(science_c.unit_id, "sys_beta", 2), "independent ship hyperlane move should be accepted", failures)
		for _day in range(2):
			SpaceManager._on_sim_day_tick({})
		_expect(science_c.current_system_id == "sys_beta", "independent ship should arrive through hyperlane travel", failures)

	var fleet := SpaceManager.create_fleet("empire_test", "sys_alpha", [science_a.unit_id, science_b.unit_id], {
		"display_name": "Science Group",
	})
	_expect(fleet != null and fleet.unit_ids.size() == 2, "fleet should contain both science ships", failures)
	if fleet == null:
		return

	_expect(not SpaceManager.add_unit_to_fleet(station.unit_id, fleet.fleet_id), "station should not join a mobile fleet", failures)
	_expect(SpaceManager.issue_fleet_hyperlane_move(fleet.fleet_id, "sys_beta", 2), "fleet hyperlane move should be accepted", failures)
	for _day in range(2):
		SpaceManager._on_sim_day_tick({})
	_expect(fleet.current_system_id == "sys_beta", "fleet should arrive through hyperlane travel", failures)
	_expect(science_a.current_system_id == "sys_beta" and science_b.current_system_id == "sys_beta", "fleet members should arrive with fleet", failures)
	_expect(SpaceManager.issue_fleet_move(fleet.fleet_id, Vector3(19.0, 0.0, 0.0)), "fleet move order should be accepted", failures)
	for _day in range(3):
		SpaceManager._on_sim_day_tick({})

	var moved_fleet := SpaceManager.get_fleet(fleet.fleet_id)
	_expect(moved_fleet != null, "fleet should survive movement", failures)
	if moved_fleet != null:
		_expect(moved_fleet.movement_state == SpaceUnitRuntime.MOVEMENT_IDLE, "fleet should arrive and clear movement state", failures)
		_expect(moved_fleet.local_position.distance_to(Vector3(19.0, 0.0, 0.0)) < 0.001, "fleet should arrive at target", failures)

	_expect(SpaceManager.set_unit_evasion_mode(science_a.unit_id, true), "unit evasion mode should be settable", failures)
	_expect(bool(science_a.metadata.get("evasion_active", false)), "unit evasion metadata should be active", failures)
	_expect(SpaceManager.set_fleet_evasion_mode(fleet.fleet_id, true), "fleet evasion mode should apply to members", failures)
	_expect(bool(science_b.metadata.get("evasion_active", false)), "fleet evasion should mark member metadata", failures)

	var split_fleet := SpaceManager.split_unit_to_new_fleet(science_a.unit_id)
	_expect(split_fleet != null and split_fleet.unit_ids.size() == 1, "split should create a single-ship detachment", failures)
	if split_fleet != null:
		_expect(science_a.fleet_id == split_fleet.fleet_id, "split ship should belong to the new fleet", failures)
		var reinforced := SpaceManager.debug_reinforce_fleet(split_fleet.fleet_id, science_a.unit_id)
		_expect(reinforced != null, "debug reinforce should spawn a fleet member", failures)
		if reinforced != null:
			_expect(reinforced.class_id == science_a.class_id, "reinforcement should copy the template class", failures)
			_expect(reinforced.fleet_id == split_fleet.fleet_id, "reinforcement should join the target fleet", failures)
			_expect(SpaceManager.remove_unit_from_fleet(reinforced.unit_id), "member removal should detach a reinforced ship", failures)
			_expect(reinforced.fleet_id.is_empty(), "removed member should have no fleet assignment", failures)

	var snapshot := SpaceManager.build_snapshot()
	_expect(snapshot.has("space_unit_classes"), "snapshot should emit space_unit_classes", failures)
	_expect(snapshot.has("space_units"), "snapshot should emit space_units", failures)
	_expect(not snapshot.has("ship_classes"), "snapshot should not emit legacy ship_classes", failures)
	_expect(not snapshot.has("ships"), "snapshot should not emit legacy ships", failures)

	SpaceManager.load_snapshot(snapshot, true)
	_expect(SpaceManager.get_unit(science_a.unit_id) != null, "snapshot load should restore science ship", failures)
	_expect(SpaceManager.get_fleet(fleet.fleet_id) != null, "snapshot load should restore fleet", failures)
	var restored_science_a := SpaceManager.get_unit(science_a.unit_id)
	_expect(restored_science_a != null and bool(restored_science_a.metadata.get("evasion_active", false)), "snapshot load should restore unit evasion metadata", failures)


func _register_debug_unit_classes() -> void:
	SpaceManager.register_unit_class_from_data({
		"class_id": DEBUG_CORVETTE_CLASS_ID,
		"display_name": "Debug Corvette",
		"unit_kind": SpaceUnitClass.UNIT_KIND_SHIP,
		"category": SpaceUnitClass.CATEGORY_COMBAT,
		"max_hull_points": 300.0,
		"default_ai_role": "combat_patrol",
		"command_tags": ["combat", "fleet"],
		"upkeep_component": {
			"monthly_costs": {
				"energy": 1.0,
				"alloys": 0.2,
			},
			"command_point_cost": 1.0,
		},
		"mobility_component": {
			"cruise_speed": 1.0,
			"acceleration": 1.8,
			"turn_rate_degrees": 220.0,
			"formation_radius": 4.0,
			"can_join_fleets": true,
			"uses_hyperlanes": true,
			"can_orbit_system_objects": true,
		},
	}, true)
	SpaceManager.register_unit_class_from_data({
		"class_id": DEBUG_STATION_CLASS_ID,
		"display_name": "Debug Station",
		"unit_kind": SpaceUnitClass.UNIT_KIND_STATION,
		"category": SpaceUnitClass.CATEGORY_STATION,
		"max_hull_points": 1800.0,
		"default_ai_role": "system_guard",
		"command_tags": ["station", "defense"],
		"upkeep_component": {
			"monthly_costs": {
				"energy": 3.0,
				"alloys": 0.5,
			},
			"command_point_cost": 0.0,
		},
	}, true)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
