extends Node

const EMPIRE_ID := "empire_builder"
const SYSTEM_ID := "sys_alpha"
const GALAXY_SEED := 7


func _ready() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Resource collector economy smoke test passed.")
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

	var body := _fixed_deposit_body()
	EconomyManager.sync_system_sources(SYSTEM_ID, EMPIRE_ID, [body], GALAXY_SEED, [], [], 10000)
	_expect(EconomyManager.get_projected_monthly_net(EMPIRE_ID, "matter") == 0, "deposit body should not produce before a collector exists", failures)

	var station := SpaceManager.spawn_unit(SpaceManager.RESOURCE_COLLECTOR_STATION_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {
		"unit_id": "collector_alpha",
		"display_name": "Sammelstation Alpha",
		"metadata": {
			"target_body_id": "planet_deposit",
			"target_body_type": "planet",
			"target_body_name": "Deposit World",
		},
	})
	_expect(station != null, "resource collector station should spawn", failures)
	if station == null:
		_cleanup()
		return

	EconomyManager.sync_system_sources(SYSTEM_ID, EMPIRE_ID, [body], GALAXY_SEED, [], _collector_records(SYSTEM_ID), 10000)
	_expect(EconomyManager.has_source(EconomyManager.get_resource_collector_source_id(station.unit_id)), "collector should register a resource source", failures)
	_expect(EconomyManager.get_projected_monthly_net(EMPIRE_ID, "matter") == 50000, "collector should harvest fixed deposits", failures)

	var builder := SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {
		"unit_id": "builder_alpha",
		"display_name": "ISS Mason",
	})
	_expect(builder != null, "builder should spawn for duplicate collector validation", failures)
	if builder != null:
		var duplicate_options := SpaceManager.get_build_options_for_body(builder.unit_id, SYSTEM_ID, _body_context(body))
		_expect(not _options_have_class(duplicate_options, SpaceManager.RESOURCE_COLLECTOR_STATION_CLASS_ID), "completed collector should block duplicate collector options", failures)

	EconomyManager.sync_system_sources(SYSTEM_ID, EMPIRE_ID, [body], GALAXY_SEED, [], _collector_records(SYSTEM_ID), 12000)
	_expect(EconomyManager.get_projected_monthly_net(EMPIRE_ID, "matter") == 60000, "+20% collector modifier should scale harvested output", failures)

	SpaceManager.remove_unit(station.unit_id)
	_expect(not EconomyManager.has_source(EconomyManager.get_resource_collector_source_id(station.unit_id)), "removing collector should remove its resource source", failures)
	_expect(EconomyManager.get_projected_monthly_net(EMPIRE_ID, "matter") == 0, "matter income should stop after collector removal", failures)
	_cleanup()


func _cleanup() -> void:
	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()


func _fixed_deposit_body() -> Dictionary:
	return {
		"id": "planet_deposit",
		"name": "Deposit World",
		"type": "planet",
		"size": 2.0,
		"resource_deposit_component": {
			"mode": "fixed",
			"deposits": [{"resource_id": "matter", "milliunits": 50000}],
		},
		"buildable_component": {
			"body_type": "planet",
			"allowed_build_tags": ["orbital_station"],
			"max_active_projects": 1,
		},
	}


func _collector_records(system_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit_id in SpaceManager.get_unit_ids_in_system(system_id):
		var unit := SpaceManager.get_unit(unit_id)
		if unit == null or unit.class_id != SpaceManager.RESOURCE_COLLECTOR_STATION_CLASS_ID:
			continue
		result.append({
			"unit_id": unit.unit_id,
			"owner_empire_id": unit.owner_empire_id,
			"metadata": unit.metadata.duplicate(true),
		})
	return result


func _body_context(body: Dictionary) -> Dictionary:
	return {
		"system_id": SYSTEM_ID,
		"generated_seed": GALAXY_SEED,
		"body_id": str(body.get("id", "")),
		"body_type": str(body.get("type", "planet")),
		"body_name": str(body.get("name", "")),
		"local_position": Vector3(18.0, 0.0, 0.0),
		"size": float(body.get("size", 1.0)),
		"body_record": body.duplicate(true),
		"buildable_component": body.get("buildable_component", {}).duplicate(true),
	}


func _options_have_class(options: Array, class_id: String) -> bool:
	for option in options:
		if str(option.get("class_id", "")) == class_id:
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
