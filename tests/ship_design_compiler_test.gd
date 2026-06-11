extends SceneTree

const SHIP_COMPONENT_CATALOG_SCRIPT: Script = preload("res://core/space/design/ShipComponentCatalog.gd")
const SHIP_DESIGN_CATALOG_SCRIPT: Script = preload("res://core/space/design/ShipDesignCatalog.gd")
const SPACE_UNIT_CLASS_SCRIPT: Script = preload("res://core/space/SpaceUnitClass.gd")

const TEST_EMPIRE_ID := "empire_design_test"


func _initialize() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Ship design compiler test passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _run(failures: Array[String]) -> void:
	var component_catalog: ShipComponentCatalog = SHIP_COMPONENT_CATALOG_SCRIPT.new()
	component_catalog.load_definitions()
	_expect(component_catalog.has_component("basic_laser"), "component config should provide basic_laser", failures)
	_expect(component_catalog.has_component("shockwave_emitter"), "component config should provide shockwave_emitter", failures)

	var design_catalog: ShipDesignCatalog = SHIP_DESIGN_CATALOG_SCRIPT.new()
	design_catalog.setup(component_catalog)
	design_catalog.bootstrap_empire_unlocks(TEST_EMPIRE_ID)

	var corvette_class := _build_corvette_class()
	var station_class := _build_station_class()

	# Slot kind mismatch: weapon component in drive slot.
	var mismatch_design_id := design_catalog.create_design(TEST_EMPIRE_ID, corvette_class, {
		"drive": "basic_laser",
	})
	_expect(mismatch_design_id.is_empty(), "weapon in drive slot should fail validation", failures)
	_expect(_errors_have_prefix(design_catalog.get_last_validation_errors(), "slot_mismatch:"), "mismatch error should be reported", failures)

	# Required drive slot left empty.
	var missing_drive_design_id := design_catalog.create_design(TEST_EMPIRE_ID, corvette_class, {
		"weapon_1": "basic_laser",
	})
	_expect(missing_drive_design_id.is_empty(), "missing required drive should fail validation", failures)
	_expect(_errors_have_prefix(design_catalog.get_last_validation_errors(), "required_slot_empty:"), "required slot error should be reported", failures)

	# Locked tier-1 component.
	var locked_design_id := design_catalog.create_design(TEST_EMPIRE_ID, corvette_class, {
		"weapon_1": "pulse_laser_mk2",
		"drive": "basic_drive",
	})
	_expect(locked_design_id.is_empty(), "locked component should fail validation", failures)
	_expect(_errors_have_prefix(design_catalog.get_last_validation_errors(), "component_locked:"), "locked component error should be reported", failures)

	# Drive on a station hull (requires mobility).
	var station_drive_design_id := design_catalog.create_design(TEST_EMPIRE_ID, station_class, {
		"utility_1": "basic_drive",
	})
	_expect(station_drive_design_id.is_empty(), "drive on station should fail validation", failures)

	# Valid corvette design with deterministic compiled stats.
	var valid_design_id := design_catalog.create_design(TEST_EMPIRE_ID, corvette_class, {
		"weapon_1": "basic_laser",
		"weapon_2": "basic_laser",
		"defense_1": "basic_armor_plating",
		"drive": "basic_drive",
	}, {"display_name": "Test Corvette"})
	_expect(not valid_design_id.is_empty(), "valid design should be accepted: %s" % ", ".join(design_catalog.get_last_validation_errors()), failures)
	if not valid_design_id.is_empty():
		var stats := design_catalog.get_compiled_stats(valid_design_id, corvette_class)
		_expect(int(stats.get("max_hull_points", 0)) == 320, "hull should be 300 base + 20 armor plating, got %d" % int(stats.get("max_hull_points", 0)), failures)
		_expect(int(stats.get("armor_points", 0)) == 8, "armor should be 8", failures)
		_expect(int(stats.get("max_shield_points", -1)) == 0, "no shield assigned", failures)
		_expect(int(stats.get("evasion_bp", 0)) == 500, "evasion should come from the drive", failures)
		_expect(is_equal_approx(float(stats.get("cruise_speed", 0.0)), 6.0), "cruise speed should come from the drive", failures)
		_expect((stats.get("weapons", []) as Array).size() == 2, "two weapons should be compiled", failures)
		_expect(int(stats.get("build_time_days", 0)) == 43, "build time should be 30 + 4 + 4 + 3 + 2 = 43, got %d" % int(stats.get("build_time_days", 0)), failures)
		_expect(_amount_for(stats.get("build_costs", []), "alloys") == 225000, "build cost alloys should merge hull + components, got %d" % _amount_for(stats.get("build_costs", []), "alloys"), failures)
		_expect(_amount_for(stats.get("build_costs", []), "energy") == 40000, "build cost energy should merge hull + components", failures)
		_expect(_amount_for(stats.get("monthly_upkeep", []), "energy") == 3300, "monthly energy upkeep should merge hull + components, got %d" % _amount_for(stats.get("monthly_upkeep", []), "energy"), failures)
		_expect(_amount_for(stats.get("monthly_upkeep", []), "alloys") == 300, "monthly alloys upkeep should merge hull + components", failures)

	# Default design generation.
	design_catalog.ensure_default_designs(TEST_EMPIRE_ID, [corvette_class, station_class])
	var default_corvette_id := design_catalog.get_default_design_id(TEST_EMPIRE_ID, corvette_class.class_id)
	_expect(not default_corvette_id.is_empty(), "corvette default design should exist", failures)
	if not default_corvette_id.is_empty():
		var default_design := design_catalog.get_design(default_corvette_id)
		_expect(default_design.get_assigned_component_id("drive") == "basic_drive", "default corvette should mount the basic drive", failures)
		_expect(default_design.get_assigned_component_id("weapon_1") == "basic_laser", "default corvette should mount basic lasers", failures)
		_expect(default_design.get_assigned_component_id("defense_1") == "basic_shield_emitter", "default corvette defense should prefer the shield emitter", failures)
	var default_station_id := design_catalog.get_default_design_id(TEST_EMPIRE_ID, station_class.class_id)
	_expect(not default_station_id.is_empty(), "station default design should exist", failures)
	if not default_station_id.is_empty():
		var station_stats := design_catalog.get_compiled_stats(default_station_id, station_class)
		_expect(float(station_stats.get("cruise_speed", -1.0)) < 0.0, "station design should not provide cruise speed", failures)
		_expect((station_stats.get("weapons", []) as Array).size() >= 1, "default station should be armed", failures)

	# Unlock flow enables previously locked components.
	_expect(design_catalog.unlock_component(TEST_EMPIRE_ID, "pulse_laser_mk2"), "tier-1 weapon should unlock", failures)
	_expect(not design_catalog.unlock_component(TEST_EMPIRE_ID, "pulse_laser_mk2"), "double unlock should be rejected", failures)
	if not valid_design_id.is_empty():
		var updated := design_catalog.update_design(valid_design_id, corvette_class, {
			"weapon_1": "pulse_laser_mk2",
			"drive": "basic_drive",
		})
		_expect(updated, "design update with unlocked component should pass: %s" % ", ".join(design_catalog.get_last_validation_errors()), failures)
		var updated_stats := design_catalog.get_compiled_stats(valid_design_id, corvette_class)
		_expect((updated_stats.get("weapons", []) as Array).size() == 1, "updated design should compile one weapon", failures)

	# Snapshot round trip.
	var snapshot := design_catalog.build_snapshot()
	var restored_catalog: ShipDesignCatalog = SHIP_DESIGN_CATALOG_SCRIPT.new()
	restored_catalog.setup(component_catalog)
	restored_catalog.load_snapshot(snapshot)
	_expect(restored_catalog.is_component_unlocked(TEST_EMPIRE_ID, "pulse_laser_mk2"), "unlocks should round-trip through snapshots", failures)
	_expect(restored_catalog.get_default_design_id(TEST_EMPIRE_ID, corvette_class.class_id) == default_corvette_id, "default design mapping should round-trip", failures)
	if not valid_design_id.is_empty():
		var restored_stats := restored_catalog.get_compiled_stats(valid_design_id, corvette_class)
		_expect((restored_stats.get("weapons", []) as Array).size() == 1, "restored design should compile identically", failures)


func _build_corvette_class() -> SpaceUnitClass:
	return SPACE_UNIT_CLASS_SCRIPT.from_dict({
		"class_id": "test_corvette",
		"display_name": "Test Corvette",
		"unit_kind": "ship",
		"category": "combat",
		"max_hull_points": 300,
		"component_slots": [
			{"slot_id": "weapon_1", "slot_kind": "weapon", "required": false},
			{"slot_id": "weapon_2", "slot_kind": "weapon", "required": false},
			{"slot_id": "defense_1", "slot_kind": "defense", "required": false},
			{"slot_id": "utility_1", "slot_kind": "utility", "required": false},
			{"slot_id": "drive", "slot_kind": "drive", "required": true},
		],
		"upkeep_component": {
			"build_costs": {"alloys": 90.0, "energy": 30.0},
			"monthly_costs": {"energy": 0.8, "alloys": 0.2},
		},
		"mobility_component": {
			"cruise_speed": 6.0,
		},
		"buildable_component": {
			"build_time_days": 30,
			"buildable_by_builder_ships": true,
			"build_tags": ["ship"],
		},
	}) as SpaceUnitClass


func _build_station_class() -> SpaceUnitClass:
	return SPACE_UNIT_CLASS_SCRIPT.from_dict({
		"class_id": "test_station",
		"display_name": "Test Station",
		"unit_kind": "station",
		"category": "station",
		"max_hull_points": 1800,
		"component_slots": [
			{"slot_id": "weapon_1", "slot_kind": "weapon", "required": false},
			{"slot_id": "defense_1", "slot_kind": "defense", "required": false},
			{"slot_id": "utility_1", "slot_kind": "drive", "required": false},
		],
		"upkeep_component": {
			"build_costs": {"alloys": 240.0, "energy": 100.0},
			"monthly_costs": {"energy": 3.0, "alloys": 0.4},
		},
	}) as SpaceUnitClass


func _errors_have_prefix(errors: PackedStringArray, prefix: String) -> bool:
	for error in errors:
		if error.begins_with(prefix):
			return true
	return false


func _amount_for(amounts_variant: Variant, resource_id: String) -> int:
	if amounts_variant is not Array:
		return 0
	for amount_variant in amounts_variant:
		if amount_variant is not Dictionary:
			continue
		var amount: Dictionary = amount_variant
		if str(amount.get("resource_id", "")) == resource_id:
			return int(amount.get("milliunits", 0))
	return 0


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
