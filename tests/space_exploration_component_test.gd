extends Node


func _ready() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Space exploration component test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	SpaceManager.reset_runtime_state(true)

	var science_class := SpaceManager.get_unit_class(SpaceManager.SCIENCE_SHIP_CLASS_ID)
	_expect(science_class != null and science_class.has_explorer(), "science ship class should carry explorer component", failures)

	var ship := SpaceManager.spawn_unit(SpaceManager.SCIENCE_SHIP_CLASS_ID, "empire_explorer", "sys_alpha", {
		"unit_id": "science_explorer",
		"display_name": "ISS Kepler",
		"local_position": Vector3.ZERO,
	})
	_expect(ship != null and ship.can_explore_systems(), "science ship should spawn with exploration capability", failures)
	if ship == null:
		return

	var details := _build_test_system_details()
	var order_id := SpaceManager.request_explore_system(ship.unit_id, "sys_alpha", details, 0, {"galaxy_seed": 4242})
	_expect(not order_id.is_empty(), "exploration order should start in current system", failures)
	var order := SpaceManager.get_exploration_order(order_id)
	_expect(not order.is_empty(), "started exploration order should be queryable", failures)
	_expect(int(order.get("target_count", 0)) == 3, "exploration should scan star and two orbitals", failures)
	_expect(bool(ship.metadata.get("exploration_active", false)), "ship metadata should mark active exploration", failures)
	for target_variant in order.get("targets", []):
		var target: Dictionary = target_variant
		var scan_days := int(target.get("scan_days_total", 0))
		_expect(scan_days >= 5 and scan_days <= 15, "scan duration should stay in the component range", failures)

	var snapshot := SpaceManager.build_snapshot()
	_expect(snapshot.has("exploration_orders"), "snapshot should include exploration orders", failures)
	SpaceManager.load_snapshot(snapshot, true)
	ship = SpaceManager.get_unit("science_explorer")
	order = SpaceManager.get_exploration_order(order_id)
	_expect(ship != null and not order.is_empty(), "snapshot load should restore ship and exploration order", failures)
	if ship == null or order.is_empty():
		return

	var scanned_body_ids := PackedStringArray()
	var completed_orders := PackedStringArray()
	var scan_callable := func(completed_order_id: String, _unit_id: String, _system_id: String, body_id: String) -> void:
		if completed_order_id == order_id:
			scanned_body_ids.append(body_id)
	var complete_callable := func(completed_order_id: String, _unit_id: String, _system_id: String) -> void:
		completed_orders.append(completed_order_id)
	SpaceManager.exploration_scan_completed.connect(scan_callable)
	SpaceManager.exploration_completed.connect(complete_callable)

	for _day in range(90):
		if SpaceManager.get_exploration_order(order_id).is_empty():
			break
		SpaceManager._on_sim_day_tick({})

	if SpaceManager.exploration_scan_completed.is_connected(scan_callable):
		SpaceManager.exploration_scan_completed.disconnect(scan_callable)
	if SpaceManager.exploration_completed.is_connected(complete_callable):
		SpaceManager.exploration_completed.disconnect(complete_callable)

	_expect(scanned_body_ids.size() == 3, "exploration should emit one scan completion per body", failures)
	_expect(completed_orders.has(order_id), "exploration should emit order completion", failures)
	_expect(SpaceManager.get_exploration_order(order_id).is_empty(), "completed exploration order should be removed", failures)
	ship = SpaceManager.get_unit("science_explorer")
	_expect(ship != null and not bool(ship.metadata.get("exploration_active", false)), "completed exploration should clear ship metadata", failures)

	SpaceManager.reset_runtime_state(true)


func _build_test_system_details() -> Dictionary:
	return {
		"id": "sys_alpha",
		"name": "Alpha",
		"generated_seed": 4242,
		"stars": [{
			"id": "alpha_star",
			"name": "Alpha",
			"type": "star",
			"scale": 1.0,
			"orbit_radius": 0.0,
			"orbit_angle": 0.0,
		}],
		"orbitals": [{
			"id": "alpha_i",
			"name": "Alpha I",
			"type": "planet",
			"size": 1.4,
			"orbit_radius": 8.0,
			"orbit_angle": 0.0,
		}, {
			"id": "alpha_belt",
			"name": "Alpha Belt",
			"type": "asteroid_belt",
			"orbit_radius": 15.0,
			"orbit_angle": 1.1,
			"orbit_width": 4.0,
		}],
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
