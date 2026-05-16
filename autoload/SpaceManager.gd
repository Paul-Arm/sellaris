extends Node

const SPACE_UNIT_CLASS_SCRIPT: Script = preload("res://core/space/SpaceUnitClass.gd")
const SPACE_UNIT_RUNTIME_SCRIPT: Script = preload("res://core/space/SpaceUnitRuntime.gd")
const SPACE_FLEET_RUNTIME_SCRIPT: Script = preload("res://core/space/SpaceFleetRuntime.gd")
const UNIT_SOURCE_PREFIX := "unit:"
const SCIENCE_SHIP_CLASS_ID := "science_ship"
const BUILDER_SHIP_CLASS_ID := "builder_ship"
const BASIC_STATION_CLASS_ID := "basic_station"
const STELLAR_STATION_CLASS_ID := "stellar_station"
const STATION_BUILD_TIME_DAYS := 60
const BUILD_TAG_ORBITAL_STATION := "orbital_station"
const BUILD_TAG_STELLAR_STATION := "stellar_station"
const BUILD_TAG_MINING_STATION := "mining_station"
const BUILD_TAG_RESEARCH_STATION := "research_station"
const CONSTRUCTION_STATE_MOVING_TO_SITE := "moving_to_site"
const CONSTRUCTION_STATE_BUILDING := "building"
const CONSTRUCTION_SITE_ARRIVAL_DISTANCE := 0.35

signal unit_class_registered(class_id: String)
signal unit_spawned(unit_id: String)
signal unit_removed(unit_id: String)
signal unit_updated(unit_id: String)
signal fleet_created(fleet_id: String)
signal fleet_removed(fleet_id: String)
signal fleet_updated(fleet_id: String)
signal construction_started(project_id: String)
signal construction_updated(project_id: String)
signal construction_completed(project_id: String, unit_id: String)
signal construction_cancelled(project_id: String)

var _next_unit_id: int = 1
var _next_fleet_id: int = 1
var _next_movement_order_id: int = 1
var _next_construction_project_id: int = 1
var _unit_classes: Dictionary = {}
var _units: Dictionary = {}
var _fleets: Dictionary = {}
var _construction_projects: Dictionary = {}
var _unit_ids_by_owner: Dictionary = {}
var _unit_ids_by_system: Dictionary = {}
var _unit_ids_by_class: Dictionary = {}
var _fleet_ids_by_owner: Dictionary = {}
var _fleet_ids_by_system: Dictionary = {}
var _construction_project_ids_by_builder_unit_id: Dictionary = {}
var _construction_project_ids_by_system: Dictionary = {}


func _ready() -> void:
	register_builtin_unit_classes()
	if SimClock != null:
		if not SimClock.day_tick.is_connected(_on_sim_day_tick):
			SimClock.day_tick.connect(_on_sim_day_tick)


func reset_runtime_state(clear_unit_classes: bool = false) -> void:
	for unit_id_variant in _units.keys():
		_remove_unit_economy_source(str(unit_id_variant))
	_next_unit_id = 1
	_next_fleet_id = 1
	_next_movement_order_id = 1
	_next_construction_project_id = 1
	_units.clear()
	_fleets.clear()
	_construction_projects.clear()
	_unit_ids_by_owner.clear()
	_unit_ids_by_system.clear()
	_unit_ids_by_class.clear()
	_fleet_ids_by_owner.clear()
	_fleet_ids_by_system.clear()
	_construction_project_ids_by_builder_unit_id.clear()
	_construction_project_ids_by_system.clear()
	if clear_unit_classes:
		_unit_classes.clear()
		register_builtin_unit_classes(true)


func register_builtin_unit_classes(overwrite_existing: bool = false) -> void:
	register_unit_class_from_data({
		"class_id": SCIENCE_SHIP_CLASS_ID,
		"display_name": "Science Ship",
		"unit_kind": SpaceUnitClass.UNIT_KIND_SHIP,
		"category": SpaceUnitClass.CATEGORY_CIVILIAN,
		"max_hull_points": 120.0,
		"default_ai_role": "science_scout",
		"command_tags": ["civilian", "science", "survey", "explore"],
		"component_slots": [
			{"slot_id": "drive", "slot_kind": "drive", "required": true},
			{"slot_id": "utility", "slot_kind": "addon", "required": false},
		],
		"upkeep_component": {
			"build_costs": {
				"alloys": 100.0,
				"energy": 50.0,
			},
			"monthly_costs": {
				"energy": 1.0,
				"alloys": 0.1,
			},
			"command_point_cost": 0.0,
		},
		"mobility_component": {
			"cruise_speed": 6.0,
			"acceleration": 6.0,
			"turn_rate_degrees": 180.0,
			"formation_radius": 2.4,
			"can_join_fleets": true,
			"uses_hyperlanes": true,
			"can_orbit_system_objects": true,
			"can_move_in_system": true,
		},
	}, overwrite_existing)
	register_unit_class_from_data({
		"class_id": BUILDER_SHIP_CLASS_ID,
		"display_name": "Builder Ship",
		"unit_kind": SpaceUnitClass.UNIT_KIND_SHIP,
		"category": SpaceUnitClass.CATEGORY_CIVILIAN,
		"max_hull_points": 180.0,
		"default_ai_role": "construction",
		"command_tags": ["civilian", "builder", "construction"],
		"component_slots": [
			{"slot_id": "drive", "slot_kind": "drive", "required": true},
			{"slot_id": "construction", "slot_kind": "construction", "required": true},
			{"slot_id": "utility", "slot_kind": "addon", "required": false},
		],
		"upkeep_component": {
			"build_costs": {
				"alloys": 120.0,
				"energy": 60.0,
			},
			"monthly_costs": {
				"energy": 1.2,
				"alloys": 0.15,
			},
			"command_point_cost": 0.0,
		},
		"mobility_component": {
			"cruise_speed": 5.0,
			"acceleration": 5.0,
			"turn_rate_degrees": 160.0,
			"formation_radius": 2.8,
			"can_join_fleets": true,
			"uses_hyperlanes": true,
			"can_orbit_system_objects": true,
			"can_move_in_system": true,
		},
		"builder_component": {
			"buildable_tags": [
				BUILD_TAG_ORBITAL_STATION,
				BUILD_TAG_STELLAR_STATION,
				BUILD_TAG_MINING_STATION,
				BUILD_TAG_RESEARCH_STATION,
			],
			"single_active_project": true,
		},
	}, overwrite_existing)
	register_unit_class_from_data({
		"class_id": BASIC_STATION_CLASS_ID,
		"display_name": "Station",
		"unit_kind": SpaceUnitClass.UNIT_KIND_STATION,
		"category": SpaceUnitClass.CATEGORY_STATION,
		"max_hull_points": 1800.0,
		"default_ai_role": "system_anchor",
		"command_tags": ["station", "buildable"],
		"upkeep_component": {
			"build_costs": {
				"alloys": 240.0,
				"energy": 100.0,
			},
			"monthly_costs": {
				"energy": 3.0,
				"alloys": 0.4,
			},
			"command_point_cost": 0.0,
		},
		"buildable_component": {
			"build_time_days": STATION_BUILD_TIME_DAYS,
			"buildable_by_builder_ships": true,
			"build_tags": [BUILD_TAG_ORBITAL_STATION],
		},
	}, overwrite_existing)
	register_unit_class_from_data({
		"class_id": STELLAR_STATION_CLASS_ID,
		"display_name": "Stellar Station",
		"unit_kind": SpaceUnitClass.UNIT_KIND_STATION,
		"category": SpaceUnitClass.CATEGORY_STATION,
		"max_hull_points": 2200.0,
		"default_ai_role": "stellar_anchor",
		"command_tags": ["station", "stellar", "buildable"],
		"upkeep_component": {
			"build_costs": {
				"alloys": 300.0,
				"energy": 140.0,
			},
			"monthly_costs": {
				"energy": 4.0,
				"alloys": 0.5,
			},
			"command_point_cost": 0.0,
		},
		"buildable_component": {
			"build_time_days": STATION_BUILD_TIME_DAYS,
			"buildable_by_builder_ships": true,
			"build_tags": [BUILD_TAG_STELLAR_STATION],
		},
	}, overwrite_existing)


func register_unit_class(unit_class: SpaceUnitClass, overwrite_existing: bool = false) -> bool:
	if unit_class == null:
		return false

	unit_class.ensure_defaults()
	if unit_class.class_id.is_empty():
		return false
	if _unit_classes.has(unit_class.class_id) and not overwrite_existing:
		return false

	_unit_classes[unit_class.class_id] = unit_class
	if overwrite_existing:
		_rebuild_indexes_and_economy_sources()
	unit_class_registered.emit(unit_class.class_id)
	return true


func register_unit_class_from_data(class_data: Dictionary, overwrite_existing: bool = false) -> bool:
	var unit_class := SPACE_UNIT_CLASS_SCRIPT.from_dict(class_data) as SpaceUnitClass
	if unit_class == null:
		return false
	return register_unit_class(unit_class, overwrite_existing)


func unregister_unit_class(class_id: String) -> bool:
	if class_id.is_empty() or not _unit_classes.has(class_id):
		return false
	if _unit_ids_by_class.has(class_id):
		return false
	_unit_classes.erase(class_id)
	return true


func has_unit_class(class_id: String) -> bool:
	return _unit_classes.has(class_id)


func get_unit_class(class_id: String) -> SpaceUnitClass:
	return _unit_classes.get(class_id, null)


func get_all_unit_classes() -> Array[SpaceUnitClass]:
	var result: Array[SpaceUnitClass] = []
	for unit_class_variant in _unit_classes.values():
		var unit_class: SpaceUnitClass = unit_class_variant
		result.append(unit_class)
	return result


func spawn_unit(class_id: String, owner_empire_id: String, system_id: String, spawn_data: Dictionary = {}) -> SpaceUnitRuntime:
	var unit_class := get_unit_class(class_id)
	if unit_class == null:
		return null

	unit_class.ensure_defaults()
	if unit_class.ownership_component != null and unit_class.ownership_component.requires_owner and owner_empire_id.is_empty():
		return null

	var unit_id: String = str(spawn_data.get("unit_id", spawn_data.get("ship_id", "")))
	if unit_id.is_empty():
		unit_id = _generate_unit_id()
	if _units.has(unit_id):
		return null

	var controller_kind: String = str(spawn_data.get("controller_kind", SpaceUnitOwnershipComponent.CONTROLLER_UNASSIGNED))
	if unit_class.ownership_component != null and not unit_class.ownership_component.supports_controller(controller_kind):
		controller_kind = SpaceUnitOwnershipComponent.CONTROLLER_UNASSIGNED

	var day_serial := _get_current_day_serial()
	var local_position := SpaceUnitRuntime._variant_to_vector3(spawn_data.get(
		"local_position",
		_resolve_spawn_position(system_id, unit_id, unit_class)
	))

	var unit := SPACE_UNIT_RUNTIME_SCRIPT.new() as SpaceUnitRuntime
	unit.unit_id = unit_id
	unit.class_id = unit_class.class_id
	unit.display_name = str(spawn_data.get("display_name", unit_class.display_name))
	unit.owner_empire_id = owner_empire_id
	unit.controller_kind = controller_kind
	unit.controller_peer_id = int(spawn_data.get("controller_peer_id", 0))
	unit.ai_role = StringName(str(spawn_data.get("ai_role", str(unit_class.default_ai_role))))
	unit.current_system_id = system_id
	unit.destination_system_id = str(spawn_data.get("destination_system_id", ""))
	unit.eta_days_remaining = maxi(int(spawn_data.get("eta_days_remaining", 0)), 0)
	unit.max_hull_points = unit_class.max_hull_points
	unit.current_hull_points = clampf(float(spawn_data.get("current_hull_points", unit.max_hull_points)), 0.0, unit.max_hull_points)
	unit.capability_mask = unit_class.get_capability_mask()
	unit.command_tags = unit_class.command_tags.duplicate()
	unit.metadata = _sanitize_dictionary(spawn_data.get("metadata", unit_class.metadata))
	unit.set_local_position(local_position, day_serial)

	_units[unit_id] = unit
	_add_to_index(_unit_ids_by_owner, owner_empire_id, unit_id)
	_add_to_index(_unit_ids_by_system, system_id, unit_id)
	_add_to_index(_unit_ids_by_class, unit.class_id, unit_id)
	_sync_unit_economy_source(unit)
	if unit_class.has_colony_host() and bool(unit_class.colony_host_component.get("auto_create_colony")):
		ColonyManager.create_colony_for_space_unit(unit.unit_id)
	unit_spawned.emit(unit_id)
	return unit


func remove_unit(unit_id: String) -> bool:
	var unit := get_unit(unit_id)
	if unit == null:
		return false

	cancel_build_order_for_builder(unit_id)
	if not unit.fleet_id.is_empty():
		remove_unit_from_fleet(unit_id)

	_remove_from_index(_unit_ids_by_owner, unit.owner_empire_id, unit_id)
	_remove_from_index(_unit_ids_by_system, unit.current_system_id, unit_id)
	_remove_from_index(_unit_ids_by_class, unit.class_id, unit_id)
	_remove_unit_economy_source(unit_id)
	var hosted_colony_id := ColonyManager.get_colony_id_for_host(ColonyRuntime.HOST_KIND_SPACE_UNIT, unit_id)
	if not hosted_colony_id.is_empty():
		ColonyManager.remove_colony(hosted_colony_id)
	_units.erase(unit_id)
	unit_removed.emit(unit_id)
	return true


func get_unit(unit_id: String) -> SpaceUnitRuntime:
	return _units.get(unit_id, null)


func get_unit_ids_for_owner(empire_id: String) -> PackedStringArray:
	return _get_index_values(_unit_ids_by_owner, empire_id)


func get_unit_ids_in_system(system_id: String) -> PackedStringArray:
	return _get_index_values(_unit_ids_by_system, system_id)


func get_unit_ids_of_class(class_id: String) -> PackedStringArray:
	return _get_index_values(_unit_ids_by_class, class_id)


func get_owner_monthly_upkeep(empire_id: String) -> Dictionary:
	var totals: Dictionary = {}
	for unit_id in get_unit_ids_for_owner(empire_id):
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		var unit_class := get_unit_class(unit.class_id)
		if unit_class == null:
			continue
		_merge_amount_defs_into_map(totals, unit_class.get_monthly_upkeep())
	return totals


func issue_build_order(builder_unit_id: String, build_class_id: String, build_data: Dictionary = {}) -> String:
	var builder := get_unit(builder_unit_id)
	if builder == null or not builder.can_build_units():
		return ""
	if not builder.fleet_id.is_empty():
		return ""

	var builder_class := get_unit_class(builder.class_id)
	var build_class := get_unit_class(build_class_id)
	if builder_class == null or build_class == null:
		return ""
	builder_class.ensure_defaults()
	build_class.ensure_defaults()
	if not build_class.can_builder_construct(builder_class):
		return ""

	if builder_class.builder_component != null and bool(builder_class.builder_component.get("single_active_project")):
		if is_unit_constructing(builder_unit_id):
			return ""

	var project_id: String = str(build_data.get("project_id", "")).strip_edges()
	if project_id.is_empty():
		project_id = _generate_construction_project_id()
	if _construction_projects.has(project_id):
		return ""

	var build_position := _resolve_build_site_position(builder, build_class, build_data)
	var construction_state := CONSTRUCTION_STATE_MOVING_TO_SITE
	if builder.local_position.distance_to(build_position) <= CONSTRUCTION_SITE_ARRIVAL_DISTANCE:
		construction_state = CONSTRUCTION_STATE_BUILDING
	if construction_state == CONSTRUCTION_STATE_MOVING_TO_SITE and not builder.is_mobile():
		return ""

	if bool(build_data.get("commit_cost", false)):
		if EconomyManager == null or not EconomyManager.commit_cost(builder.owner_empire_id, build_class.get_build_costs()):
			return ""

	var build_time_days := maxi(int(build_data.get("build_time_days", build_class.get_build_time_days())), 1)
	var project := {
		"project_id": project_id,
		"builder_unit_id": builder.unit_id,
		"build_class_id": build_class.class_id,
		"display_name": str(build_data.get("display_name", build_class.display_name)).strip_edges(),
		"owner_empire_id": builder.owner_empire_id,
		"system_id": builder.current_system_id,
		"days_total": build_time_days,
		"days_remaining": build_time_days,
		"construction_state": construction_state,
		"local_position": build_position,
		"target_body_id": str(build_data.get("target_body_id", "")),
		"target_body_type": str(build_data.get("target_body_type", "")),
		"target_body_name": str(build_data.get("target_body_name", "")),
		"started_day_serial": _get_current_day_serial(),
		"build_started_day_serial": _get_current_day_serial() if construction_state == CONSTRUCTION_STATE_BUILDING else 0,
		"command_revision": 0,
		"metadata": _sanitize_dictionary(build_data.get("metadata", {})),
	}
	if str(project.get("display_name", "")).is_empty():
		project["display_name"] = build_class.display_name

	_construction_projects[project_id] = project
	_add_to_index(_construction_project_ids_by_builder_unit_id, builder.unit_id, project_id)
	_add_to_index(_construction_project_ids_by_system, builder.current_system_id, project_id)
	_set_builder_project_metadata(builder, project_id)
	if construction_state == CONSTRUCTION_STATE_MOVING_TO_SITE:
		_move_builder_to_construction_site(builder, build_position)
	else:
		_stop_unit_for_construction(builder)
	builder.command_revision += 1
	unit_updated.emit(builder.unit_id)
	construction_started.emit(project_id)
	return project_id


func request_build_order(builder_unit_id: String, build_class_id: String, build_data: Dictionary = {}) -> String:
	return issue_build_order(builder_unit_id, build_class_id, build_data)


func request_build_station(builder_unit_id: String, build_data: Dictionary = {}) -> String:
	return issue_build_order(builder_unit_id, BASIC_STATION_CLASS_ID, build_data)


func cancel_build_order(project_id: String) -> bool:
	return _remove_construction_project(project_id, true)


func cancel_build_order_for_builder(builder_unit_id: String) -> bool:
	var project_ids := _get_index_values(_construction_project_ids_by_builder_unit_id, builder_unit_id)
	var changed := false
	for project_id in project_ids:
		changed = _remove_construction_project(project_id, true) or changed
	return changed


func get_construction_project(project_id: String) -> Dictionary:
	var project: Dictionary = _construction_projects.get(project_id, {})
	return project.duplicate(true)


func get_construction_project_for_builder(builder_unit_id: String) -> Dictionary:
	var project_ids := _get_index_values(_construction_project_ids_by_builder_unit_id, builder_unit_id)
	if project_ids.is_empty():
		return {}
	return get_construction_project(project_ids[0])


func get_construction_project_ids_in_system(system_id: String) -> PackedStringArray:
	return _get_index_values(_construction_project_ids_by_system, system_id)


func get_all_construction_projects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for project_variant in _construction_projects.values():
		var project: Dictionary = project_variant
		result.append(project.duplicate(true))
	return result


func is_unit_constructing(unit_id: String) -> bool:
	return not _get_index_values(_construction_project_ids_by_builder_unit_id, unit_id).is_empty()


func get_buildable_class_ids_for_builder(builder_unit_id: String) -> PackedStringArray:
	var result := PackedStringArray()
	var builder := get_unit(builder_unit_id)
	if builder == null:
		return result
	var builder_class := get_unit_class(builder.class_id)
	if builder_class == null or builder_class.builder_component == null:
		return result
	for unit_class_variant in _unit_classes.values():
		var candidate: SpaceUnitClass = unit_class_variant
		if candidate == null or not candidate.is_buildable():
			continue
		if candidate.can_builder_construct(builder_class):
			result.append(candidate.class_id)
	return result


func get_build_options_for_body(builder_unit_id: String, system_id: String, body_context: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var builder := get_unit(builder_unit_id)
	if builder == null or not builder.can_build_units():
		return result
	if builder.current_system_id != system_id or is_unit_constructing(builder_unit_id):
		return result
	var builder_class := get_unit_class(builder.class_id)
	if builder_class == null or builder_class.builder_component == null:
		return result

	var normalized_body := _normalize_build_body_context(system_id, body_context)
	if normalized_body.is_empty() or _is_body_project_limit_reached(normalized_body):
		return result
	var allowed_tags: PackedStringArray = normalized_body.get("allowed_build_tags", PackedStringArray())
	if allowed_tags.is_empty():
		return result

	for unit_class_variant in _unit_classes.values():
		var candidate: SpaceUnitClass = unit_class_variant
		if candidate == null or not candidate.is_buildable():
			continue
		if not candidate.can_builder_construct(builder_class):
			continue
		var candidate_tags := candidate.get_build_tags()
		if not _string_arrays_intersect(candidate_tags, allowed_tags):
			continue
		result.append({
			"class_id": candidate.class_id,
			"display_name": candidate.display_name,
			"unit_kind": candidate.unit_kind,
			"category": candidate.category,
			"build_time_days": candidate.get_build_time_days(),
			"build_tags": candidate_tags.duplicate(),
			"build_costs": ResourceAmountDef.to_dict_array(candidate.get_build_costs()),
			"target_body_id": str(normalized_body.get("body_id", "")),
			"target_body_type": str(normalized_body.get("body_type", "")),
			"target_body_name": str(normalized_body.get("body_name", "")),
		})

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var name_a := str(a.get("display_name", a.get("class_id", "")))
		var name_b := str(b.get("display_name", b.get("class_id", "")))
		if name_a == name_b:
			return str(a.get("class_id", "")) < str(b.get("class_id", ""))
		return name_a < name_b
	)
	return result


func request_build_order_for_body(
	builder_unit_id: String,
	system_id: String,
	body_context: Dictionary,
	build_class_id: String,
	options: Dictionary = {}
) -> String:
	var build_options := get_build_options_for_body(builder_unit_id, system_id, body_context)
	var selected_option: Dictionary = {}
	for option in build_options:
		if str(option.get("class_id", "")) == build_class_id:
			selected_option = option
			break
	if selected_option.is_empty():
		return ""

	var normalized_body := _normalize_build_body_context(system_id, body_context)
	if normalized_body.is_empty():
		return ""
	var build_data := options.duplicate(true)
	build_data["target_body_id"] = str(normalized_body.get("body_id", ""))
	build_data["target_body_type"] = str(normalized_body.get("body_type", ""))
	build_data["target_body_name"] = str(normalized_body.get("body_name", ""))
	if not build_data.has("local_position"):
		build_data["local_position"] = _resolve_body_build_site_position(builder_unit_id, build_class_id, normalized_body)
	if not build_data.has("display_name"):
		build_data["display_name"] = selected_option.get("display_name", build_class_id)
	var metadata := _sanitize_dictionary(build_data.get("metadata", {}))
	metadata["target_body_id"] = build_data["target_body_id"]
	metadata["target_body_type"] = build_data["target_body_type"]
	metadata["target_body_name"] = build_data["target_body_name"]
	build_data["metadata"] = metadata
	return issue_build_order(builder_unit_id, build_class_id, build_data)


func set_unit_owner(
	unit_id: String,
	owner_empire_id: String,
	controller_kind: String = SpaceUnitOwnershipComponent.CONTROLLER_UNASSIGNED,
	controller_peer_id: int = 0
) -> bool:
	var unit := get_unit(unit_id)
	if unit == null:
		return false

	var unit_class := get_unit_class(unit.class_id)
	if unit_class == null:
		return false
	if unit_class.ownership_component != null and unit_class.ownership_component.requires_owner and owner_empire_id.is_empty():
		return false
	if unit_class.ownership_component != null and not unit_class.ownership_component.supports_controller(controller_kind):
		return false

	var changed := false
	if unit.owner_empire_id != owner_empire_id:
		_remove_from_index(_unit_ids_by_owner, unit.owner_empire_id, unit_id)
		unit.owner_empire_id = owner_empire_id
		_add_to_index(_unit_ids_by_owner, unit.owner_empire_id, unit_id)
		_sync_unit_economy_source(unit)
		ColonyManager.sync_colony_host_for_space_unit(unit.unit_id)
		_sync_construction_project_for_builder(unit)
		changed = true

	if unit.controller_kind != controller_kind:
		unit.controller_kind = controller_kind
		changed = true
	if unit.controller_peer_id != controller_peer_id:
		unit.controller_peer_id = controller_peer_id
		changed = true

	if changed:
		unit.command_revision += 1
		if not unit.fleet_id.is_empty():
			if unit_class.ownership_component == null or unit_class.ownership_component.transfer_clears_fleet_assignment:
				remove_unit_from_fleet(unit_id)
			else:
				var fleet := get_fleet(unit.fleet_id)
				if fleet != null and fleet.owner_empire_id != owner_empire_id:
					remove_unit_from_fleet(unit_id)
		unit_updated.emit(unit_id)

	return changed


func set_unit_system(unit_id: String, system_id: String) -> bool:
	var unit := get_unit(unit_id)
	if unit == null or not unit.fleet_id.is_empty():
		return false
	if is_unit_constructing(unit_id):
		return false
	if unit.current_system_id == system_id:
		return false

	_remove_from_index(_unit_ids_by_system, unit.current_system_id, unit_id)
	unit.current_system_id = system_id
	unit.destination_system_id = ""
	unit.eta_days_remaining = 0
	unit.command_revision += 1
	_add_to_index(_unit_ids_by_system, unit.current_system_id, unit_id)
	ColonyManager.sync_colony_host_for_space_unit(unit.unit_id)
	unit_updated.emit(unit_id)
	return true


func issue_unit_hyperlane_move(unit_id: String, destination_system_id: String, eta_days: int = 1) -> bool:
	var unit := get_unit(unit_id)
	if unit == null or not unit.fleet_id.is_empty() or not unit.is_mobile():
		return false
	if is_unit_constructing(unit_id):
		return false
	if destination_system_id.is_empty():
		return false
	if not _unit_uses_hyperlanes(unit):
		return false
	if unit.current_system_id == destination_system_id:
		return clear_unit_hyperlane_move(unit_id)

	unit.previous_local_position = unit.local_position
	unit.target_local_position = unit.local_position
	unit.velocity = Vector3.ZERO
	unit.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
	unit.destination_system_id = destination_system_id
	unit.eta_days_remaining = maxi(eta_days, 1)
	unit.command_revision += 1
	unit_updated.emit(unit_id)
	return true


func clear_unit_hyperlane_move(unit_id: String) -> bool:
	var unit := get_unit(unit_id)
	if unit == null:
		return false
	var changed := not unit.destination_system_id.is_empty() or unit.eta_days_remaining > 0
	unit.destination_system_id = ""
	unit.eta_days_remaining = 0
	if changed:
		unit.command_revision += 1
		unit_updated.emit(unit_id)
	return changed


func issue_unit_move(unit_id: String, target_position: Vector3) -> bool:
	var unit := get_unit(unit_id)
	if unit == null or not unit.fleet_id.is_empty() or not unit.is_mobile():
		return false
	if is_unit_constructing(unit_id):
		return false
	var unit_class := get_unit_class(unit.class_id)
	if unit_class == null or unit_class.get_in_system_speed() <= 0.0:
		return false
	if unit.local_position.is_equal_approx(target_position):
		return clear_unit_move(unit_id)

	unit.previous_local_position = unit.local_position
	unit.target_local_position = target_position
	unit.velocity = (target_position - unit.local_position).normalized() * unit_class.get_in_system_speed()
	unit.movement_state = SpaceUnitRuntime.MOVEMENT_MOVING
	unit.movement_order_id = _generate_movement_order_id()
	unit.last_movement_day_serial = _get_current_day_serial()
	unit.command_revision += 1
	unit_updated.emit(unit_id)
	return true


func clear_unit_move(unit_id: String) -> bool:
	var unit := get_unit(unit_id)
	if unit == null:
		return false
	var changed := unit.has_active_movement() or unit.velocity.length_squared() > 0.0
	unit.previous_local_position = unit.local_position
	unit.target_local_position = unit.local_position
	unit.velocity = Vector3.ZERO
	unit.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
	unit.last_movement_day_serial = _get_current_day_serial()
	if changed:
		unit.command_revision += 1
		unit_updated.emit(unit_id)
	return changed


func create_fleet(owner_empire_id: String, system_id: String, unit_ids_variant: Variant = PackedStringArray(), fleet_data: Dictionary = {}) -> SpaceFleetRuntime:
	var generated_fleet_index := _next_fleet_id
	var fleet_id: String = str(fleet_data.get("fleet_id", ""))
	if fleet_id.is_empty():
		fleet_id = _generate_fleet_id()
	if _fleets.has(fleet_id):
		return null

	var fleet := SPACE_FLEET_RUNTIME_SCRIPT.new() as SpaceFleetRuntime
	fleet.fleet_id = fleet_id
	fleet.display_name = str(fleet_data.get("display_name", "Fleet %03d" % generated_fleet_index))
	fleet.owner_empire_id = owner_empire_id
	fleet.controller_kind = str(fleet_data.get("controller_kind", SpaceUnitOwnershipComponent.CONTROLLER_UNASSIGNED))
	fleet.controller_peer_id = int(fleet_data.get("controller_peer_id", 0))
	fleet.ai_role = StringName(str(fleet_data.get("ai_role", "")))
	fleet.current_system_id = system_id
	fleet.destination_system_id = str(fleet_data.get("destination_system_id", ""))
	fleet.eta_days_remaining = maxi(int(fleet_data.get("eta_days_remaining", 0)), 0)
	fleet.home_system_id = str(fleet_data.get("home_system_id", system_id))
	fleet.local_position = SpaceUnitRuntime._variant_to_vector3(fleet_data.get("local_position", Vector3.ZERO))
	fleet.previous_local_position = fleet.local_position
	fleet.target_local_position = fleet.local_position
	fleet.last_movement_day_serial = _get_current_day_serial()
	fleet.metadata = _sanitize_dictionary(fleet_data.get("metadata", {}))

	_fleets[fleet_id] = fleet
	_add_to_index(_fleet_ids_by_owner, owner_empire_id, fleet_id)
	_add_to_index(_fleet_ids_by_system, system_id, fleet_id)

	for unit_id_variant in _variant_to_packed_string_array(unit_ids_variant):
		add_unit_to_fleet(str(unit_id_variant), fleet_id)

	if not bool(fleet_data.has("local_position")):
		_sync_fleet_center_from_members(fleet)

	fleet_created.emit(fleet_id)
	return fleet


func get_fleet(fleet_id: String) -> SpaceFleetRuntime:
	return _fleets.get(fleet_id, null)


func get_fleet_ids_for_owner(empire_id: String) -> PackedStringArray:
	return _get_index_values(_fleet_ids_by_owner, empire_id)


func get_fleet_ids_in_system(system_id: String) -> PackedStringArray:
	return _get_index_values(_fleet_ids_by_system, system_id)


func add_unit_to_fleet(unit_id: String, fleet_id: String) -> bool:
	var unit := get_unit(unit_id)
	var fleet := get_fleet(fleet_id)
	if unit == null or fleet == null:
		return false
	if not unit.can_join_fleet():
		return false
	if is_unit_constructing(unit_id):
		return false
	if unit.owner_empire_id != fleet.owner_empire_id:
		return false
	if unit.current_system_id != fleet.current_system_id:
		return false
	if unit.fleet_id == fleet_id:
		return false

	if not unit.fleet_id.is_empty():
		remove_unit_from_fleet(unit_id)

	if not fleet.add_unit(unit_id):
		return false

	unit.fleet_id = fleet_id
	unit.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
	unit.velocity = Vector3.ZERO
	unit.command_revision += 1
	_sync_fleet_center_from_members(fleet)
	unit_updated.emit(unit_id)
	fleet_updated.emit(fleet_id)
	return true


func remove_unit_from_fleet(unit_id: String) -> bool:
	var unit := get_unit(unit_id)
	if unit == null or unit.fleet_id.is_empty():
		return false

	var fleet_id := unit.fleet_id
	var fleet := get_fleet(fleet_id)
	unit.clear_fleet_assignment()
	unit.command_revision += 1
	unit_updated.emit(unit_id)

	if fleet == null:
		return true
	if not fleet.remove_unit(unit_id):
		return true
	if fleet.is_empty():
		disband_fleet(fleet_id)
		return true

	_sync_fleet_center_from_members(fleet)
	fleet_updated.emit(fleet_id)
	return true


func disband_fleet(fleet_id: String) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null:
		return false

	var unit_ids: PackedStringArray = fleet.unit_ids.duplicate()
	for unit_id in unit_ids:
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		unit.clear_fleet_assignment()
		unit.command_revision += 1
		unit_updated.emit(unit_id)

	_remove_from_index(_fleet_ids_by_owner, fleet.owner_empire_id, fleet_id)
	_remove_from_index(_fleet_ids_by_system, fleet.current_system_id, fleet_id)
	_fleets.erase(fleet_id)
	fleet_removed.emit(fleet_id)
	return true


func set_fleet_system(fleet_id: String, system_id: String) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null:
		return false
	if fleet.current_system_id == system_id and fleet.destination_system_id.is_empty():
		return false

	_remove_from_index(_fleet_ids_by_system, fleet.current_system_id, fleet_id)
	fleet.current_system_id = system_id
	fleet.destination_system_id = ""
	fleet.eta_days_remaining = 0
	fleet.command_revision += 1
	_add_to_index(_fleet_ids_by_system, system_id, fleet_id)

	for unit_id in fleet.unit_ids:
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		_remove_from_index(_unit_ids_by_system, unit.current_system_id, unit.unit_id)
		unit.current_system_id = system_id
		unit.destination_system_id = ""
		unit.eta_days_remaining = 0
		unit.command_revision += 1
		_add_to_index(_unit_ids_by_system, unit.current_system_id, unit.unit_id)
		ColonyManager.sync_colony_host_for_space_unit(unit.unit_id)
		unit_updated.emit(unit.unit_id)

	fleet_updated.emit(fleet_id)
	return true


func set_fleet_destination(fleet_id: String, destination_system_id: String, eta_days: int = 0) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null:
		return false
	if fleet.destination_system_id == destination_system_id and fleet.eta_days_remaining == maxi(eta_days, 0):
		return false

	fleet.destination_system_id = destination_system_id
	fleet.eta_days_remaining = maxi(eta_days, 0)
	fleet.command_revision += 1

	for unit_id in fleet.unit_ids:
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		unit.destination_system_id = destination_system_id
		unit.eta_days_remaining = fleet.eta_days_remaining
		unit.command_revision += 1
		unit_updated.emit(unit_id)

	fleet_updated.emit(fleet_id)
	return true


func issue_fleet_hyperlane_move(fleet_id: String, destination_system_id: String, eta_days: int = 1) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null or fleet.unit_ids.is_empty():
		return false
	if destination_system_id.is_empty():
		return false
	if not _fleet_uses_hyperlanes(fleet):
		return false
	if fleet.current_system_id == destination_system_id:
		return clear_fleet_hyperlane_move(fleet_id)

	fleet.previous_local_position = fleet.local_position
	fleet.target_local_position = fleet.local_position
	fleet.velocity = Vector3.ZERO
	fleet.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
	fleet.destination_system_id = destination_system_id
	fleet.eta_days_remaining = maxi(eta_days, 1)
	fleet.command_revision += 1

	for unit_id in fleet.unit_ids:
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		unit.previous_local_position = unit.local_position
		unit.target_local_position = unit.local_position
		unit.velocity = Vector3.ZERO
		unit.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
		unit.destination_system_id = destination_system_id
		unit.eta_days_remaining = fleet.eta_days_remaining
		unit.command_revision += 1
		unit_updated.emit(unit_id)

	fleet_updated.emit(fleet_id)
	return true


func clear_fleet_hyperlane_move(fleet_id: String) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null:
		return false
	var changed := not fleet.destination_system_id.is_empty() or fleet.eta_days_remaining > 0
	fleet.destination_system_id = ""
	fleet.eta_days_remaining = 0
	for unit_id in fleet.unit_ids:
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		unit.destination_system_id = ""
		unit.eta_days_remaining = 0
		unit.command_revision += 1
		unit_updated.emit(unit_id)
	if changed:
		fleet.command_revision += 1
		fleet_updated.emit(fleet_id)
	return changed


func issue_fleet_move(fleet_id: String, target_position: Vector3) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null or fleet.unit_ids.is_empty():
		return false
	var fleet_speed := _get_fleet_in_system_speed(fleet)
	if fleet_speed <= 0.0:
		return false
	if fleet.local_position.is_equal_approx(target_position):
		return clear_fleet_move(fleet_id)

	fleet.previous_local_position = fleet.local_position
	fleet.target_local_position = target_position
	fleet.velocity = (target_position - fleet.local_position).normalized() * fleet_speed
	fleet.movement_state = SpaceUnitRuntime.MOVEMENT_MOVING
	fleet.movement_order_id = _generate_movement_order_id()
	fleet.last_movement_day_serial = _get_current_day_serial()
	fleet.command_revision += 1
	_apply_fleet_member_positions(fleet, false)
	fleet_updated.emit(fleet_id)
	return true


func clear_fleet_move(fleet_id: String) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null:
		return false
	var changed := fleet.has_active_movement() or fleet.velocity.length_squared() > 0.0
	fleet.previous_local_position = fleet.local_position
	fleet.target_local_position = fleet.local_position
	fleet.velocity = Vector3.ZERO
	fleet.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
	fleet.last_movement_day_serial = _get_current_day_serial()
	for unit_id in fleet.unit_ids:
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		unit.previous_local_position = unit.local_position
		unit.target_local_position = unit.local_position
		unit.velocity = Vector3.ZERO
		unit.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
		unit.last_movement_day_serial = fleet.last_movement_day_serial
		unit.command_revision += 1
		unit_updated.emit(unit_id)
	if changed:
		fleet.command_revision += 1
		fleet_updated.emit(fleet_id)
	return changed


func queue_fleet_command(fleet_id: String, command: Dictionary) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null:
		return false
	fleet.command_queue.append(command.duplicate(true))
	fleet.command_revision += 1
	fleet_updated.emit(fleet_id)
	return true


func clear_fleet_commands(fleet_id: String) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null or fleet.command_queue.is_empty():
		return false
	fleet.command_queue.clear()
	fleet.command_revision += 1
	fleet_updated.emit(fleet_id)
	return true


func build_system_presence(system_id: String) -> Dictionary:
	var presence := {
		"system_id": system_id,
		"unit_count": 0,
		"mobile_unit_count": 0,
		"station_count": 0,
		"construction_project_count": 0,
		"fleet_count": 0,
		"owner_breakdown": {},
	}

	for unit_id in get_unit_ids_in_system(system_id):
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		presence["unit_count"] = int(presence.get("unit_count", 0)) + 1
		if unit.is_mobile():
			presence["mobile_unit_count"] = int(presence.get("mobile_unit_count", 0)) + 1
		else:
			presence["station_count"] = int(presence.get("station_count", 0)) + 1

		var owner_breakdown: Dictionary = presence.get("owner_breakdown", {})
		var owner_entry: Dictionary = owner_breakdown.get(unit.owner_empire_id, {
			"unit_count": 0,
			"mobile_unit_count": 0,
			"station_count": 0,
			"construction_project_count": 0,
			"fleet_count": 0,
		})
		owner_entry["unit_count"] = int(owner_entry.get("unit_count", 0)) + 1
		if unit.is_mobile():
			owner_entry["mobile_unit_count"] = int(owner_entry.get("mobile_unit_count", 0)) + 1
		else:
			owner_entry["station_count"] = int(owner_entry.get("station_count", 0)) + 1
		owner_breakdown[unit.owner_empire_id] = owner_entry
		presence["owner_breakdown"] = owner_breakdown

	for fleet_id in get_fleet_ids_in_system(system_id):
		var fleet := get_fleet(fleet_id)
		if fleet == null:
			continue
		presence["fleet_count"] = int(presence.get("fleet_count", 0)) + 1
		var owner_breakdown: Dictionary = presence.get("owner_breakdown", {})
		var owner_entry: Dictionary = owner_breakdown.get(fleet.owner_empire_id, {
			"unit_count": 0,
			"mobile_unit_count": 0,
			"station_count": 0,
			"construction_project_count": 0,
			"fleet_count": 0,
		})
		owner_entry["fleet_count"] = int(owner_entry.get("fleet_count", 0)) + 1
		owner_breakdown[fleet.owner_empire_id] = owner_entry
		presence["owner_breakdown"] = owner_breakdown

	for project_id in get_construction_project_ids_in_system(system_id):
		var project := get_construction_project(project_id)
		if project.is_empty():
			continue
		presence["construction_project_count"] = int(presence.get("construction_project_count", 0)) + 1
		var owner_breakdown: Dictionary = presence.get("owner_breakdown", {})
		var owner_id := str(project.get("owner_empire_id", ""))
		var owner_entry: Dictionary = owner_breakdown.get(owner_id, {
			"unit_count": 0,
			"mobile_unit_count": 0,
			"station_count": 0,
			"construction_project_count": 0,
			"fleet_count": 0,
		})
		owner_entry["construction_project_count"] = int(owner_entry.get("construction_project_count", 0)) + 1
		owner_breakdown[owner_id] = owner_entry
		presence["owner_breakdown"] = owner_breakdown

	return presence


func build_system_renderables(system_id: String) -> Dictionary:
	var renderables := {
		"system_id": system_id,
		"units": [],
		"fleets": [],
		"construction_projects": [],
	}
	var unit_entries: Array[Dictionary] = []
	var fleet_entries: Array[Dictionary] = []
	var construction_entries: Array[Dictionary] = []
	var day_progress := SimClock.get_day_progress() if SimClock != null and SimClock.has_method("get_day_progress") else 1.0

	for unit_id in get_unit_ids_in_system(system_id):
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		var unit_class := get_unit_class(unit.class_id)
		unit_entries.append({
			"unit_id": unit.unit_id,
			"display_name": unit.display_name,
			"owner_empire_id": unit.owner_empire_id,
			"class_id": unit.class_id,
			"class_display_name": unit_class.display_name if unit_class != null else unit.class_id,
			"unit_kind": unit_class.unit_kind if unit_class != null else SpaceUnitClass.UNIT_KIND_SHIP,
			"class_category": unit_class.category if unit_class != null else "",
			"can_host_colony": unit.can_host_colony(),
			"hosted_colony_id": ColonyManager.get_colony_id_for_host(ColonyRuntime.HOST_KIND_SPACE_UNIT, unit.unit_id) if unit.can_host_colony() else "",
			"can_build_units": unit.can_build_units(),
			"construction_project_id": _get_active_construction_project_id(unit.unit_id),
			"fleet_id": unit.fleet_id,
			"ai_role": str(unit.ai_role),
			"is_mobile": unit.is_mobile(),
			"is_stationary": unit.is_stationary(),
			"hull_ratio": unit.get_hull_ratio(),
			"current_hull_points": unit.current_hull_points,
			"max_hull_points": unit.max_hull_points,
			"current_system_id": unit.current_system_id,
			"destination_system_id": unit.destination_system_id,
			"eta_days_remaining": unit.eta_days_remaining,
			"controller_kind": unit.controller_kind,
			"controller_peer_id": unit.controller_peer_id,
			"command_revision": unit.command_revision,
			"command_tags": unit.command_tags.duplicate(),
			"local_position": unit.local_position,
			"previous_local_position": unit.previous_local_position,
			"target_local_position": unit.target_local_position,
			"interpolated_local_position": unit.get_interpolated_local_position(day_progress),
			"velocity": unit.velocity,
			"movement_state": unit.movement_state,
			"movement_order_id": unit.movement_order_id,
			"last_movement_day_serial": unit.last_movement_day_serial,
			"metadata": unit.metadata.duplicate(true),
		})

	for project_id in get_construction_project_ids_in_system(system_id):
		var project: Dictionary = _construction_projects.get(project_id, {})
		if project.is_empty():
			continue
		construction_entries.append(_construction_project_to_renderable(project))

	for fleet_id in get_fleet_ids_in_system(system_id):
		var fleet := get_fleet(fleet_id)
		if fleet == null:
			continue
		fleet_entries.append({
			"fleet_id": fleet.fleet_id,
			"display_name": fleet.display_name,
			"owner_empire_id": fleet.owner_empire_id,
			"unit_count": fleet.unit_ids.size(),
			"unit_ids": fleet.unit_ids.duplicate(),
			"ai_role": str(fleet.ai_role),
			"current_system_id": fleet.current_system_id,
			"destination_system_id": fleet.destination_system_id,
			"eta_days_remaining": fleet.eta_days_remaining,
			"home_system_id": fleet.home_system_id,
			"controller_kind": fleet.controller_kind,
			"controller_peer_id": fleet.controller_peer_id,
			"command_queue_size": fleet.command_queue.size(),
			"command_revision": fleet.command_revision,
			"local_position": fleet.local_position,
			"previous_local_position": fleet.previous_local_position,
			"target_local_position": fleet.target_local_position,
			"interpolated_local_position": (
				fleet.previous_local_position.lerp(fleet.local_position, day_progress)
				if fleet.has_active_movement()
				else fleet.local_position
			),
			"velocity": fleet.velocity,
			"movement_state": fleet.movement_state,
			"movement_order_id": fleet.movement_order_id,
			"last_movement_day_serial": fleet.last_movement_day_serial,
			"metadata": fleet.metadata.duplicate(true),
		})

	renderables["units"] = unit_entries
	renderables["fleets"] = fleet_entries
	renderables["construction_projects"] = construction_entries
	return renderables


func build_owner_presence(empire_id: String) -> Dictionary:
	var presence := {
		"empire_id": empire_id,
		"unit_count": 0,
		"mobile_unit_count": 0,
		"station_count": 0,
		"construction_project_count": 0,
		"fleet_count": 0,
		"system_breakdown": {},
		"monthly_upkeep": get_owner_monthly_upkeep(empire_id),
	}

	for unit_id in get_unit_ids_for_owner(empire_id):
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		presence["unit_count"] = int(presence.get("unit_count", 0)) + 1
		var system_breakdown: Dictionary = presence.get("system_breakdown", {})
		var system_entry: Dictionary = system_breakdown.get(unit.current_system_id, {
			"unit_count": 0,
			"mobile_unit_count": 0,
			"station_count": 0,
			"construction_project_count": 0,
			"fleet_count": 0,
		})
		system_entry["unit_count"] = int(system_entry.get("unit_count", 0)) + 1
		if unit.is_mobile():
			presence["mobile_unit_count"] = int(presence.get("mobile_unit_count", 0)) + 1
			system_entry["mobile_unit_count"] = int(system_entry.get("mobile_unit_count", 0)) + 1
		else:
			presence["station_count"] = int(presence.get("station_count", 0)) + 1
			system_entry["station_count"] = int(system_entry.get("station_count", 0)) + 1
		system_breakdown[unit.current_system_id] = system_entry
		presence["system_breakdown"] = system_breakdown

	for fleet_id in get_fleet_ids_for_owner(empire_id):
		var fleet := get_fleet(fleet_id)
		if fleet == null:
			continue
		presence["fleet_count"] = int(presence.get("fleet_count", 0)) + 1
		var system_breakdown: Dictionary = presence.get("system_breakdown", {})
		var system_entry: Dictionary = system_breakdown.get(fleet.current_system_id, {
			"unit_count": 0,
			"mobile_unit_count": 0,
			"station_count": 0,
			"construction_project_count": 0,
			"fleet_count": 0,
		})
		system_entry["fleet_count"] = int(system_entry.get("fleet_count", 0)) + 1
		system_breakdown[fleet.current_system_id] = system_entry
		presence["system_breakdown"] = system_breakdown

	for project_variant in _construction_projects.values():
		var project: Dictionary = project_variant
		if str(project.get("owner_empire_id", "")) != empire_id:
			continue
		presence["construction_project_count"] = int(presence.get("construction_project_count", 0)) + 1
		var system_id := str(project.get("system_id", ""))
		var system_breakdown: Dictionary = presence.get("system_breakdown", {})
		var system_entry: Dictionary = system_breakdown.get(system_id, {
			"unit_count": 0,
			"mobile_unit_count": 0,
			"station_count": 0,
			"construction_project_count": 0,
			"fleet_count": 0,
		})
		system_entry["construction_project_count"] = int(system_entry.get("construction_project_count", 0)) + 1
		system_breakdown[system_id] = system_entry
		presence["system_breakdown"] = system_breakdown

	return presence


func build_snapshot() -> Dictionary:
	var unit_class_snapshots: Array[Dictionary] = []
	var unit_snapshots: Array[Dictionary] = []
	var fleet_snapshots: Array[Dictionary] = []
	var construction_project_snapshots: Array[Dictionary] = []

	for unit_class_variant in _unit_classes.values():
		var unit_class: SpaceUnitClass = unit_class_variant
		unit_class_snapshots.append(unit_class.to_dict())

	for unit_variant in _units.values():
		var unit: SpaceUnitRuntime = unit_variant
		unit_snapshots.append(unit.to_dict())

	for fleet_variant in _fleets.values():
		var fleet: SpaceFleetRuntime = fleet_variant
		fleet_snapshots.append(fleet.to_dict())

	for project_variant in _construction_projects.values():
		var project: Dictionary = project_variant
		construction_project_snapshots.append(_construction_project_to_snapshot(project))

	return {
		"next_unit_id": _next_unit_id,
		"next_fleet_id": _next_fleet_id,
		"next_movement_order_id": _next_movement_order_id,
		"next_construction_project_id": _next_construction_project_id,
		"space_unit_classes": unit_class_snapshots,
		"space_units": unit_snapshots,
		"fleets": fleet_snapshots,
		"construction_projects": construction_project_snapshots,
	}


func load_snapshot(snapshot: Dictionary, clear_existing_state: bool = true) -> void:
	if clear_existing_state:
		reset_runtime_state(true)

	_next_unit_id = maxi(int(snapshot.get("next_unit_id", snapshot.get("next_ship_id", 1))), 1)
	_next_fleet_id = maxi(int(snapshot.get("next_fleet_id", 1)), 1)
	_next_movement_order_id = maxi(int(snapshot.get("next_movement_order_id", 1)), 1)
	_next_construction_project_id = maxi(int(snapshot.get("next_construction_project_id", 1)), 1)

	for class_variant in snapshot.get("space_unit_classes", snapshot.get("ship_classes", [])):
		var class_data: Dictionary = class_variant
		var unit_class := SPACE_UNIT_CLASS_SCRIPT.from_dict(class_data) as SpaceUnitClass
		if unit_class == null:
			continue
		_unit_classes[unit_class.class_id] = unit_class

	for unit_variant in snapshot.get("space_units", snapshot.get("ships", [])):
		var unit_data: Dictionary = unit_variant
		var unit := SPACE_UNIT_RUNTIME_SCRIPT.from_dict(unit_data) as SpaceUnitRuntime
		if unit == null or unit.unit_id.is_empty():
			continue
		_units[unit.unit_id] = unit

	for fleet_variant in snapshot.get("fleets", []):
		var fleet_data: Dictionary = fleet_variant
		var fleet := SPACE_FLEET_RUNTIME_SCRIPT.from_dict(fleet_data) as SpaceFleetRuntime
		if fleet == null or fleet.fleet_id.is_empty():
			continue
		_fleets[fleet.fleet_id] = fleet

	for project_variant in snapshot.get("construction_projects", []):
		var project_data: Dictionary = project_variant
		var project := _construction_project_from_snapshot(project_data)
		var project_id := str(project.get("project_id", ""))
		if project_id.is_empty():
			continue
		_construction_projects[project_id] = project

	_rebuild_indexes_and_economy_sources()


func _on_sim_day_tick(_date: Dictionary) -> void:
	var day_serial := _get_current_day_serial()
	_tick_fleet_hyperlane_travel()
	_tick_unit_hyperlane_travel()
	_tick_fleet_in_system_movement(day_serial)
	_tick_independent_unit_movement(day_serial)
	_tick_construction_projects()


func _tick_fleet_hyperlane_travel() -> void:
	for fleet_variant in _fleets.values():
		var fleet: SpaceFleetRuntime = fleet_variant
		if fleet.destination_system_id.is_empty():
			continue
		if fleet.eta_days_remaining > 0:
			fleet.eta_days_remaining -= 1
		if fleet.eta_days_remaining > 0:
			for unit_id in fleet.unit_ids:
				var unit := get_unit(unit_id)
				if unit == null:
					continue
				unit.eta_days_remaining = fleet.eta_days_remaining
				unit_updated.emit(unit_id)
			fleet_updated.emit(fleet.fleet_id)
			continue
		set_fleet_system(fleet.fleet_id, fleet.destination_system_id)


func _tick_unit_hyperlane_travel() -> void:
	for unit_variant in _units.values():
		var unit: SpaceUnitRuntime = unit_variant
		if unit.destination_system_id.is_empty() or not unit.fleet_id.is_empty():
			continue
		if unit.eta_days_remaining > 0:
			unit.eta_days_remaining -= 1
		if unit.eta_days_remaining > 0:
			unit_updated.emit(unit.unit_id)
			continue
		set_unit_system(unit.unit_id, unit.destination_system_id)


func _tick_fleet_in_system_movement(day_serial: int) -> void:
	for fleet_variant in _fleets.values():
		var fleet: SpaceFleetRuntime = fleet_variant
		if not fleet.has_active_movement():
			continue
		var speed := _get_fleet_in_system_speed(fleet)
		if speed <= 0.0:
			clear_fleet_move(fleet.fleet_id)
			continue

		fleet.previous_local_position = fleet.local_position
		var offset := fleet.target_local_position - fleet.local_position
		var distance := offset.length()
		if distance <= speed or distance <= 0.001:
			fleet.local_position = fleet.target_local_position
			fleet.previous_local_position = fleet.local_position
			fleet.velocity = Vector3.ZERO
			fleet.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
		else:
			fleet.velocity = offset.normalized() * speed
			fleet.local_position += fleet.velocity
		fleet.last_movement_day_serial = day_serial
		fleet.command_revision += 1
		_apply_fleet_member_positions(fleet, true)
		fleet_updated.emit(fleet.fleet_id)


func _tick_independent_unit_movement(day_serial: int) -> void:
	for unit_variant in _units.values():
		var unit: SpaceUnitRuntime = unit_variant
		if not unit.has_active_movement() or not unit.fleet_id.is_empty():
			continue
		var unit_class := get_unit_class(unit.class_id)
		var speed := unit_class.get_in_system_speed() if unit_class != null else 0.0
		if speed <= 0.0:
			clear_unit_move(unit.unit_id)
			continue

		unit.previous_local_position = unit.local_position
		var offset := unit.target_local_position - unit.local_position
		var distance := offset.length()
		if distance <= speed or distance <= 0.001:
			unit.local_position = unit.target_local_position
			unit.previous_local_position = unit.local_position
			unit.velocity = Vector3.ZERO
			unit.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
		else:
			unit.velocity = offset.normalized() * speed
			unit.local_position += unit.velocity
		unit.last_movement_day_serial = day_serial
		unit.command_revision += 1
		unit_updated.emit(unit.unit_id)


func _tick_construction_projects() -> void:
	var project_ids := PackedStringArray()
	for project_id_variant in _construction_projects.keys():
		project_ids.append(str(project_id_variant))

	for project_id in project_ids:
		var project: Dictionary = _construction_projects.get(project_id, {})
		if project.is_empty():
			continue
		var builder := get_unit(str(project.get("builder_unit_id", "")))
		if builder == null:
			_remove_construction_project(project_id, true)
			continue

		_sync_construction_project_for_builder(builder)
		project = _construction_projects.get(project_id, project)
		if _normalize_construction_state(project.get("construction_state", CONSTRUCTION_STATE_BUILDING)) == CONSTRUCTION_STATE_MOVING_TO_SITE:
			if not _is_builder_at_construction_site(builder, project):
				continue
			_start_construction_timer(project_id, project, builder)
			continue

		project["days_remaining"] = maxi(int(project.get("days_remaining", 0)) - 1, 0)
		project["command_revision"] = int(project.get("command_revision", 0)) + 1
		_construction_projects[project_id] = project
		if int(project.get("days_remaining", 0)) <= 0:
			_complete_construction_project(project_id)
			continue
		construction_updated.emit(project_id)


func _complete_construction_project(project_id: String) -> void:
	var project: Dictionary = _construction_projects.get(project_id, {})
	if project.is_empty():
		return
	var builder := get_unit(str(project.get("builder_unit_id", "")))
	var owner_empire_id := str(project.get("owner_empire_id", ""))
	var system_id := str(project.get("system_id", ""))
	if builder != null:
		owner_empire_id = builder.owner_empire_id
		system_id = builder.current_system_id
	var build_class_id := str(project.get("build_class_id", ""))
	var unit := spawn_unit(build_class_id, owner_empire_id, system_id, {
		"display_name": str(project.get("display_name", "")),
		"local_position": SpaceUnitRuntime._variant_to_vector3(project.get("local_position", Vector3.ZERO)),
		"metadata": project.get("metadata", {}).duplicate(true) if project.get("metadata", {}) is Dictionary else {},
	})
	if unit == null:
		_remove_construction_project(project_id, true)
		return

	_remove_construction_project(project_id, false)
	if builder != null:
		builder.command_revision += 1
		unit_updated.emit(builder.unit_id)
	construction_completed.emit(project_id, unit.unit_id)


func _remove_construction_project(project_id: String, emit_cancelled: bool) -> bool:
	var project: Dictionary = _construction_projects.get(project_id, {})
	if project.is_empty():
		return false
	var builder_unit_id := str(project.get("builder_unit_id", ""))
	var system_id := str(project.get("system_id", ""))
	_remove_from_index(_construction_project_ids_by_builder_unit_id, builder_unit_id, project_id)
	_remove_from_index(_construction_project_ids_by_system, system_id, project_id)
	_construction_projects.erase(project_id)

	var builder := get_unit(builder_unit_id)
	if builder != null:
		if emit_cancelled:
			_stop_unit_for_construction(builder)
		_clear_builder_project_metadata(builder, project_id)
		builder.command_revision += 1
		unit_updated.emit(builder.unit_id)
	if emit_cancelled:
		construction_cancelled.emit(project_id)
	return true


func _sync_construction_project_for_builder(builder: SpaceUnitRuntime) -> void:
	if builder == null:
		return
	var project_id := _get_active_construction_project_id(builder.unit_id)
	if project_id.is_empty():
		return
	var project: Dictionary = _construction_projects.get(project_id, {})
	if project.is_empty():
		return

	var changed := false
	var old_system_id := str(project.get("system_id", ""))
	if old_system_id != builder.current_system_id:
		_remove_from_index(_construction_project_ids_by_system, old_system_id, project_id)
		_add_to_index(_construction_project_ids_by_system, builder.current_system_id, project_id)
		project["system_id"] = builder.current_system_id
		changed = true
	if str(project.get("owner_empire_id", "")) != builder.owner_empire_id:
		project["owner_empire_id"] = builder.owner_empire_id
		changed = true
	if not changed:
		return
	project["command_revision"] = int(project.get("command_revision", 0)) + 1
	_construction_projects[project_id] = project
	construction_updated.emit(project_id)


func _is_builder_at_construction_site(builder: SpaceUnitRuntime, project: Dictionary) -> bool:
	if builder == null:
		return false
	var build_position := SpaceUnitRuntime._variant_to_vector3(project.get("local_position", Vector3.ZERO))
	if builder.has_active_movement():
		return false
	return builder.local_position.distance_to(build_position) <= CONSTRUCTION_SITE_ARRIVAL_DISTANCE


func _start_construction_timer(project_id: String, project: Dictionary, builder: SpaceUnitRuntime) -> void:
	project["construction_state"] = CONSTRUCTION_STATE_BUILDING
	project["command_revision"] = int(project.get("command_revision", 0)) + 1
	project["build_started_day_serial"] = _get_current_day_serial()
	_construction_projects[project_id] = project
	_stop_unit_for_construction(builder)
	if builder != null:
		builder.command_revision += 1
		unit_updated.emit(builder.unit_id)
	construction_updated.emit(project_id)


func _move_builder_to_construction_site(builder: SpaceUnitRuntime, build_position: Vector3) -> void:
	if builder == null:
		return
	builder.previous_local_position = builder.local_position
	builder.target_local_position = build_position
	builder.velocity = Vector3.ZERO
	builder.movement_state = SpaceUnitRuntime.MOVEMENT_MOVING
	builder.movement_order_id = _generate_movement_order_id()
	builder.destination_system_id = ""
	builder.eta_days_remaining = 0
	builder.last_movement_day_serial = _get_current_day_serial()


func _stop_unit_for_construction(unit: SpaceUnitRuntime) -> void:
	if unit == null:
		return
	unit.previous_local_position = unit.local_position
	unit.target_local_position = unit.local_position
	unit.velocity = Vector3.ZERO
	unit.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
	unit.movement_order_id = 0
	unit.destination_system_id = ""
	unit.eta_days_remaining = 0
	unit.last_movement_day_serial = _get_current_day_serial()


func _resolve_build_site_position(builder: SpaceUnitRuntime, build_class: SpaceUnitClass, build_data: Dictionary) -> Vector3:
	if build_data.has("local_position"):
		return SpaceUnitRuntime._variant_to_vector3(build_data.get("local_position"))
	var offset := SpaceUnitRuntime._variant_to_vector3(build_data.get("local_offset", Vector3.ZERO))
	if offset.length_squared() > 0.001:
		return builder.local_position + offset
	var radius := 10.0
	if build_class != null and build_class.is_stationary():
		radius = 14.0
	var seed_key := "%s:%s" % [builder.unit_id, str(_next_construction_project_id)]
	var seed := float(abs(seed_key.hash()) % 3600) / 3600.0 * TAU
	return builder.local_position + Vector3(cos(seed) * radius, 0.0, sin(seed) * radius)


func _resolve_body_build_site_position(builder_unit_id: String, build_class_id: String, body_context: Dictionary) -> Vector3:
	var body_position := SpaceUnitRuntime._variant_to_vector3(body_context.get("local_position", Vector3.ZERO))
	var placement_metadata: Dictionary = body_context.get("placement_metadata", {}) if body_context.get("placement_metadata", {}) is Dictionary else {}
	var body_size := maxf(float(body_context.get("size", body_context.get("scale", 1.0))), 1.0)
	var placement_radius := maxf(float(placement_metadata.get("placement_radius", body_size * 4.0 + 5.0)), 3.0)
	var seed_key := "%s:%s:%s:%s" % [
		builder_unit_id,
		build_class_id,
		str(body_context.get("body_type", "")),
		str(body_context.get("body_id", "")),
	]
	var seed := float(abs(seed_key.hash()) % 3600) / 3600.0 * TAU
	return body_position + Vector3(cos(seed) * placement_radius, 0.0, sin(seed) * placement_radius)


func _normalize_build_body_context(system_id: String, body_context: Dictionary) -> Dictionary:
	var body_id := str(body_context.get("body_id", body_context.get("id", ""))).strip_edges()
	var body_type := str(body_context.get("body_type", body_context.get("type", ""))).strip_edges()
	if body_type.is_empty():
		var kind := str(body_context.get("kind", "")).strip_edges()
		if kind == "star" or kind == "black_hole":
			body_type = "star"
	if body_id.is_empty() or body_type.is_empty():
		return {}

	var component := _normalize_body_buildable_component(body_context.get("buildable_component", {}), body_type)
	return {
		"system_id": system_id,
		"body_id": body_id,
		"body_type": body_type,
		"body_name": str(body_context.get("body_name", body_context.get("name", body_id))).strip_edges(),
		"local_position": SpaceUnitRuntime._variant_to_vector3(body_context.get("local_position", Vector3.ZERO)),
		"size": float(body_context.get("size", body_context.get("scale", 1.0))),
		"allowed_build_tags": component.get("allowed_build_tags", PackedStringArray()),
		"max_active_projects": int(component.get("max_active_projects", 1)),
		"display_metadata": component.get("display_metadata", {}).duplicate(true) if component.get("display_metadata", {}) is Dictionary else {},
		"placement_metadata": component.get("placement_metadata", {}).duplicate(true) if component.get("placement_metadata", {}) is Dictionary else {},
	}


func _normalize_body_buildable_component(value: Variant, body_type: String) -> Dictionary:
	var source: Dictionary = value.duplicate(true) if value is Dictionary else {}
	var normalized_type := str(source.get("body_type", body_type)).strip_edges()
	if normalized_type.is_empty():
		normalized_type = body_type
	var allowed_tags := _variant_to_unique_string_array(source.get("allowed_build_tags", _default_body_allowed_build_tags(normalized_type)))
	if allowed_tags.is_empty():
		allowed_tags = _default_body_allowed_build_tags(normalized_type)
	return {
		"body_type": normalized_type,
		"allowed_build_tags": allowed_tags,
		"max_active_projects": maxi(int(source.get("max_active_projects", 1)), 0),
		"display_metadata": source.get("display_metadata", {}).duplicate(true) if source.get("display_metadata", {}) is Dictionary else {},
		"placement_metadata": source.get("placement_metadata", {}).duplicate(true) if source.get("placement_metadata", {}) is Dictionary else {},
	}


func _default_body_allowed_build_tags(body_type: String) -> PackedStringArray:
	match body_type:
		"star":
			return PackedStringArray([BUILD_TAG_STELLAR_STATION])
		"asteroid_belt":
			return PackedStringArray([BUILD_TAG_ORBITAL_STATION, BUILD_TAG_MINING_STATION])
		"structure", "ruin":
			return PackedStringArray([BUILD_TAG_ORBITAL_STATION, BUILD_TAG_RESEARCH_STATION])
		_:
			return PackedStringArray([BUILD_TAG_ORBITAL_STATION])


func _normalize_construction_state(value: Variant) -> String:
	var state := str(value).strip_edges()
	match state:
		CONSTRUCTION_STATE_MOVING_TO_SITE, CONSTRUCTION_STATE_BUILDING:
			return state
		_:
			return CONSTRUCTION_STATE_BUILDING


func _is_body_project_limit_reached(body_context: Dictionary) -> bool:
	var max_active_projects := int(body_context.get("max_active_projects", 1))
	if max_active_projects <= 0:
		return false
	var active_count := 0
	var system_id := str(body_context.get("system_id", ""))
	var body_id := str(body_context.get("body_id", ""))
	var body_type := str(body_context.get("body_type", ""))
	for project_variant in _construction_projects.values():
		var project: Dictionary = project_variant
		if str(project.get("system_id", "")) != system_id:
			continue
		if str(project.get("target_body_id", "")) != body_id:
			continue
		if str(project.get("target_body_type", "")) != body_type:
			continue
		active_count += 1
		if active_count >= max_active_projects:
			return true
	return false


func _string_arrays_intersect(a: PackedStringArray, b: PackedStringArray) -> bool:
	for value in a:
		if b.has(value):
			return true
	return false


func _variant_to_unique_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}
	if values is PackedStringArray:
		values = Array(values)
	if values is not Array:
		return result
	for value_variant in values:
		var value := str(value_variant).strip_edges()
		if value.is_empty() or seen.has(value):
			continue
		seen[value] = true
		result.append(value)
	return result


func _construction_project_to_snapshot(project: Dictionary) -> Dictionary:
	var snapshot := project.duplicate(true)
	snapshot["local_position"] = SpaceUnitRuntime._vector3_to_dict(SpaceUnitRuntime._variant_to_vector3(project.get("local_position", Vector3.ZERO)))
	snapshot["metadata"] = project.get("metadata", {}).duplicate(true) if project.get("metadata", {}) is Dictionary else {}
	return snapshot


func _construction_project_to_renderable(project: Dictionary) -> Dictionary:
	var days_total := maxi(int(project.get("days_total", 1)), 1)
	var days_remaining := maxi(int(project.get("days_remaining", days_total)), 0)
	return {
		"project_id": str(project.get("project_id", "")),
		"builder_unit_id": str(project.get("builder_unit_id", "")),
		"build_class_id": str(project.get("build_class_id", "")),
		"display_name": str(project.get("display_name", "")),
		"owner_empire_id": str(project.get("owner_empire_id", "")),
		"system_id": str(project.get("system_id", "")),
		"target_body_id": str(project.get("target_body_id", "")),
		"target_body_type": str(project.get("target_body_type", "")),
		"target_body_name": str(project.get("target_body_name", "")),
		"days_total": days_total,
		"days_remaining": days_remaining,
		"construction_state": _normalize_construction_state(project.get("construction_state", CONSTRUCTION_STATE_BUILDING)),
		"is_build_timer_active": _normalize_construction_state(project.get("construction_state", CONSTRUCTION_STATE_BUILDING)) == CONSTRUCTION_STATE_BUILDING,
		"progress_ratio": clampf(float(days_total - days_remaining) / float(days_total), 0.0, 1.0),
		"local_position": SpaceUnitRuntime._variant_to_vector3(project.get("local_position", Vector3.ZERO)),
		"started_day_serial": int(project.get("started_day_serial", 0)),
		"command_revision": int(project.get("command_revision", 0)),
		"metadata": project.get("metadata", {}).duplicate(true) if project.get("metadata", {}) is Dictionary else {},
	}


func _construction_project_from_snapshot(data: Dictionary) -> Dictionary:
	var project_id := str(data.get("project_id", "")).strip_edges()
	if project_id.is_empty():
		return {}
	var days_total := maxi(int(data.get("days_total", data.get("build_time_days", 1))), 1)
	return {
		"project_id": project_id,
		"builder_unit_id": str(data.get("builder_unit_id", "")),
		"build_class_id": str(data.get("build_class_id", BASIC_STATION_CLASS_ID)),
		"display_name": str(data.get("display_name", "")),
		"owner_empire_id": str(data.get("owner_empire_id", "")),
		"system_id": str(data.get("system_id", "")),
		"target_body_id": str(data.get("target_body_id", "")),
		"target_body_type": str(data.get("target_body_type", "")),
		"target_body_name": str(data.get("target_body_name", "")),
		"days_total": days_total,
		"days_remaining": clampi(int(data.get("days_remaining", days_total)), 0, days_total),
		"construction_state": _normalize_construction_state(data.get("construction_state", data.get("state", CONSTRUCTION_STATE_BUILDING))),
		"local_position": SpaceUnitRuntime._variant_to_vector3(data.get("local_position", Vector3.ZERO)),
		"started_day_serial": maxi(int(data.get("started_day_serial", 0)), 0),
		"build_started_day_serial": maxi(int(data.get("build_started_day_serial", 0)), 0),
		"command_revision": maxi(int(data.get("command_revision", 0)), 0),
		"metadata": _sanitize_dictionary(data.get("metadata", {})),
	}


func _get_active_construction_project_id(builder_unit_id: String) -> String:
	var project_ids := _get_index_values(_construction_project_ids_by_builder_unit_id, builder_unit_id)
	if project_ids.is_empty():
		return ""
	return project_ids[0]


func _set_builder_project_metadata(builder: SpaceUnitRuntime, project_id: String) -> void:
	if builder == null:
		return
	var metadata := builder.metadata.duplicate(true)
	metadata["active_construction_project_id"] = project_id
	builder.metadata = metadata


func _clear_builder_project_metadata(builder: SpaceUnitRuntime, project_id: String) -> void:
	if builder == null:
		return
	if str(builder.metadata.get("active_construction_project_id", "")) != project_id:
		return
	var metadata := builder.metadata.duplicate(true)
	metadata.erase("active_construction_project_id")
	builder.metadata = metadata


func _generate_unit_id() -> String:
	var unit_id := "unit_%06d" % _next_unit_id
	_next_unit_id += 1
	return unit_id


func _generate_fleet_id() -> String:
	var fleet_id := "fleet_%06d" % _next_fleet_id
	_next_fleet_id += 1
	return fleet_id


func _generate_movement_order_id() -> int:
	var movement_order_id := _next_movement_order_id
	_next_movement_order_id += 1
	return movement_order_id


func _generate_construction_project_id() -> String:
	var project_id := "construction_%06d" % _next_construction_project_id
	_next_construction_project_id += 1
	return project_id


func _rebuild_indexes_and_economy_sources() -> void:
	_unit_ids_by_owner.clear()
	_unit_ids_by_system.clear()
	_unit_ids_by_class.clear()
	_fleet_ids_by_owner.clear()
	_fleet_ids_by_system.clear()

	for unit_variant in _units.values():
		var unit: SpaceUnitRuntime = unit_variant
		_add_to_index(_unit_ids_by_owner, unit.owner_empire_id, unit.unit_id)
		_add_to_index(_unit_ids_by_system, unit.current_system_id, unit.unit_id)
		_add_to_index(_unit_ids_by_class, unit.class_id, unit.unit_id)
		_sync_unit_economy_source(unit)

	for fleet_variant in _fleets.values():
		var fleet: SpaceFleetRuntime = fleet_variant
		_add_to_index(_fleet_ids_by_owner, fleet.owner_empire_id, fleet.fleet_id)
		_add_to_index(_fleet_ids_by_system, fleet.current_system_id, fleet.fleet_id)

	for project_variant in _construction_projects.values():
		var project: Dictionary = project_variant
		var project_id := str(project.get("project_id", ""))
		var builder_unit_id := str(project.get("builder_unit_id", ""))
		var system_id := str(project.get("system_id", ""))
		if project_id.is_empty() or builder_unit_id.is_empty() or system_id.is_empty():
			continue
		_add_to_index(_construction_project_ids_by_builder_unit_id, builder_unit_id, project_id)
		_add_to_index(_construction_project_ids_by_system, system_id, project_id)
		var builder := get_unit(builder_unit_id)
		if builder != null:
			_set_builder_project_metadata(builder, project_id)


func _sync_unit_economy_source(unit: SpaceUnitRuntime) -> void:
	if unit == null:
		return

	var source_id := _get_unit_source_id(unit.unit_id)
	var unit_class := get_unit_class(unit.class_id)
	if EconomyManager == null or unit_class == null or unit.owner_empire_id.is_empty():
		_remove_unit_economy_source(unit.unit_id)
		return

	var upkeep_costs := unit_class.get_monthly_upkeep()
	if upkeep_costs.is_empty():
		_remove_unit_economy_source(unit.unit_id)
		return

	if EconomyManager.has_source(source_id):
		EconomyManager.transfer_source(source_id, unit.owner_empire_id)
		EconomyManager.update_source(source_id, [], upkeep_costs, [])
		return

	EconomyManager.register_source(
		source_id,
		unit.owner_empire_id,
		[],
		upkeep_costs,
		[],
		"space_unit_upkeep"
	)


func _remove_unit_economy_source(unit_id: String) -> void:
	if EconomyManager == null:
		return
	var source_id := _get_unit_source_id(unit_id)
	if EconomyManager.has_source(source_id):
		EconomyManager.remove_source(source_id)


func _get_unit_source_id(unit_id: String) -> String:
	return "%s%s" % [UNIT_SOURCE_PREFIX, unit_id]


func _merge_amount_defs_into_map(target: Dictionary, amounts: Array[ResourceAmountDef]) -> void:
	for amount in amounts:
		if amount == null or amount.resource_id.is_empty() or amount.milliunits == 0:
			continue
		target[amount.resource_id] = int(target.get(amount.resource_id, 0)) + amount.milliunits


func _get_fleet_in_system_speed(fleet: SpaceFleetRuntime) -> float:
	if fleet == null or fleet.unit_ids.is_empty():
		return 0.0
	var speed := INF
	for unit_id in fleet.unit_ids:
		var unit := get_unit(unit_id)
		if unit == null or not unit.is_mobile():
			return 0.0
		var unit_class := get_unit_class(unit.class_id)
		if unit_class == null:
			return 0.0
		speed = minf(speed, unit_class.get_in_system_speed())
	return speed if speed != INF else 0.0


func _unit_uses_hyperlanes(unit: SpaceUnitRuntime) -> bool:
	if unit == null:
		return false
	var unit_class := get_unit_class(unit.class_id)
	if unit_class == null or unit_class.mobility_component == null:
		return false
	return unit_class.mobility_component.uses_hyperlanes


func _fleet_uses_hyperlanes(fleet: SpaceFleetRuntime) -> bool:
	if fleet == null or fleet.unit_ids.is_empty():
		return false
	for unit_id in fleet.unit_ids:
		var unit := get_unit(unit_id)
		if unit == null or not _unit_uses_hyperlanes(unit):
			return false
	return true


func _sync_fleet_center_from_members(fleet: SpaceFleetRuntime) -> void:
	if fleet == null or fleet.unit_ids.is_empty():
		return
	var center := Vector3.ZERO
	var count := 0
	for unit_id in fleet.unit_ids:
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		center += unit.local_position
		count += 1
	if count <= 0:
		return
	fleet.local_position = center / float(count)
	fleet.previous_local_position = fleet.local_position
	fleet.target_local_position = fleet.local_position
	fleet.last_movement_day_serial = _get_current_day_serial()


func _apply_fleet_member_positions(fleet: SpaceFleetRuntime, emit_units: bool) -> void:
	if fleet == null:
		return
	for member_index in range(fleet.unit_ids.size()):
		var unit_id := fleet.unit_ids[member_index]
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		var offset := _resolve_fleet_member_offset(fleet, member_index)
		unit.previous_local_position = unit.local_position
		unit.local_position = fleet.local_position + offset
		unit.target_local_position = fleet.target_local_position + offset
		unit.velocity = fleet.velocity
		unit.movement_state = fleet.movement_state
		unit.movement_order_id = fleet.movement_order_id
		unit.last_movement_day_serial = fleet.last_movement_day_serial
		unit.command_revision += 1
		if emit_units:
			unit_updated.emit(unit_id)


func _resolve_fleet_member_offset(fleet: SpaceFleetRuntime, member_index: int) -> Vector3:
	if fleet == null or fleet.unit_ids.size() <= 1:
		return Vector3.ZERO
	var largest_radius := 2.0
	for unit_id in fleet.unit_ids:
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		var unit_class := get_unit_class(unit.class_id)
		if unit_class != null:
			largest_radius = maxf(largest_radius, unit_class.get_formation_radius())
	var angle := float(member_index) * TAU / float(maxi(fleet.unit_ids.size(), 1)) + float(abs(fleet.fleet_id.hash()) % 3600) / 3600.0 * TAU
	var radius := largest_radius
	if member_index == 0 and fleet.unit_ids.size() > 2:
		radius *= 0.5
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _resolve_spawn_position(system_id: String, unit_id: String, unit_class: SpaceUnitClass) -> Vector3:
	var existing_count := get_unit_ids_in_system(system_id).size()
	var radius := 34.0 if unit_class == null or unit_class.is_stationary() else 42.0
	var ring_index := int(floor(float(existing_count) / 8.0))
	var slot_index := existing_count % 8
	var slot_count := 8 + ring_index * 2
	var seed_angle := float(abs(unit_id.hash()) % 3600) / 3600.0 * TAU
	var angle := seed_angle + float(slot_index) * TAU / float(maxi(slot_count, 1))
	return Vector3(cos(angle) * (radius + float(ring_index) * 5.0), 0.35, sin(angle) * (radius + float(ring_index) * 5.0))


func _get_current_day_serial() -> int:
	return SimClock.get_current_day_serial() if SimClock != null and SimClock.has_method("get_current_day_serial") else 0


func _add_to_index(index: Dictionary, key: String, value: String) -> void:
	if key.is_empty() or value.is_empty():
		return
	var bucket: Dictionary = index.get(key, {})
	bucket[value] = true
	index[key] = bucket


func _remove_from_index(index: Dictionary, key: String, value: String) -> void:
	if key.is_empty() or value.is_empty() or not index.has(key):
		return
	var bucket: Dictionary = index[key]
	bucket.erase(value)
	if bucket.is_empty():
		index.erase(key)
		return
	index[key] = bucket


func _get_index_values(index: Dictionary, key: String) -> PackedStringArray:
	var result := PackedStringArray()
	if key.is_empty() or not index.has(key):
		return result
	var bucket: Dictionary = index[key]
	for value_variant in bucket.keys():
		result.append(str(value_variant))
	return result


static func _variant_to_packed_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if values is PackedStringArray:
		return values
	if values is not Array:
		return result
	for value_variant in values:
		var value: String = str(value_variant).strip_edges()
		if value.is_empty():
			continue
		result.append(value)
	return result


static func _sanitize_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}
