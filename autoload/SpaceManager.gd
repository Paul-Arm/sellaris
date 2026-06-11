extends Node

const SPACE_UNIT_CLASS_SCRIPT: Script = preload("res://core/space/SpaceUnitClass.gd")
const SPACE_UNIT_RUNTIME_SCRIPT: Script = preload("res://core/space/SpaceUnitRuntime.gd")
const SPACE_FLEET_RUNTIME_SCRIPT: Script = preload("res://core/space/SpaceFleetRuntime.gd")
const SHIP_COMPONENT_CATALOG_SCRIPT: Script = preload("res://core/space/design/ShipComponentCatalog.gd")
const SHIP_DESIGN_CATALOG_SCRIPT: Script = preload("res://core/space/design/ShipDesignCatalog.gd")
const COMBAT_SYSTEM_SCRIPT: Script = preload("res://core/space/combat/CombatSystem.gd")
const HOSTILITY_FREE_FOR_ALL := "free_for_all"
const HOSTILITY_PEACEFUL := "peaceful"
const DEFAULT_AUTO_ENGAGE_RADIUS := 12.0
const UNIT_SOURCE_PREFIX := "unit:"
const SCIENCE_SHIP_CLASS_ID := "science_ship"
const BUILDER_SHIP_CLASS_ID := "builder_ship"
const BASIC_STATION_CLASS_ID := "basic_station"
const STELLAR_STATION_CLASS_ID := "stellar_station"
const RESOURCE_COLLECTOR_STATION_CLASS_ID := "resource_collector_station"
const CORVETTE_CLASS_ID := "corvette"
const STATION_BUILD_TIME_DAYS := 60
const CORVETTE_BUILD_TIME_DAYS := 30
const BUILD_TAG_ORBITAL_STATION := "orbital_station"
const BUILD_TAG_STELLAR_STATION := "stellar_station"
const BUILD_TAG_MINING_STATION := "mining_station"
const BUILD_TAG_RESEARCH_STATION := "research_station"
const BUILD_TAG_SHIP := "ship"
const CONSTRUCTION_STATE_MOVING_TO_SITE := "moving_to_site"
const CONSTRUCTION_STATE_BUILDING := "building"
const CONSTRUCTION_SITE_ARRIVAL_DISTANCE := 0.35
const EXPLORATION_STATE_TRAVELLING := "travelling_to_system"
const EXPLORATION_STATE_MOVING_TO_BODY := "moving_to_body"
const EXPLORATION_STATE_SCANNING_BODY := "scanning_body"
const EXPLORATION_STATE_COMPLETED := "completed"

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
signal exploration_started(order_id: String)
signal exploration_updated(order_id: String)
signal exploration_scan_completed(order_id: String, unit_id: String, system_id: String, body_id: String)
signal exploration_completed(order_id: String, unit_id: String, system_id: String)
signal exploration_cancelled(order_id: String)
signal ship_component_unlocked(empire_id: String, component_id: String)
signal ship_design_created(design_id: String)
signal ship_design_updated(design_id: String)
signal combat_events(events: Array[Dictionary])
signal battle_started(battle_id: String, system_id: String)
signal battle_ended(battle_id: String, system_id: String)

var _next_unit_id: int = 1
var _next_fleet_id: int = 1
var _next_movement_order_id: int = 1
var _next_construction_project_id: int = 1
var _next_exploration_order_id: int = 1
var _unit_classes: Dictionary = {}
var _units: Dictionary = {}
var _fleets: Dictionary = {}
var _construction_projects: Dictionary = {}
var _exploration_orders: Dictionary = {}
var _unit_ids_by_owner: Dictionary = {}
var _unit_ids_by_system: Dictionary = {}
var _unit_ids_by_class: Dictionary = {}
var _fleet_ids_by_owner: Dictionary = {}
var _fleet_ids_by_system: Dictionary = {}
var _construction_project_ids_by_builder_unit_id: Dictionary = {}
var _construction_project_ids_by_system: Dictionary = {}
var _exploration_order_ids_by_unit_id: Dictionary = {}
var _exploration_order_ids_by_system: Dictionary = {}
var _ship_component_catalog: ShipComponentCatalog = null
var _ship_design_catalog: ShipDesignCatalog = null
var _combat_system: CombatSystem = null
var _hostility_mode: String = HOSTILITY_FREE_FOR_ALL
var _next_ability_command_id: int = 1


func _ready() -> void:
	_ship_component_catalog = SHIP_COMPONENT_CATALOG_SCRIPT.new() as ShipComponentCatalog
	_ship_component_catalog.load_definitions()
	_ship_design_catalog = SHIP_DESIGN_CATALOG_SCRIPT.new() as ShipDesignCatalog
	_ship_design_catalog.setup(_ship_component_catalog)
	_combat_system = COMBAT_SYSTEM_SCRIPT.new() as CombatSystem
	_combat_system.setup(self)
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
	_next_exploration_order_id = 1
	_units.clear()
	_fleets.clear()
	_construction_projects.clear()
	_exploration_orders.clear()
	_unit_ids_by_owner.clear()
	_unit_ids_by_system.clear()
	_unit_ids_by_class.clear()
	_fleet_ids_by_owner.clear()
	_fleet_ids_by_system.clear()
	_construction_project_ids_by_builder_unit_id.clear()
	_construction_project_ids_by_system.clear()
	_exploration_order_ids_by_unit_id.clear()
	_exploration_order_ids_by_system.clear()
	if _ship_design_catalog != null:
		_ship_design_catalog.reset_state()
	if _combat_system != null:
		_combat_system.reset_state()
	_hostility_mode = HOSTILITY_FREE_FOR_ALL
	_next_ability_command_id = 1
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
			{"slot_id": "defense_1", "slot_kind": "defense", "required": false},
			{"slot_id": "utility_1", "slot_kind": "utility", "required": false},
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
		"explorer_component": {
			"scan_min_days": 5,
			"scan_max_days": 15,
			"scan_offset_radius": 4.0,
			"arrival_distance": 0.45,
			"scan_body_types": ["star", "planet", "asteroid_belt", "structure", "ruin"],
			"discover_anomalies_per_body": true,
			"grants_full_system_intel": true,
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
			{"slot_id": "defense_1", "slot_kind": "defense", "required": false},
			{"slot_id": "utility_1", "slot_kind": "utility", "required": false},
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
		"command_tags": ["station", "buildable", "shipyard"],
		"component_slots": [
			{"slot_id": "weapon_1", "slot_kind": "weapon", "required": false},
			{"slot_id": "weapon_2", "slot_kind": "weapon", "required": false},
			{"slot_id": "defense_1", "slot_kind": "defense", "required": false},
			{"slot_id": "defense_2", "slot_kind": "defense", "required": false},
			{"slot_id": "utility_1", "slot_kind": "utility", "required": false},
			{"slot_id": "utility_2", "slot_kind": "utility", "required": false},
		],
		"builder_component": {
			"buildable_tags": [BUILD_TAG_SHIP],
			"single_active_project": true,
		},
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
		"command_tags": ["station", "stellar", "buildable", "shipyard"],
		"component_slots": [
			{"slot_id": "weapon_1", "slot_kind": "weapon", "required": false},
			{"slot_id": "weapon_2", "slot_kind": "weapon", "required": false},
			{"slot_id": "defense_1", "slot_kind": "defense", "required": false},
			{"slot_id": "defense_2", "slot_kind": "defense", "required": false},
			{"slot_id": "utility_1", "slot_kind": "utility", "required": false},
			{"slot_id": "utility_2", "slot_kind": "utility", "required": false},
		],
		"builder_component": {
			"buildable_tags": [BUILD_TAG_SHIP],
			"single_active_project": true,
		},
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
	register_unit_class_from_data({
		"class_id": RESOURCE_COLLECTOR_STATION_CLASS_ID,
		"display_name": "Sammelstation",
		"unit_kind": SpaceUnitClass.UNIT_KIND_STATION,
		"category": SpaceUnitClass.CATEGORY_STATION,
		"max_hull_points": 1200.0,
		"default_ai_role": "resource_collection",
		"command_tags": ["station", "collector", "buildable"],
		"component_slots": [
			{"slot_id": "weapon_1", "slot_kind": "weapon", "required": false},
			{"slot_id": "defense_1", "slot_kind": "defense", "required": false},
			{"slot_id": "utility_1", "slot_kind": "utility", "required": false},
		],
		"upkeep_component": {
			"build_costs": {
				"alloys": 180.0,
				"energy": 80.0,
			},
			"monthly_costs": {
				"energy": 2.0,
				"alloys": 0.25,
			},
			"command_point_cost": 0.0,
		},
		"buildable_component": {
			"build_time_days": STATION_BUILD_TIME_DAYS,
			"buildable_by_builder_ships": true,
			"build_tags": [BUILD_TAG_ORBITAL_STATION, BUILD_TAG_STELLAR_STATION],
		},
		"metadata": {
			"requires_resource_deposit": true,
		},
	}, overwrite_existing)
	register_unit_class_from_data({
		"class_id": CORVETTE_CLASS_ID,
		"display_name": "Corvette",
		"unit_kind": SpaceUnitClass.UNIT_KIND_SHIP,
		"category": SpaceUnitClass.CATEGORY_COMBAT,
		"max_hull_points": 300,
		"default_ai_role": "escort",
		"command_tags": ["military", "combat", "escort"],
		"component_slots": [
			{"slot_id": "weapon_1", "slot_kind": "weapon", "required": false},
			{"slot_id": "weapon_2", "slot_kind": "weapon", "required": false},
			{"slot_id": "defense_1", "slot_kind": "defense", "required": false},
			{"slot_id": "utility_1", "slot_kind": "utility", "required": false},
			{"slot_id": "drive", "slot_kind": "drive", "required": true},
		],
		"upkeep_component": {
			"build_costs": {
				"alloys": 90.0,
				"energy": 30.0,
			},
			"monthly_costs": {
				"energy": 0.8,
				"alloys": 0.2,
			},
			"command_point_cost": 1.0,
		},
		"mobility_component": {
			"cruise_speed": 6.0,
			"acceleration": 7.0,
			"turn_rate_degrees": 220.0,
			"formation_radius": 2.0,
			"can_join_fleets": true,
			"uses_hyperlanes": true,
			"can_orbit_system_objects": true,
			"can_move_in_system": true,
		},
		"buildable_component": {
			"build_time_days": CORVETTE_BUILD_TIME_DAYS,
			"buildable_by_builder_ships": true,
			"build_tags": [BUILD_TAG_SHIP],
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


func bootstrap_empires(empire_ids_variant: Variant) -> void:
	if _ship_design_catalog == null:
		return
	for empire_id_variant in empire_ids_variant:
		var empire_id := str(empire_id_variant).strip_edges()
		if empire_id.is_empty():
			continue
		_ship_design_catalog.bootstrap_empire_unlocks(empire_id)
		_ship_design_catalog.ensure_default_designs(empire_id, get_all_unit_classes())


func get_ship_component_catalog() -> ShipComponentCatalog:
	return _ship_component_catalog


func get_ship_component(component_id: String) -> Dictionary:
	if _ship_component_catalog == null:
		return {}
	var definition := _ship_component_catalog.get_component(component_id)
	if definition == null:
		return {}
	return definition.to_dict()


func is_ship_component_unlocked(empire_id: String, component_id: String) -> bool:
	if _ship_design_catalog == null:
		return false
	return _ship_design_catalog.is_component_unlocked(empire_id, component_id)


func unlock_ship_component(empire_id: String, component_id: String) -> bool:
	if _ship_design_catalog == null:
		return false
	if not _ship_design_catalog.unlock_component(empire_id, component_id):
		return false
	ship_component_unlocked.emit(empire_id, component_id)
	return true


func get_unlocked_ship_component_ids(empire_id: String) -> Array[String]:
	if _ship_design_catalog == null:
		return []
	return _ship_design_catalog.get_unlocked_component_ids(empire_id)


func create_ship_design(empire_id: String, class_id: String, slot_assignments: Dictionary, options: Dictionary = {}) -> String:
	if _ship_design_catalog == null:
		return ""
	var design_id := _ship_design_catalog.create_design(empire_id, get_unit_class(class_id), slot_assignments, options)
	if not design_id.is_empty():
		ship_design_created.emit(design_id)
	return design_id


func update_ship_design(design_id: String, slot_assignments: Dictionary) -> bool:
	if _ship_design_catalog == null:
		return false
	var design := _ship_design_catalog.get_design(design_id)
	if design == null:
		return false
	if not _ship_design_catalog.update_design(design_id, get_unit_class(design.class_id), slot_assignments):
		return false
	for unit_variant in _units.values():
		var unit: SpaceUnitRuntime = unit_variant
		if unit.design_id == design_id:
			_apply_design_to_unit(unit)
			_sync_unit_economy_source(unit)
			unit_updated.emit(unit.unit_id)
	ship_design_updated.emit(design_id)
	return true


func remove_ship_design(design_id: String) -> bool:
	if _ship_design_catalog == null:
		return false
	var design := _ship_design_catalog.get_design(design_id)
	if design == null or design.is_default:
		return false
	for unit_variant in _units.values():
		var unit: SpaceUnitRuntime = unit_variant
		if unit.design_id == design_id:
			return false
	if not _ship_design_catalog.remove_design(design_id):
		return false
	ship_design_updated.emit(design_id)
	return true


func rename_ship_design(design_id: String, display_name: String) -> bool:
	if _ship_design_catalog == null:
		return false
	if not _ship_design_catalog.rename_design(design_id, display_name):
		return false
	ship_design_updated.emit(design_id)
	return true


func set_default_ship_design(design_id: String) -> bool:
	if _ship_design_catalog == null:
		return false
	if not _ship_design_catalog.set_default_design(design_id):
		return false
	ship_design_updated.emit(design_id)
	return true


func compile_ship_design_draft(class_id: String, slot_assignments: Dictionary) -> Dictionary:
	var unit_class := get_unit_class(class_id)
	if unit_class == null or _ship_component_catalog == null:
		return {}
	return ShipDesignCompiler.compile(unit_class, slot_assignments, _ship_component_catalog)


func validate_ship_design_draft(empire_id: String, class_id: String, slot_assignments: Dictionary) -> PackedStringArray:
	var unit_class := get_unit_class(class_id)
	if unit_class == null or _ship_component_catalog == null or _ship_design_catalog == null:
		return PackedStringArray(["unknown_unit_class"])
	var unlocked: Dictionary = {}
	for component_id in _ship_design_catalog.get_unlocked_component_ids(empire_id):
		unlocked[component_id] = true
	return ShipDesignCompiler.validate(unit_class, slot_assignments, _ship_component_catalog, unlocked)


func get_ship_design(design_id: String) -> Dictionary:
	if _ship_design_catalog == null:
		return {}
	var design := _ship_design_catalog.get_design(design_id)
	if design == null:
		return {}
	return design.to_dict()


func get_ship_design_ids_for_empire(empire_id: String) -> Array[String]:
	if _ship_design_catalog == null:
		return []
	return _ship_design_catalog.get_design_ids_for_empire(empire_id)


func get_default_ship_design_id(empire_id: String, class_id: String) -> String:
	if _ship_design_catalog == null:
		return ""
	return _ship_design_catalog.get_default_design_id(empire_id, class_id)


func get_compiled_ship_design_stats(design_id: String) -> Dictionary:
	if _ship_design_catalog == null:
		return {}
	var design := _ship_design_catalog.get_design(design_id)
	if design == null:
		return {}
	return _ship_design_catalog.get_compiled_stats(design_id, get_unit_class(design.class_id))


func get_last_ship_design_errors() -> PackedStringArray:
	if _ship_design_catalog == null:
		return PackedStringArray()
	return _ship_design_catalog.get_last_validation_errors()


# --- Combat API (COMBAT_DESIGN.md Phase B) ---

func set_hostility_mode(mode: String) -> void:
	if mode == HOSTILITY_FREE_FOR_ALL or mode == HOSTILITY_PEACEFUL:
		_hostility_mode = mode


func get_hostility_mode() -> String:
	return _hostility_mode


func are_empires_hostile(empire_id_a: String, empire_id_b: String) -> bool:
	# Diplomacy stub: free-for-all until a war/relations system exists.
	if _hostility_mode != HOSTILITY_FREE_FOR_ALL:
		return false
	if empire_id_a.is_empty() or empire_id_b.is_empty():
		return false
	return empire_id_a != empire_id_b


func set_unit_stance(unit_id: String, stance: String) -> bool:
	var unit := get_unit(unit_id)
	if unit == null:
		return false
	var normalized := SpaceUnitRuntime._normalize_stance(stance)
	if unit.stance == normalized:
		return false
	unit.stance = normalized
	unit.command_revision += 1
	unit_updated.emit(unit_id)
	return true


func set_fleet_stance(fleet_id: String, stance: String) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null:
		return false
	var changed := false
	for unit_id in fleet.unit_ids:
		changed = set_unit_stance(unit_id, stance) or changed
	return changed


func queue_unit_ability_command(unit_id: String, slot_id: String, command_data: Dictionary = {}) -> bool:
	var unit := get_unit(unit_id)
	if unit == null or unit.design_id.is_empty():
		return false
	slot_id = slot_id.strip_edges()
	if slot_id.is_empty() or unit.ability_cooldowns.has(slot_id):
		return false

	var has_manual_ability := false
	var design_stats := get_compiled_ship_design_stats(unit.design_id)
	for ability_variant in design_stats.get("abilities", []):
		if ability_variant is not Dictionary:
			continue
		var ability: Dictionary = ability_variant
		if str(ability.get("slot_id", "")) == slot_id and str(ability.get("trigger", "")) == "manual":
			has_manual_ability = true
			break
	if not has_manual_ability:
		return false

	for pending_command in unit.pending_ability_commands:
		if str(pending_command.get("slot_id", "")) == slot_id:
			return false

	var command := command_data.duplicate(true)
	command["command_id"] = _next_ability_command_id
	command["slot_id"] = slot_id
	_next_ability_command_id += 1
	unit.pending_ability_commands.append(command)
	unit.command_revision += 1
	unit_updated.emit(unit_id)
	return true


func get_battle(battle_id: String) -> Dictionary:
	if _combat_system == null:
		return {}
	return _combat_system.get_battle(battle_id)


func get_active_battle_ids() -> Array[String]:
	if _combat_system == null:
		return []
	return _combat_system.get_active_battle_ids()


func get_battle_id_for_system(system_id: String) -> String:
	if _combat_system == null:
		return ""
	return _combat_system.get_battle_id_for_system(system_id)


func get_battle_event_log(battle_id: String) -> Array[Dictionary]:
	if _combat_system == null:
		return []
	return _combat_system.get_battle_event_log(battle_id)


func get_all_unit_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for unit_id_variant in _units.keys():
		result.append(str(unit_id_variant))
	return result


func get_system_ids_with_units() -> PackedStringArray:
	var result := PackedStringArray()
	for system_id_variant in _unit_ids_by_system.keys():
		result.append(str(system_id_variant))
	return result


func _resolve_design_for_spawn(unit_class: SpaceUnitClass, owner_empire_id: String, spawn_data: Dictionary) -> String:
	if _ship_design_catalog == null or unit_class == null:
		return ""
	var design_id := str(spawn_data.get("design_id", "")).strip_edges()
	if design_id.is_empty():
		design_id = _ship_design_catalog.get_default_design_id(owner_empire_id, unit_class.class_id)
	if design_id.is_empty():
		return ""
	var design := _ship_design_catalog.get_design(design_id)
	if design == null or design.class_id != unit_class.class_id or design.empire_id != owner_empire_id:
		return ""
	return design_id


func _apply_design_to_unit(unit: SpaceUnitRuntime) -> void:
	if unit == null or unit.design_id.is_empty():
		return
	var stats := get_compiled_ship_design_stats(unit.design_id)
	if stats.is_empty():
		return
	var hull_ratio := unit.get_hull_ratio()
	unit.max_hull_points = maxi(int(stats.get("max_hull_points", unit.max_hull_points)), 1)
	unit.current_hull_points = clampi(int(round(float(unit.max_hull_points) * hull_ratio)), 0, unit.max_hull_points)
	var shield_ratio := unit.get_shield_ratio()
	unit.max_shield_points = maxi(int(stats.get("max_shield_points", 0)), 0)
	unit.current_shield_points = clampi(int(round(float(unit.max_shield_points) * shield_ratio)), 0, unit.max_shield_points)
	unit.armor_points = maxi(int(stats.get("armor_points", 0)), 0)
	unit.evasion_bp = clampi(int(stats.get("evasion_bp", 0)), 0, 9500)
	unit.auto_engage_radius = maxf(float(stats.get("auto_engage_radius", DEFAULT_AUTO_ENGAGE_RADIUS)), 0.0)


func _get_default_stance(unit_class: SpaceUnitClass) -> String:
	if unit_class == null:
		return SpaceUnitRuntime.STANCE_PASSIVE
	match unit_class.category:
		SpaceUnitClass.CATEGORY_COMBAT, SpaceUnitClass.CATEGORY_STATION:
			return SpaceUnitRuntime.STANCE_AGGRESSIVE
		_:
			return SpaceUnitRuntime.STANCE_PASSIVE


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
	unit.design_id = _resolve_design_for_spawn(unit_class, owner_empire_id, spawn_data)
	unit.display_name = str(spawn_data.get("display_name", unit_class.display_name))
	unit.owner_empire_id = owner_empire_id
	unit.controller_kind = controller_kind
	unit.controller_peer_id = int(spawn_data.get("controller_peer_id", 0))
	unit.ai_role = StringName(str(spawn_data.get("ai_role", str(unit_class.default_ai_role))))
	unit.current_system_id = system_id
	unit.destination_system_id = str(spawn_data.get("destination_system_id", ""))
	unit.eta_days_remaining = maxi(int(spawn_data.get("eta_days_remaining", 0)), 0)
	unit.max_hull_points = unit_class.max_hull_points
	unit.auto_engage_radius = DEFAULT_AUTO_ENGAGE_RADIUS
	if not unit.design_id.is_empty():
		var design_stats := get_compiled_ship_design_stats(unit.design_id)
		unit.max_hull_points = maxi(int(design_stats.get("max_hull_points", unit.max_hull_points)), 1)
		unit.max_shield_points = maxi(int(design_stats.get("max_shield_points", 0)), 0)
		unit.armor_points = maxi(int(design_stats.get("armor_points", 0)), 0)
		unit.evasion_bp = clampi(int(design_stats.get("evasion_bp", 0)), 0, 9500)
		unit.auto_engage_radius = maxf(float(design_stats.get("auto_engage_radius", DEFAULT_AUTO_ENGAGE_RADIUS)), 0.0)
	unit.current_hull_points = clampi(int(round(float(spawn_data.get("current_hull_points", unit.max_hull_points)))), 0, unit.max_hull_points)
	unit.current_shield_points = clampi(int(spawn_data.get("current_shield_points", unit.max_shield_points)), 0, unit.max_shield_points)
	unit.stance = SpaceUnitRuntime._normalize_stance(str(spawn_data.get("stance", _get_default_stance(unit_class))))
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

	cancel_exploration_order_for_unit(unit_id)
	cancel_build_order_for_builder(unit_id)
	if _combat_system != null:
		_combat_system.handle_unit_removed(unit)
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
		_merge_amount_defs_into_map(totals, _get_unit_monthly_upkeep(unit, unit_class))
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

	var design_id := str(build_data.get("design_id", "")).strip_edges()
	if design_id.is_empty() and _ship_design_catalog != null:
		design_id = _ship_design_catalog.get_default_design_id(builder.owner_empire_id, build_class.class_id)
	var design_stats: Dictionary = {}
	if not design_id.is_empty():
		var design := _ship_design_catalog.get_design(design_id) if _ship_design_catalog != null else null
		if design == null or design.class_id != build_class.class_id or design.empire_id != builder.owner_empire_id:
			design_id = ""
		else:
			design_stats = get_compiled_ship_design_stats(design_id)

	if bool(build_data.get("commit_cost", false)):
		var order_costs: Variant = design_stats.get("build_costs", []) if not design_stats.is_empty() else build_class.get_build_costs()
		if EconomyManager == null or not EconomyManager.commit_cost(builder.owner_empire_id, order_costs):
			return ""

	var default_build_time := int(design_stats.get("build_time_days", build_class.get_build_time_days())) if not design_stats.is_empty() else build_class.get_build_time_days()
	var build_time_days := maxi(int(build_data.get("build_time_days", default_build_time)), 1)
	var project := {
		"project_id": project_id,
		"builder_unit_id": builder.unit_id,
		"build_class_id": build_class.class_id,
		"design_id": design_id,
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


func request_explore_system(
	unit_id: String,
	destination_system_id: String,
	system_details: Dictionary,
	eta_days: int = 1,
	options: Dictionary = {}
) -> String:
	var unit := get_unit(unit_id)
	if unit == null or not unit.can_explore_systems() or not unit.is_mobile():
		return ""
	if unit.fleet_id != "" or is_unit_constructing(unit_id):
		return ""
	if destination_system_id.is_empty() or system_details.is_empty():
		return ""
	if str(system_details.get("id", destination_system_id)) != destination_system_id:
		system_details = system_details.duplicate(true)
		system_details["id"] = destination_system_id

	var unit_class := get_unit_class(unit.class_id)
	if unit_class == null or unit_class.explorer_component == null:
		return ""
	var explorer_component = unit_class.explorer_component
	if explorer_component == null:
		return ""
	explorer_component.ensure_defaults()

	var targets: Array[Dictionary] = _build_exploration_targets(unit, destination_system_id, system_details, explorer_component, options)
	if targets.is_empty():
		return ""

	cancel_exploration_order_for_unit(unit_id)

	var order_id: String = str(options.get("order_id", "")).strip_edges()
	if order_id.is_empty():
		order_id = _generate_exploration_order_id()
	if _exploration_orders.has(order_id):
		return ""

	var order := {
		"order_id": order_id,
		"unit_id": unit.unit_id,
		"owner_empire_id": unit.owner_empire_id,
		"system_id": destination_system_id,
		"state": EXPLORATION_STATE_TRAVELLING if unit.current_system_id != destination_system_id else EXPLORATION_STATE_MOVING_TO_BODY,
		"target_index": 0,
		"targets": targets,
		"started_day_serial": _get_current_day_serial(),
		"updated_day_serial": _get_current_day_serial(),
		"completed_day_serial": 0,
		"command_revision": 0,
		"metadata": _sanitize_dictionary(options.get("metadata", {})),
	}

	_exploration_orders[order_id] = order
	_add_to_index(_exploration_order_ids_by_unit_id, unit.unit_id, order_id)
	_add_to_index(_exploration_order_ids_by_system, destination_system_id, order_id)
	_set_unit_exploration_metadata(unit, order_id)
	unit.command_revision += 1

	if unit.current_system_id != destination_system_id:
		if not _issue_unit_hyperlane_move(unit.unit_id, destination_system_id, maxi(eta_days, 1), false):
			_remove_exploration_order(order_id, true)
			return ""
	else:
		_start_exploration_target_move(order_id)

	unit_updated.emit(unit.unit_id)
	exploration_started.emit(order_id)
	return order_id


func cancel_exploration_order_for_unit(unit_id: String) -> bool:
	var order_id: String = _get_active_exploration_order_id(unit_id)
	if order_id.is_empty():
		return false
	return cancel_exploration_order(order_id)


func cancel_exploration_order(order_id: String) -> bool:
	return _remove_exploration_order(order_id, true)


func get_exploration_order(order_id: String) -> Dictionary:
	var order: Dictionary = _exploration_orders.get(order_id, {})
	if order.is_empty():
		return {}
	return _exploration_order_to_public(order)


func get_exploration_order_for_unit(unit_id: String) -> Dictionary:
	var order_id: String = _get_active_exploration_order_id(unit_id)
	if order_id.is_empty():
		return {}
	return get_exploration_order(order_id)


func get_exploration_order_ids_in_system(system_id: String) -> PackedStringArray:
	return _get_index_values(_exploration_order_ids_by_system, system_id)


func get_all_exploration_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for order_variant in _exploration_orders.values():
		var order: Dictionary = order_variant
		result.append(_exploration_order_to_public(order))
	return result


func is_unit_exploring(unit_id: String) -> bool:
	return not _get_active_exploration_order_id(unit_id).is_empty()


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
		if _is_resource_collector_class(candidate) and not _can_build_resource_collector_for_body(system_id, normalized_body, body_context):
			continue
		var option := _build_class_option(candidate, builder.owner_empire_id)
		option["build_tags"] = candidate_tags.duplicate()
		option["target_body_id"] = str(normalized_body.get("body_id", ""))
		option["target_body_type"] = str(normalized_body.get("body_type", ""))
		option["target_body_name"] = str(normalized_body.get("body_name", ""))
		result.append(option)

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var name_a := str(a.get("display_name", a.get("class_id", "")))
		var name_b := str(b.get("display_name", b.get("class_id", "")))
		if name_a == name_b:
			return str(a.get("class_id", "")) < str(b.get("class_id", ""))
		return name_a < name_b
	)
	return result


func _build_class_option(candidate: SpaceUnitClass, owner_empire_id: String) -> Dictionary:
	var option := {
		"class_id": candidate.class_id,
		"display_name": candidate.display_name,
		"unit_kind": candidate.unit_kind,
		"category": candidate.category,
		"build_time_days": candidate.get_build_time_days(),
		"build_costs": ResourceAmountDef.to_dict_array(candidate.get_build_costs()),
		"design_id": "",
	}
	var design_id := get_default_ship_design_id(owner_empire_id, candidate.class_id)
	if design_id.is_empty():
		return option
	var design_stats := get_compiled_ship_design_stats(design_id)
	if design_stats.is_empty():
		return option
	option["design_id"] = design_id
	option["build_time_days"] = maxi(int(design_stats.get("build_time_days", option["build_time_days"])), 1)
	option["build_costs"] = design_stats.get("build_costs", option["build_costs"])
	return option


func get_ship_build_options(builder_unit_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var builder := get_unit(builder_unit_id)
	if builder == null or not builder.can_build_units() or is_unit_constructing(builder_unit_id):
		return result
	var builder_class := get_unit_class(builder.class_id)
	if builder_class == null or builder_class.builder_component == null:
		return result

	for unit_class_variant in _unit_classes.values():
		var candidate: SpaceUnitClass = unit_class_variant
		if candidate == null or not candidate.is_buildable():
			continue
		if not candidate.get_build_tags().has(BUILD_TAG_SHIP):
			continue
		if not candidate.can_builder_construct(builder_class):
			continue
		var design_entries := _build_design_options_for_class(candidate, builder.owner_empire_id)
		if design_entries.is_empty():
			result.append(_build_class_option(candidate, builder.owner_empire_id))
		else:
			result.append_array(design_entries)

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var name_a := str(a.get("display_name", a.get("class_id", "")))
		var name_b := str(b.get("display_name", b.get("class_id", "")))
		if name_a == name_b:
			return str(a.get("class_id", "")) < str(b.get("class_id", ""))
		return name_a < name_b
	)
	return result


func _build_design_options_for_class(candidate: SpaceUnitClass, owner_empire_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _ship_design_catalog == null:
		return result
	var default_design_id := _ship_design_catalog.get_default_design_id(owner_empire_id, candidate.class_id)
	for design_id in _ship_design_catalog.get_design_ids_for_empire(owner_empire_id):
		var design := _ship_design_catalog.get_design(design_id)
		if design == null or design.class_id != candidate.class_id:
			continue
		var design_stats := get_compiled_ship_design_stats(design_id)
		if design_stats.is_empty():
			continue
		result.append({
			"class_id": candidate.class_id,
			"design_id": design_id,
			"display_name": design.display_name,
			"unit_kind": candidate.unit_kind,
			"category": candidate.category,
			"is_default_design": design_id == default_design_id,
			"build_time_days": maxi(int(design_stats.get("build_time_days", candidate.get_build_time_days())), 1),
			"build_costs": design_stats.get("build_costs", []),
		})
	return result


func request_build_ship(builder_unit_id: String, build_class_id: String, build_data: Dictionary = {}) -> String:
	var builder := get_unit(builder_unit_id)
	if builder == null:
		return ""
	var allowed := false
	for option in get_ship_build_options(builder_unit_id):
		if str(option.get("class_id", "")) == build_class_id:
			allowed = true
			break
	if not allowed:
		return ""

	var resolved_build_data := build_data.duplicate(true)
	if not resolved_build_data.has("local_position"):
		resolved_build_data["local_position"] = builder.local_position + _resolve_ship_spawn_offset(builder.unit_id, build_class_id)
	if not resolved_build_data.has("commit_cost"):
		resolved_build_data["commit_cost"] = true
	return issue_build_order(builder_unit_id, build_class_id, resolved_build_data)


func _resolve_ship_spawn_offset(builder_unit_id: String, build_class_id: String) -> Vector3:
	# Keep the dock site within CONSTRUCTION_SITE_ARRIVAL_DISTANCE so stationary
	# builders (shipyard stations) start in the "building" state immediately.
	var seed_key := "%s|%s|%d" % [builder_unit_id, build_class_id, _next_construction_project_id]
	var angle := float(absi(seed_key.hash()) % 3600) / 3600.0 * TAU
	return Vector3(cos(angle), 0.0, sin(angle)) * (CONSTRUCTION_SITE_ARRIVAL_DISTANCE * 0.8)


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
	return _issue_unit_hyperlane_move(unit_id, destination_system_id, eta_days, true)


func _issue_unit_hyperlane_move(unit_id: String, destination_system_id: String, eta_days: int = 1, cancel_active_exploration: bool = true) -> bool:
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
	if cancel_active_exploration:
		cancel_exploration_order_for_unit(unit_id)

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
	cancel_exploration_order_for_unit(unit_id)
	var changed := not unit.destination_system_id.is_empty() or unit.eta_days_remaining > 0
	unit.destination_system_id = ""
	unit.eta_days_remaining = 0
	if changed:
		unit.command_revision += 1
		unit_updated.emit(unit_id)
	return changed


func issue_unit_move(unit_id: String, target_position: Vector3) -> bool:
	return _issue_unit_move(unit_id, target_position, true)


func _issue_unit_move(unit_id: String, target_position: Vector3, cancel_active_exploration: bool = true) -> bool:
	var unit := get_unit(unit_id)
	if unit == null or not unit.fleet_id.is_empty() or not unit.is_mobile():
		return false
	if is_unit_constructing(unit_id):
		return false
	var unit_speed := get_unit_in_system_speed(unit)
	if unit_speed <= 0.0:
		return false
	if unit.local_position.is_equal_approx(target_position):
		return clear_unit_move(unit_id)
	if cancel_active_exploration:
		cancel_exploration_order_for_unit(unit_id)

	unit.previous_local_position = unit.local_position
	unit.target_local_position = target_position
	unit.velocity = (target_position - unit.local_position).normalized() * unit_speed
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
	cancel_exploration_order_for_unit(unit_id)
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


func set_unit_evasion_mode(unit_id: String, active: bool) -> bool:
	var unit := get_unit(unit_id)
	if unit == null:
		return false
	if bool(unit.metadata.get("evasion_active", false)) == active:
		return false
	unit.metadata["evasion_active"] = active
	unit.command_revision += 1
	unit_updated.emit(unit_id)
	return true


func set_fleet_evasion_mode(fleet_id: String, active: bool) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null or fleet.unit_ids.is_empty():
		return false
	var changed := false
	for unit_id in fleet.unit_ids:
		if set_unit_evasion_mode(unit_id, active):
			changed = true
	if changed:
		fleet.command_revision += 1
		fleet_updated.emit(fleet_id)
	return changed


func split_unit_to_new_fleet(unit_id: String) -> SpaceFleetRuntime:
	var unit := get_unit(unit_id)
	if unit == null or unit.fleet_id.is_empty() or not unit.can_join_fleet():
		return null
	var source_fleet := get_fleet(unit.fleet_id)
	if source_fleet == null:
		return null
	return create_fleet(unit.owner_empire_id, unit.current_system_id, [unit.unit_id], {
		"display_name": "%s Detachment" % unit.display_name,
		"controller_kind": source_fleet.controller_kind,
		"controller_peer_id": source_fleet.controller_peer_id,
		"ai_role": str(source_fleet.ai_role),
		"home_system_id": source_fleet.home_system_id,
		"local_position": unit.local_position,
	})


func debug_reinforce_fleet(fleet_id: String, template_unit_id: String = "") -> SpaceUnitRuntime:
	var fleet := get_fleet(fleet_id)
	if fleet == null or fleet.unit_ids.is_empty():
		return null
	var template_unit := get_unit(template_unit_id)
	if template_unit == null or not fleet.unit_ids.has(template_unit_id):
		for member_id in fleet.unit_ids:
			template_unit = get_unit(member_id)
			if template_unit != null:
				break
	if template_unit == null:
		return null

	var template_class := get_unit_class(template_unit.class_id)
	if template_class == null or not template_unit.can_join_fleet():
		return null

	var spawn_count := get_unit_ids_of_class(template_unit.class_id).size() + 1
	var spawn_position := fleet.local_position + Vector3(3.0 + float(fleet.unit_ids.size()), 0.0, 1.5)
	var reinforcement := spawn_unit(template_unit.class_id, fleet.owner_empire_id, fleet.current_system_id, {
		"display_name": "%s Reinforcement %02d" % [template_class.display_name, spawn_count],
		"controller_kind": fleet.controller_kind,
		"controller_peer_id": fleet.controller_peer_id,
		"ai_role": str(template_unit.ai_role),
		"local_position": spawn_position,
		"metadata": template_unit.metadata.duplicate(true),
	})
	if reinforcement == null:
		return null
	if not add_unit_to_fleet(reinforcement.unit_id, fleet_id):
		remove_unit(reinforcement.unit_id)
		return null
	return reinforcement


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
	cancel_exploration_order_for_unit(unit_id)

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
		"exploration_orders": [],
	}
	var unit_entries: Array[Dictionary] = []
	var fleet_entries: Array[Dictionary] = []
	var construction_entries: Array[Dictionary] = []
	var exploration_entries: Array[Dictionary] = []
	var day_progress := SimClock.get_day_progress() if SimClock != null and SimClock.has_method("get_day_progress") else 1.0

	for unit_id in get_unit_ids_in_system(system_id):
		var unit := get_unit(unit_id)
		if unit == null:
			continue
		var unit_class := get_unit_class(unit.class_id)
		var exploration_order_id: String = _get_active_exploration_order_id(unit.unit_id)
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
			"can_explore_systems": unit.can_explore_systems(),
			"construction_project_id": _get_active_construction_project_id(unit.unit_id),
			"exploration_order_id": exploration_order_id,
			"is_exploring": not exploration_order_id.is_empty(),
			"exploration_order": get_exploration_order(exploration_order_id) if not exploration_order_id.is_empty() else {},
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

	for order_id in get_exploration_order_ids_in_system(system_id):
		var exploration_order: Dictionary = _exploration_orders.get(order_id, {})
		if exploration_order.is_empty():
			continue
		exploration_entries.append(_exploration_order_to_renderable(exploration_order))

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
	renderables["exploration_orders"] = exploration_entries
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
	var exploration_order_snapshots: Array[Dictionary] = []

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

	for order_variant in _exploration_orders.values():
		var order: Dictionary = order_variant
		exploration_order_snapshots.append(_exploration_order_to_snapshot(order))

	return {
		"next_unit_id": _next_unit_id,
		"next_fleet_id": _next_fleet_id,
		"next_movement_order_id": _next_movement_order_id,
		"next_construction_project_id": _next_construction_project_id,
		"next_exploration_order_id": _next_exploration_order_id,
		"space_unit_classes": unit_class_snapshots,
		"space_units": unit_snapshots,
		"fleets": fleet_snapshots,
		"construction_projects": construction_project_snapshots,
		"exploration_orders": exploration_order_snapshots,
		"ship_designs": _ship_design_catalog.build_snapshot() if _ship_design_catalog != null else {},
		"combat": _combat_system.build_snapshot() if _combat_system != null else {},
		"hostility_mode": _hostility_mode,
		"next_ability_command_id": _next_ability_command_id,
	}


func load_snapshot(snapshot: Dictionary, clear_existing_state: bool = true) -> void:
	if clear_existing_state:
		reset_runtime_state(true)

	_next_unit_id = maxi(int(snapshot.get("next_unit_id", snapshot.get("next_ship_id", 1))), 1)
	_next_fleet_id = maxi(int(snapshot.get("next_fleet_id", 1)), 1)
	_next_movement_order_id = maxi(int(snapshot.get("next_movement_order_id", 1)), 1)
	_next_construction_project_id = maxi(int(snapshot.get("next_construction_project_id", 1)), 1)
	_next_exploration_order_id = maxi(int(snapshot.get("next_exploration_order_id", 1)), 1)

	for class_variant in snapshot.get("space_unit_classes", snapshot.get("ship_classes", [])):
		var class_data: Dictionary = class_variant
		var unit_class := SPACE_UNIT_CLASS_SCRIPT.from_dict(class_data) as SpaceUnitClass
		if unit_class == null:
			continue
		_unit_classes[unit_class.class_id] = unit_class

	if _ship_design_catalog != null:
		_ship_design_catalog.load_snapshot(snapshot.get("ship_designs", {}))
	if _combat_system != null:
		_combat_system.load_snapshot(snapshot.get("combat", {}))
	set_hostility_mode(str(snapshot.get("hostility_mode", HOSTILITY_FREE_FOR_ALL)))
	_next_ability_command_id = maxi(int(snapshot.get("next_ability_command_id", 1)), 1)

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

	for order_variant in snapshot.get("exploration_orders", []):
		var order_data: Dictionary = order_variant
		var order: Dictionary = _exploration_order_from_snapshot(order_data)
		var order_id := str(order.get("order_id", ""))
		if order_id.is_empty():
			continue
		_exploration_orders[order_id] = order

	_rebuild_indexes_and_economy_sources()


func _on_sim_day_tick(_date: Dictionary) -> void:
	var day_serial := _get_current_day_serial()
	_tick_fleet_hyperlane_travel()
	_tick_unit_hyperlane_travel()
	_tick_fleet_in_system_movement(day_serial)
	_tick_independent_unit_movement(day_serial)
	_tick_combat(day_serial)
	_tick_exploration_orders()
	_tick_construction_projects()


func _tick_combat(day_serial: int) -> void:
	if _combat_system == null:
		return
	var events: Array[Dictionary] = _combat_system.tick(day_serial)
	if events.is_empty():
		return
	for event in events:
		match str(event.get("type", "")):
			CombatSystem.EVENT_BATTLE_STARTED:
				battle_started.emit(str(event.get("battle_id", "")), str(event.get("system_id", "")))
			CombatSystem.EVENT_BATTLE_ENDED:
				battle_ended.emit(str(event.get("battle_id", "")), str(event.get("system_id", "")))
	combat_events.emit(events)


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
		var speed := get_unit_in_system_speed(unit)
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
		"design_id": str(project.get("design_id", "")),
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


func _tick_exploration_orders() -> void:
	var order_ids := PackedStringArray()
	for order_id_variant in _exploration_orders.keys():
		order_ids.append(str(order_id_variant))

	for order_id in order_ids:
		_tick_exploration_order(order_id)


func _tick_exploration_order(order_id: String) -> void:
	var order: Dictionary = _exploration_orders.get(order_id, {})
	if order.is_empty():
		return
	var unit_id := str(order.get("unit_id", ""))
	var unit := get_unit(unit_id)
	if unit == null or unit.fleet_id != "":
		_remove_exploration_order(order_id, true)
		return

	var target_system_id := str(order.get("system_id", ""))
	var state := _normalize_exploration_state(order.get("state", EXPLORATION_STATE_TRAVELLING))
	match state:
		EXPLORATION_STATE_TRAVELLING:
			if unit.current_system_id != target_system_id or not unit.destination_system_id.is_empty():
				return
			_start_exploration_target_move(order_id)
		EXPLORATION_STATE_MOVING_TO_BODY:
			if unit.current_system_id != target_system_id:
				_remove_exploration_order(order_id, true)
				return
			if unit.has_active_movement():
				return
			if _is_unit_at_current_exploration_target(unit, order):
				_start_exploration_target_scan(order_id)
		EXPLORATION_STATE_SCANNING_BODY:
			if unit.current_system_id != target_system_id:
				_remove_exploration_order(order_id, true)
				return
			_tick_exploration_target_scan(order_id)
		_:
			_remove_exploration_order(order_id, false)


func _start_exploration_target_move(order_id: String) -> bool:
	var order: Dictionary = _exploration_orders.get(order_id, {})
	if order.is_empty():
		return false
	var unit_id := str(order.get("unit_id", ""))
	var unit := get_unit(unit_id)
	if unit == null:
		return false
	var target: Dictionary = _get_current_exploration_target(order)
	if target.is_empty():
		_complete_exploration_order(order_id)
		return true

	order["state"] = EXPLORATION_STATE_MOVING_TO_BODY
	order["updated_day_serial"] = _get_current_day_serial()
	order["command_revision"] = int(order.get("command_revision", 0)) + 1
	_exploration_orders[order_id] = order

	var scan_position := SpaceUnitRuntime._variant_to_vector3(target.get("scan_position", target.get("local_position", Vector3.ZERO)))
	if unit.local_position.distance_to(scan_position) <= _get_exploration_arrival_distance(unit):
		_start_exploration_target_scan(order_id)
		return true

	if not _issue_unit_move(unit.unit_id, scan_position, false):
		_start_exploration_target_scan(order_id)
		return true
	exploration_updated.emit(order_id)
	return true


func _start_exploration_target_scan(order_id: String) -> bool:
	var order: Dictionary = _exploration_orders.get(order_id, {})
	if order.is_empty():
		return false
	var unit := get_unit(str(order.get("unit_id", "")))
	if unit == null:
		return false
	var target_index := int(order.get("target_index", 0))
	var targets: Array[Dictionary] = _get_exploration_targets(order)
	if target_index < 0 or target_index >= targets.size():
		_complete_exploration_order(order_id)
		return true

	var target: Dictionary = targets[target_index]
	unit.previous_local_position = unit.local_position
	unit.local_position = SpaceUnitRuntime._variant_to_vector3(target.get("scan_position", target.get("local_position", unit.local_position)))
	unit.target_local_position = unit.local_position
	unit.velocity = Vector3.ZERO
	unit.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
	unit.movement_order_id = 0
	unit.destination_system_id = ""
	unit.eta_days_remaining = 0
	unit.last_movement_day_serial = _get_current_day_serial()
	unit.command_revision += 1

	target["scan_started_day_serial"] = _get_current_day_serial()
	target["scan_days_remaining"] = maxi(int(target.get("scan_days_remaining", target.get("scan_days_total", 1))), 1)
	target["scanned"] = false
	targets[target_index] = target
	order["targets"] = targets
	order["state"] = EXPLORATION_STATE_SCANNING_BODY
	order["updated_day_serial"] = _get_current_day_serial()
	order["command_revision"] = int(order.get("command_revision", 0)) + 1
	_exploration_orders[order_id] = order
	unit_updated.emit(unit.unit_id)
	exploration_updated.emit(order_id)
	return true


func _tick_exploration_target_scan(order_id: String) -> void:
	var order: Dictionary = _exploration_orders.get(order_id, {})
	if order.is_empty():
		return
	var target_index := int(order.get("target_index", 0))
	var targets: Array[Dictionary] = _get_exploration_targets(order)
	if target_index < 0 or target_index >= targets.size():
		_complete_exploration_order(order_id)
		return

	var target: Dictionary = targets[target_index]
	target["scan_days_remaining"] = maxi(int(target.get("scan_days_remaining", 0)) - 1, 0)
	targets[target_index] = target
	order["targets"] = targets
	order["updated_day_serial"] = _get_current_day_serial()
	order["command_revision"] = int(order.get("command_revision", 0)) + 1
	_exploration_orders[order_id] = order
	exploration_updated.emit(order_id)

	var unit := get_unit(str(order.get("unit_id", "")))
	if unit != null:
		unit.command_revision += 1
		unit_updated.emit(unit.unit_id)

	if int(target.get("scan_days_remaining", 0)) <= 0:
		_complete_exploration_target_scan(order_id)


func _complete_exploration_target_scan(order_id: String) -> void:
	var order: Dictionary = _exploration_orders.get(order_id, {})
	if order.is_empty():
		return
	var unit_id := str(order.get("unit_id", ""))
	var target_index := int(order.get("target_index", 0))
	var targets: Array[Dictionary] = _get_exploration_targets(order)
	if target_index < 0 or target_index >= targets.size():
		_complete_exploration_order(order_id)
		return

	var target: Dictionary = targets[target_index]
	target["scanned"] = true
	target["scan_days_remaining"] = 0
	target["scan_completed_day_serial"] = _get_current_day_serial()
	targets[target_index] = target
	order["targets"] = targets
	order["target_index"] = target_index + 1
	order["updated_day_serial"] = _get_current_day_serial()
	order["command_revision"] = int(order.get("command_revision", 0)) + 1
	_exploration_orders[order_id] = order

	exploration_scan_completed.emit(
		order_id,
		unit_id,
		str(order.get("system_id", "")),
		str(target.get("body_id", ""))
	)

	if target_index + 1 >= targets.size():
		_complete_exploration_order(order_id)
		return
	_start_exploration_target_move(order_id)


func _complete_exploration_order(order_id: String) -> void:
	var order: Dictionary = _exploration_orders.get(order_id, {})
	if order.is_empty():
		return
	var unit_id := str(order.get("unit_id", ""))
	var system_id := str(order.get("system_id", ""))
	order["state"] = EXPLORATION_STATE_COMPLETED
	order["completed_day_serial"] = _get_current_day_serial()
	order["updated_day_serial"] = _get_current_day_serial()
	_exploration_orders[order_id] = order
	_remove_exploration_order(order_id, false)
	exploration_completed.emit(order_id, unit_id, system_id)


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


func _remove_exploration_order(order_id: String, emit_cancelled: bool) -> bool:
	var order: Dictionary = _exploration_orders.get(order_id, {})
	if order.is_empty():
		return false

	var unit_id := str(order.get("unit_id", ""))
	var system_id := str(order.get("system_id", ""))
	_remove_from_index(_exploration_order_ids_by_unit_id, unit_id, order_id)
	_remove_from_index(_exploration_order_ids_by_system, system_id, order_id)
	_exploration_orders.erase(order_id)

	var unit := get_unit(unit_id)
	if unit != null:
		_clear_unit_exploration_metadata(unit, order_id)
		if emit_cancelled:
			_stop_unit_for_exploration(unit)
		unit.command_revision += 1
		unit_updated.emit(unit.unit_id)
	if emit_cancelled:
		exploration_cancelled.emit(order_id)
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


func _stop_unit_for_exploration(unit: SpaceUnitRuntime) -> void:
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


func _is_resource_collector_class(unit_class: SpaceUnitClass) -> bool:
	if unit_class == null:
		return false
	return unit_class.class_id == RESOURCE_COLLECTOR_STATION_CLASS_ID or bool(unit_class.metadata.get("requires_resource_deposit", false))


func _can_build_resource_collector_for_body(system_id: String, normalized_body: Dictionary, raw_body_context: Dictionary) -> bool:
	var body_id := str(normalized_body.get("body_id", "")).strip_edges()
	var body_type := str(normalized_body.get("body_type", "")).strip_edges()
	if body_id.is_empty() or body_type.is_empty():
		return false
	if _body_has_completed_resource_collector(system_id, body_id, body_type):
		return false
	if _body_has_active_resource_collector_project(system_id, body_id, body_type):
		return false
	return _body_has_resource_deposits(system_id, normalized_body, raw_body_context)


func _body_has_resource_deposits(system_id: String, normalized_body: Dictionary, raw_body_context: Dictionary) -> bool:
	if EconomyManager == null or not EconomyManager.has_method("preview_body_deposit_income"):
		return false
	var body_record := _resolve_resource_deposit_body_record(normalized_body, raw_body_context)
	if body_record.is_empty():
		return false
	var galaxy_seed := int(raw_body_context.get("generated_seed", body_record.get("generated_seed", 0)))
	var preview_map: Dictionary = EconomyManager.preview_body_deposit_income(galaxy_seed, system_id, body_record)
	return not preview_map.is_empty()


func _resolve_resource_deposit_body_record(normalized_body: Dictionary, raw_body_context: Dictionary) -> Dictionary:
	var context_record: Variant = raw_body_context.get("body_record", {})
	if context_record is Dictionary and not (context_record as Dictionary).is_empty():
		return (context_record as Dictionary).duplicate(true)

	var body_record := {
		"id": str(normalized_body.get("body_id", "")),
		"name": str(normalized_body.get("body_name", normalized_body.get("body_id", ""))),
		"type": str(normalized_body.get("body_type", "")),
		"size": float(normalized_body.get("size", 1.0)),
	}
	for key in ["resource_deposit_component", "resource_richness_points", "resource_richness", "habitability_points", "habitability", "is_colonizable", "kind", "special_type"]:
		if raw_body_context.has(key):
			body_record[key] = raw_body_context.get(key)
	return body_record


func _body_has_completed_resource_collector(system_id: String, body_id: String, body_type: String) -> bool:
	for unit_id in get_unit_ids_in_system(system_id):
		var unit := get_unit(unit_id)
		if unit == null or unit.class_id != RESOURCE_COLLECTOR_STATION_CLASS_ID:
			continue
		if _metadata_targets_body(unit.metadata, body_id, body_type):
			return true
	return false


func _body_has_active_resource_collector_project(system_id: String, body_id: String, body_type: String) -> bool:
	for project_variant in _construction_projects.values():
		var project: Dictionary = project_variant
		if str(project.get("system_id", "")) != system_id:
			continue
		if str(project.get("build_class_id", "")) != RESOURCE_COLLECTOR_STATION_CLASS_ID:
			continue
		if str(project.get("target_body_id", "")) != body_id:
			continue
		if str(project.get("target_body_type", "")) != body_type:
			continue
		return true
	return false


func _metadata_targets_body(metadata: Dictionary, body_id: String, body_type: String) -> bool:
	return str(metadata.get("target_body_id", "")) == body_id and str(metadata.get("target_body_type", "")) == body_type


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
	var progress_ratio := clampf(float(days_total - days_remaining) / float(days_total), 0.0, 1.0)
	var build_class_id := str(project.get("build_class_id", ""))
	var build_class := get_unit_class(build_class_id)
	var builder := get_unit(str(project.get("builder_unit_id", "")))
	return {
		"project_id": str(project.get("project_id", "")),
		"builder_unit_id": str(project.get("builder_unit_id", "")),
		"builder_name": builder.display_name if builder != null else str(project.get("builder_unit_id", "")),
		"build_class_id": build_class_id,
		"class_display_name": build_class.display_name if build_class != null else build_class_id,
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
		"progress_ratio": progress_ratio,
		"progress_percent": int(round(progress_ratio * 100.0)),
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
		"design_id": str(data.get("design_id", "")),
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


func _build_exploration_targets(
	unit: SpaceUnitRuntime,
	system_id: String,
	system_details: Dictionary,
	explorer_component,
	options: Dictionary
) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if unit == null or explorer_component == null:
		return targets
	var galaxy_seed := int(options.get("galaxy_seed", system_details.get("generated_seed", system_details.get("seed", 0))))

	for star_variant in system_details.get("stars", []):
		if star_variant is not Dictionary:
			continue
		var star_target: Dictionary = _normalize_exploration_body_record(star_variant, "star")
		if star_target.is_empty() or not explorer_component.supports_body_type(str(star_target.get("body_type", ""))):
			continue
		targets.append(_build_exploration_target(unit, system_id, star_target, explorer_component, galaxy_seed))

	for orbital_variant in system_details.get("orbitals", []):
		if orbital_variant is not Dictionary:
			continue
		var orbital: Dictionary = orbital_variant
		var orbital_target: Dictionary = _normalize_exploration_body_record(orbital, str(orbital.get("type", "planet")))
		if orbital_target.is_empty() or not explorer_component.supports_body_type(str(orbital_target.get("body_type", ""))):
			continue
		targets.append(_build_exploration_target(unit, system_id, orbital_target, explorer_component, galaxy_seed))

	return _sort_exploration_targets_by_route(targets, unit.local_position)


func _build_exploration_target(
	unit: SpaceUnitRuntime,
	system_id: String,
	body_record: Dictionary,
	explorer_component,
	galaxy_seed: int
) -> Dictionary:
	var body_id := str(body_record.get("body_id", "")).strip_edges()
	var scan_days: int = int(explorer_component.get_scan_days(unit.unit_id, system_id, body_id, galaxy_seed))
	var body_position := _get_body_orbit_position(body_record)
	var scan_position := _resolve_exploration_scan_position(unit.unit_id, system_id, body_record, explorer_component, galaxy_seed)
	return {
		"body_id": body_id,
		"body_name": str(body_record.get("body_name", body_id)),
		"body_type": str(body_record.get("body_type", "")),
		"body_position": body_position,
		"scan_position": scan_position,
		"local_position": scan_position,
		"scan_days_total": scan_days,
		"scan_days_remaining": scan_days,
		"scan_started_day_serial": 0,
		"scan_completed_day_serial": 0,
		"scanned": false,
	}


func _normalize_exploration_body_record(body_variant: Variant, fallback_body_type: String) -> Dictionary:
	if body_variant is not Dictionary:
		return {}
	var body: Dictionary = body_variant
	var body_type := str(body.get("type", fallback_body_type)).strip_edges()
	if body_type.is_empty():
		body_type = fallback_body_type
	var body_id := str(body.get("id", body.get("name", body_type))).strip_edges()
	if body_id.is_empty() or body_type.is_empty():
		return {}
	var normalized := body.duplicate(true)
	normalized["body_id"] = body_id
	normalized["body_name"] = str(body.get("name", body_id))
	normalized["body_type"] = body_type
	return normalized


func _sort_exploration_targets_by_route(targets: Array[Dictionary], start_position: Vector3) -> Array[Dictionary]:
	var remaining: Array[Dictionary] = targets.duplicate(true)
	var ordered: Array[Dictionary] = []
	var cursor := start_position
	while not remaining.is_empty():
		var best_index := 0
		var best_distance := INF
		var best_id := ""
		for index in range(remaining.size()):
			var candidate: Dictionary = remaining[index]
			var candidate_position := SpaceUnitRuntime._variant_to_vector3(candidate.get("scan_position", candidate.get("local_position", Vector3.ZERO)))
			var candidate_distance := cursor.distance_to(candidate_position)
			var candidate_id := str(candidate.get("body_id", ""))
			if candidate_distance < best_distance or (is_equal_approx(candidate_distance, best_distance) and (best_id.is_empty() or candidate_id < best_id)):
				best_index = index
				best_distance = candidate_distance
				best_id = candidate_id
		var selected: Dictionary = remaining[best_index]
		ordered.append(selected)
		cursor = SpaceUnitRuntime._variant_to_vector3(selected.get("scan_position", selected.get("local_position", cursor)))
		remaining.remove_at(best_index)
	return ordered


func _resolve_exploration_scan_position(
	unit_id: String,
	system_id: String,
	body_record: Dictionary,
	explorer_component,
	galaxy_seed: int
) -> Vector3:
	var body_position := _get_body_orbit_position(body_record)
	var body_size := maxf(float(body_record.get("size", body_record.get("scale", 1.0))), 1.0)
	var radius := maxf(explorer_component.scan_offset_radius, body_size * 2.0 + 2.0)
	if str(body_record.get("body_type", "")) == "asteroid_belt":
		radius = maxf(radius, float(body_record.get("orbit_width", 0.0)) * 0.18 + 3.0)
	var hash_value := _stable_hash("%d:%s:%s:%s:scan_position" % [
		galaxy_seed,
		unit_id,
		system_id,
		str(body_record.get("body_id", "")),
	])
	var angle := float(absi(hash_value) % 3600) / 3600.0 * TAU
	return body_position + Vector3(cos(angle) * radius, 0.35, sin(angle) * radius)


func _get_body_orbit_position(body_record: Dictionary) -> Vector3:
	if body_record.has("local_position"):
		return SpaceUnitRuntime._variant_to_vector3(body_record.get("local_position", Vector3.ZERO))
	if body_record.has("body_position"):
		return SpaceUnitRuntime._variant_to_vector3(body_record.get("body_position", Vector3.ZERO))
	var radius := float(body_record.get("orbit_radius", 0.0))
	var angle := float(body_record.get("orbit_angle", 0.0))
	var vertical_offset := float(body_record.get("vertical_offset", 0.0))
	return Vector3(cos(angle) * radius, vertical_offset, sin(angle) * radius)


func _get_current_exploration_target(order: Dictionary) -> Dictionary:
	var target_index := int(order.get("target_index", 0))
	var targets: Array[Dictionary] = _get_exploration_targets(order)
	if target_index < 0 or target_index >= targets.size():
		return {}
	return targets[target_index].duplicate(true)


func _get_exploration_targets(order: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var targets_variant: Variant = order.get("targets", [])
	if targets_variant is not Array:
		return result
	for target_variant in targets_variant:
		if target_variant is not Dictionary:
			continue
		result.append((target_variant as Dictionary).duplicate(true))
	return result


func _is_unit_at_current_exploration_target(unit: SpaceUnitRuntime, order: Dictionary) -> bool:
	if unit == null:
		return false
	var target: Dictionary = _get_current_exploration_target(order)
	if target.is_empty():
		return true
	var scan_position := SpaceUnitRuntime._variant_to_vector3(target.get("scan_position", target.get("local_position", Vector3.ZERO)))
	return unit.local_position.distance_to(scan_position) <= _get_exploration_arrival_distance(unit)


func _get_exploration_arrival_distance(unit: SpaceUnitRuntime) -> float:
	var unit_class := get_unit_class(unit.class_id) if unit != null else null
	if unit_class == null or unit_class.explorer_component == null:
		return 0.45
	var explorer_component = unit_class.explorer_component
	if explorer_component == null:
		return 0.45
	explorer_component.ensure_defaults()
	return explorer_component.arrival_distance


func _exploration_order_to_public(order: Dictionary) -> Dictionary:
	return _exploration_order_to_renderable(order)


func _exploration_order_to_renderable(order: Dictionary) -> Dictionary:
	var targets: Array[Dictionary] = _get_exploration_targets(order)
	var target_index := clampi(int(order.get("target_index", 0)), 0, maxi(targets.size(), 1))
	var current_target: Dictionary = {}
	if target_index >= 0 and target_index < targets.size():
		current_target = targets[target_index]
	var unit := get_unit(str(order.get("unit_id", "")))
	var progress_ratio := _get_exploration_progress_ratio(order)
	var scan_progress_ratio := _get_exploration_current_scan_progress_ratio(order)
	return {
		"order_id": str(order.get("order_id", "")),
		"unit_id": str(order.get("unit_id", "")),
		"unit_name": unit.display_name if unit != null else str(order.get("unit_id", "")),
		"owner_empire_id": str(order.get("owner_empire_id", "")),
		"system_id": str(order.get("system_id", "")),
		"state": _normalize_exploration_state(order.get("state", EXPLORATION_STATE_TRAVELLING)),
		"state_label": _format_exploration_state(order.get("state", EXPLORATION_STATE_TRAVELLING)),
		"target_index": target_index,
		"target_count": targets.size(),
		"current_target_id": str(current_target.get("body_id", "")),
		"current_target_name": str(current_target.get("body_name", "")),
		"current_target_type": str(current_target.get("body_type", "")),
		"scan_days_total": int(current_target.get("scan_days_total", 0)),
		"scan_days_remaining": int(current_target.get("scan_days_remaining", 0)),
		"is_scanning": _normalize_exploration_state(order.get("state", "")) == EXPLORATION_STATE_SCANNING_BODY,
		"progress_ratio": progress_ratio,
		"progress_percent": int(round(progress_ratio * 100.0)),
		"scan_progress_ratio": scan_progress_ratio,
		"scan_progress_percent": int(round(scan_progress_ratio * 100.0)),
		"local_position": SpaceUnitRuntime._variant_to_vector3(current_target.get("body_position", current_target.get("local_position", Vector3.ZERO))) if not current_target.is_empty() else Vector3.ZERO,
		"scan_position": SpaceUnitRuntime._variant_to_vector3(current_target.get("scan_position", current_target.get("local_position", Vector3.ZERO))) if not current_target.is_empty() else Vector3.ZERO,
		"unit_local_position": unit.local_position if unit != null else Vector3.ZERO,
		"targets": targets,
		"started_day_serial": int(order.get("started_day_serial", 0)),
		"updated_day_serial": int(order.get("updated_day_serial", 0)),
		"command_revision": int(order.get("command_revision", 0)),
		"metadata": order.get("metadata", {}).duplicate(true) if order.get("metadata", {}) is Dictionary else {},
	}


func _get_exploration_progress_ratio(order: Dictionary) -> float:
	var targets: Array[Dictionary] = _get_exploration_targets(order)
	if targets.is_empty():
		return 0.0
	var completed := 0.0
	for target_index in range(targets.size()):
		var target: Dictionary = targets[target_index]
		if bool(target.get("scanned", false)):
			completed += 1.0
			continue
		if target_index == int(order.get("target_index", 0)):
			completed += _get_target_scan_progress_ratio(target, _normalize_exploration_state(order.get("state", "")))
	return clampf(completed / float(targets.size()), 0.0, 1.0)


func _get_exploration_current_scan_progress_ratio(order: Dictionary) -> float:
	var current_target: Dictionary = _get_current_exploration_target(order)
	if current_target.is_empty():
		return 0.0
	return _get_target_scan_progress_ratio(current_target, _normalize_exploration_state(order.get("state", "")))


func _get_target_scan_progress_ratio(target: Dictionary, state: String) -> float:
	if bool(target.get("scanned", false)):
		return 1.0
	if state != EXPLORATION_STATE_SCANNING_BODY:
		return 0.0
	var total := maxi(int(target.get("scan_days_total", 1)), 1)
	var remaining := clampi(int(target.get("scan_days_remaining", total)), 0, total)
	return clampf(float(total - remaining) / float(total), 0.0, 1.0)


func _exploration_order_to_snapshot(order: Dictionary) -> Dictionary:
	var snapshot := order.duplicate(true)
	var snapshot_targets: Array[Dictionary] = []
	for target in _get_exploration_targets(order):
		var snapshot_target := target.duplicate(true)
		snapshot_target["body_position"] = SpaceUnitRuntime._vector3_to_dict(SpaceUnitRuntime._variant_to_vector3(target.get("body_position", Vector3.ZERO)))
		snapshot_target["scan_position"] = SpaceUnitRuntime._vector3_to_dict(SpaceUnitRuntime._variant_to_vector3(target.get("scan_position", Vector3.ZERO)))
		snapshot_target["local_position"] = SpaceUnitRuntime._vector3_to_dict(SpaceUnitRuntime._variant_to_vector3(target.get("local_position", target.get("scan_position", Vector3.ZERO))))
		snapshot_targets.append(snapshot_target)
	snapshot["targets"] = snapshot_targets
	snapshot["metadata"] = order.get("metadata", {}).duplicate(true) if order.get("metadata", {}) is Dictionary else {}
	return snapshot


func _exploration_order_from_snapshot(data: Dictionary) -> Dictionary:
	var order_id := str(data.get("order_id", "")).strip_edges()
	if order_id.is_empty():
		return {}
	var targets: Array[Dictionary] = []
	var targets_variant: Variant = data.get("targets", [])
	if targets_variant is Array:
		for target_variant in targets_variant:
			if target_variant is not Dictionary:
				continue
			var target: Dictionary = (target_variant as Dictionary).duplicate(true)
			target["body_position"] = SpaceUnitRuntime._variant_to_vector3(target.get("body_position", Vector3.ZERO))
			target["scan_position"] = SpaceUnitRuntime._variant_to_vector3(target.get("scan_position", target.get("local_position", Vector3.ZERO)))
			target["local_position"] = SpaceUnitRuntime._variant_to_vector3(target.get("local_position", target.get("scan_position", Vector3.ZERO)))
			targets.append(target)
	return {
		"order_id": order_id,
		"unit_id": str(data.get("unit_id", "")),
		"owner_empire_id": str(data.get("owner_empire_id", "")),
		"system_id": str(data.get("system_id", "")),
		"state": _normalize_exploration_state(data.get("state", EXPLORATION_STATE_TRAVELLING)),
		"target_index": clampi(int(data.get("target_index", 0)), 0, maxi(targets.size(), 1)),
		"targets": targets,
		"started_day_serial": maxi(int(data.get("started_day_serial", 0)), 0),
		"updated_day_serial": maxi(int(data.get("updated_day_serial", 0)), 0),
		"completed_day_serial": maxi(int(data.get("completed_day_serial", 0)), 0),
		"command_revision": maxi(int(data.get("command_revision", 0)), 0),
		"metadata": _sanitize_dictionary(data.get("metadata", {})),
	}


func _normalize_exploration_state(value: Variant) -> String:
	var state := str(value).strip_edges()
	match state:
		EXPLORATION_STATE_TRAVELLING, EXPLORATION_STATE_MOVING_TO_BODY, EXPLORATION_STATE_SCANNING_BODY, EXPLORATION_STATE_COMPLETED:
			return state
		_:
			return EXPLORATION_STATE_TRAVELLING


func _format_exploration_state(value: Variant) -> String:
	match _normalize_exploration_state(value):
		EXPLORATION_STATE_TRAVELLING:
			return "Anflug"
		EXPLORATION_STATE_MOVING_TO_BODY:
			return "Positioniert"
		EXPLORATION_STATE_SCANNING_BODY:
			return "Scannt"
		EXPLORATION_STATE_COMPLETED:
			return "Abgeschlossen"
		_:
			return "Erkundet"


func _get_active_construction_project_id(builder_unit_id: String) -> String:
	var project_ids := _get_index_values(_construction_project_ids_by_builder_unit_id, builder_unit_id)
	if project_ids.is_empty():
		return ""
	return project_ids[0]


func _get_active_exploration_order_id(unit_id: String) -> String:
	var order_ids := _get_index_values(_exploration_order_ids_by_unit_id, unit_id)
	if order_ids.is_empty():
		return ""
	return order_ids[0]


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


func _set_unit_exploration_metadata(unit: SpaceUnitRuntime, order_id: String) -> void:
	if unit == null:
		return
	var metadata := unit.metadata.duplicate(true)
	metadata["active_exploration_order_id"] = order_id
	metadata["exploration_active"] = true
	unit.metadata = metadata


func _clear_unit_exploration_metadata(unit: SpaceUnitRuntime, order_id: String) -> void:
	if unit == null:
		return
	if str(unit.metadata.get("active_exploration_order_id", "")) != order_id:
		return
	var metadata := unit.metadata.duplicate(true)
	metadata.erase("active_exploration_order_id")
	metadata["exploration_active"] = false
	unit.metadata = metadata


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


func _generate_exploration_order_id() -> String:
	var order_id := "exploration_%06d" % _next_exploration_order_id
	_next_exploration_order_id += 1
	return order_id


func _stable_hash(value: String) -> int:
	var hash_value := 2166136261
	for index in range(value.length()):
		hash_value = int((hash_value ^ value.unicode_at(index)) * 16777619) & 0x7fffffff
	return hash_value


func _rebuild_indexes_and_economy_sources() -> void:
	_unit_ids_by_owner.clear()
	_unit_ids_by_system.clear()
	_unit_ids_by_class.clear()
	_fleet_ids_by_owner.clear()
	_fleet_ids_by_system.clear()
	_construction_project_ids_by_builder_unit_id.clear()
	_construction_project_ids_by_system.clear()
	_exploration_order_ids_by_unit_id.clear()
	_exploration_order_ids_by_system.clear()

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

	for order_variant in _exploration_orders.values():
		var order: Dictionary = order_variant
		var order_id := str(order.get("order_id", ""))
		var unit_id := str(order.get("unit_id", ""))
		var system_id := str(order.get("system_id", ""))
		if order_id.is_empty() or unit_id.is_empty() or system_id.is_empty():
			continue
		_add_to_index(_exploration_order_ids_by_unit_id, unit_id, order_id)
		_add_to_index(_exploration_order_ids_by_system, system_id, order_id)
		var explorer := get_unit(unit_id)
		if explorer != null:
			_set_unit_exploration_metadata(explorer, order_id)


func _sync_unit_economy_source(unit: SpaceUnitRuntime) -> void:
	if unit == null:
		return

	var source_id := _get_unit_source_id(unit.unit_id)
	var unit_class := get_unit_class(unit.class_id)
	if EconomyManager == null or unit_class == null or unit.owner_empire_id.is_empty():
		_remove_unit_economy_source(unit.unit_id)
		return

	var upkeep_costs := _get_unit_monthly_upkeep(unit, unit_class)
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
	var collector_source_id := "resource_collector:%s" % unit_id
	if EconomyManager.has_source(collector_source_id):
		EconomyManager.remove_source(collector_source_id)


func _get_unit_source_id(unit_id: String) -> String:
	return "%s%s" % [UNIT_SOURCE_PREFIX, unit_id]


func _get_unit_monthly_upkeep(unit: SpaceUnitRuntime, unit_class: SpaceUnitClass) -> Array[ResourceAmountDef]:
	if unit != null and not unit.design_id.is_empty():
		var design_stats := get_compiled_ship_design_stats(unit.design_id)
		if not design_stats.is_empty():
			return ResourceAmountDef.normalize_array(design_stats.get("monthly_upkeep", []))
	if unit_class == null:
		return []
	return unit_class.get_monthly_upkeep()


func _merge_amount_defs_into_map(target: Dictionary, amounts: Array[ResourceAmountDef]) -> void:
	for amount in amounts:
		if amount == null or amount.resource_id.is_empty() or amount.milliunits == 0:
			continue
		target[amount.resource_id] = int(target.get(amount.resource_id, 0)) + amount.milliunits


func get_unit_in_system_speed(unit: SpaceUnitRuntime) -> float:
	if unit == null:
		return 0.0
	var unit_class := get_unit_class(unit.class_id)
	if unit_class == null or not unit_class.has_mobility():
		return 0.0
	if not unit.design_id.is_empty():
		var design_stats := get_compiled_ship_design_stats(unit.design_id)
		var design_speed := float(design_stats.get("cruise_speed", -1.0))
		if design_speed >= 0.0:
			return design_speed
	return unit_class.get_in_system_speed()


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
		speed = minf(speed, get_unit_in_system_speed(unit))
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
