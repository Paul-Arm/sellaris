extends Node

const EMPIRE_ID := "empire_upkeep"
const SYSTEM_ID := "sys_alpha"
const GALAXY_SEED := 7


func _ready() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Unit upkeep economy smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()
	SpaceManager.reset_runtime_state(true)
	EconomyManager.bootstrap(PackedStringArray([EMPIRE_ID]), {
		"generated_seed": GALAXY_SEED,
		"systems": [],
	})
	SpaceManager.bootstrap_empires(PackedStringArray([EMPIRE_ID]))

	# Bootstrap unlocks tier-0 components and creates default designs.
	_expect(SpaceManager.is_ship_component_unlocked(EMPIRE_ID, "basic_laser"), "tier 0 weapon should be unlocked after bootstrap", failures)
	_expect(not SpaceManager.is_ship_component_unlocked(EMPIRE_ID, "pulse_laser_mk2"), "tier 1 weapon should stay locked", failures)
	var default_corvette_design_id := SpaceManager.get_default_ship_design_id(EMPIRE_ID, SpaceManager.CORVETTE_CLASS_ID)
	_expect(not default_corvette_design_id.is_empty(), "corvette default design should exist after bootstrap", failures)

	# Spawned units pick up the default design and its compiled hull.
	var corvette := SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {
		"unit_id": "corvette_alpha",
		"local_position": Vector3.ZERO,
	})
	_expect(corvette != null, "corvette should spawn", failures)
	if corvette == null:
		_cleanup()
		return
	_expect(corvette.design_id == default_corvette_design_id, "spawned corvette should use the default design", failures)
	_expect(corvette.max_hull_points == 300, "default corvette hull should match compiled design stats", failures)

	# Design upkeep (hull + 2x laser + shield + drive) lands in the economy ledger.
	# energy: 0.8 + 1.0 + 1.0 + 0.8 + 0.5 = 4.1 -> 4100 milliunits, alloys: 0.2 -> 200.
	_expect(EconomyManager.get_projected_monthly_net(EMPIRE_ID, "energy") == -4100, "corvette design upkeep should register energy expense, got %d" % EconomyManager.get_projected_monthly_net(EMPIRE_ID, "energy"), failures)
	_expect(EconomyManager.get_projected_monthly_net(EMPIRE_ID, "alloys") == -200, "corvette design upkeep should register alloys expense, got %d" % EconomyManager.get_projected_monthly_net(EMPIRE_ID, "alloys"), failures)

	SpaceManager.remove_unit(corvette.unit_id)
	_expect(EconomyManager.get_projected_monthly_net(EMPIRE_ID, "energy") == 0, "removing the unit should clear its upkeep", failures)

	# Shipyard stations build corvettes from the default design.
	var station := SpaceManager.spawn_unit(SpaceManager.BASIC_STATION_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {
		"unit_id": "station_alpha",
		"local_position": Vector3(10.0, 0.0, 0.0),
	})
	_expect(station != null, "station should spawn", failures)
	if station == null:
		_cleanup()
		return
	_expect(station.can_build_units(), "station should act as a shipyard", failures)

	var ship_options := SpaceManager.get_ship_build_options(station.unit_id)
	var corvette_option: Dictionary = {}
	for option in ship_options:
		if str(option.get("class_id", "")) == SpaceManager.CORVETTE_CLASS_ID:
			corvette_option = option
			break
	_expect(not corvette_option.is_empty(), "station should offer corvette construction", failures)
	if corvette_option.is_empty():
		_cleanup()
		return
	_expect(str(corvette_option.get("design_id", "")) == default_corvette_design_id, "ship build option should reference the default design", failures)
	# Default design build time: 30 hull + 4 + 4 (lasers) + 3 (shield) + 2 (drive) = 43 days.
	_expect(int(corvette_option.get("build_time_days", 0)) == 43, "ship build option should use design build time, got %d" % int(corvette_option.get("build_time_days", 0)), failures)

	var alloys_before := EconomyManager.get_amount(EMPIRE_ID, "alloys")
	var project_id := SpaceManager.request_build_ship(station.unit_id, SpaceManager.CORVETTE_CLASS_ID)
	_expect(not project_id.is_empty(), "ship build order should start", failures)
	var alloys_after := EconomyManager.get_amount(EMPIRE_ID, "alloys")
	# Default design build cost: 90 hull + 80 lasers + 35 shield + 25 drive = 230 alloys.
	_expect(alloys_before - alloys_after == 230000, "ship build should commit design alloy costs, got %d" % (alloys_before - alloys_after), failures)

	for _day in range(43):
		SpaceManager._on_sim_day_tick({})

	var corvette_ids := SpaceManager.get_unit_ids_of_class(SpaceManager.CORVETTE_CLASS_ID)
	_expect(corvette_ids.size() == 1, "corvette should be completed after the design build time, got %d" % corvette_ids.size(), failures)
	if corvette_ids.size() == 1:
		var built_corvette := SpaceManager.get_unit(corvette_ids[0])
		_expect(built_corvette.design_id == default_corvette_design_id, "built corvette should carry the design id", failures)
		_expect(built_corvette.max_hull_points == 300, "built corvette hull should match the design", failures)
		_expect(built_corvette.current_system_id == SYSTEM_ID, "built corvette should spawn in the shipyard system", failures)

	# Snapshot round trip keeps designs, unlocks, and unit design assignment.
	var snapshot: Dictionary = SpaceManager.build_snapshot()
	SpaceManager.load_snapshot(snapshot)
	var restored_corvette_ids := SpaceManager.get_unit_ids_of_class(SpaceManager.CORVETTE_CLASS_ID)
	_expect(restored_corvette_ids.size() == 1, "snapshot round trip should keep the built corvette", failures)
	if restored_corvette_ids.size() == 1:
		var restored_corvette := SpaceManager.get_unit(restored_corvette_ids[0])
		_expect(restored_corvette.design_id == default_corvette_design_id, "design assignment should round-trip through snapshots", failures)
	_expect(SpaceManager.get_default_ship_design_id(EMPIRE_ID, SpaceManager.CORVETTE_CLASS_ID) == default_corvette_design_id, "default design mapping should round-trip through snapshots", failures)
	_expect(SpaceManager.is_ship_component_unlocked(EMPIRE_ID, "basic_laser"), "unlocks should round-trip through snapshots", failures)

	_cleanup()


func _cleanup() -> void:
	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
