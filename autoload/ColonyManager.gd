extends Node

const SPECIES_LIBRARY_SCRIPT := preload("res://core/empire/species/SpeciesLibrary.gd")
const SPECIES_RUNTIME_SCRIPT := preload("res://core/economy/SpeciesRuntime.gd")
const COLONY_RUNTIME_SCRIPT := preload("res://core/economy/ColonyRuntime.gd")
const POP_UNIT_RUNTIME_SCRIPT := preload("res://core/economy/PopUnitRuntime.gd")
const RESOURCE_AMOUNT_DEF_SCRIPT := preload("res://core/economy/ResourceAmountDef.gd")

const JOB_DEFINITION_PATH := "res://core/economy/jobs/jobs.cfg"
const BUILDING_DEFINITION_PATH := "res://core/economy/buildings/buildings.cfg"
const TRAIT_DEFINITION_PATH := "res://core/empire/species/traits/traits.cfg"
const STARTING_POP_UNIT_COUNT := 3
const POP_UNIT_SIZE := 1000
const CAPITAL_BUILDING_IDS := ["capital_hub", "basic_farm", "basic_reactor", "basic_extractor"]
const BUILDING_GRID_RADIUS := 3
const STARTER_BUILDING_SLOT_IDS := {
	"capital_hub": "q0_r0",
	"basic_farm": "q1_r0",
	"basic_reactor": "q0_r1",
	"basic_extractor": "q-1_r1",
}

signal runtime_reset
signal species_registry_changed(empire_id: String)
signal colony_created(colony_id: String)
signal colony_updated(colony_id: String)

var _bootstrapped: bool = false
var _job_ids: Array[String] = []
var _jobs_by_id: Dictionary = {}
var _building_ids: Array[String] = []
var _buildings_by_id: Dictionary = {}
var _traits_by_id: Dictionary = {}
var _species_by_id: Dictionary = {}
var _species_ids_by_empire_id: Dictionary = {}
var _colonies_by_id: Dictionary = {}
var _colony_ids_by_system_id: Dictionary = {}
var _colony_ids_by_empire_id: Dictionary = {}
var _colony_stats_cache: Dictionary = {}
var _colony_economy_cache: Dictionary = {}
var _last_build_error_by_colony_id: Dictionary = {}
var _building_grid_slot_ids_cache: PackedStringArray = PackedStringArray()


func _ready() -> void:
	load_definitions()


func is_bootstrapped() -> bool:
	return _bootstrapped


func load_definitions() -> void:
	_load_job_definitions()
	_load_building_definitions()
	_load_trait_definitions()
	_colony_stats_cache.clear()
	_colony_economy_cache.clear()
	for colony_variant in _colonies_by_id.values():
		if colony_variant == null:
			continue
		_refresh_colony_runtime_cache(colony_variant)
		sync_colony_source(colony_variant.colony_id)


func reset_runtime_state(clear_definitions: bool = false) -> void:
	_bootstrapped = false
	_species_by_id.clear()
	_species_ids_by_empire_id.clear()
	_colonies_by_id.clear()
	_colony_ids_by_system_id.clear()
	_colony_ids_by_empire_id.clear()
	_colony_stats_cache.clear()
	_colony_economy_cache.clear()
	_last_build_error_by_colony_id.clear()
	if clear_definitions:
		_job_ids.clear()
		_jobs_by_id.clear()
		_building_ids.clear()
		_buildings_by_id.clear()
		_traits_by_id.clear()
	runtime_reset.emit()


func bootstrap(empire_records_variant: Variant, capital_context: Dictionary = {}) -> void:
	if _jobs_by_id.is_empty() or _buildings_by_id.is_empty() or _traits_by_id.is_empty():
		load_definitions()

	reset_runtime_state(false)
	var empire_records := _normalize_empire_records(empire_records_variant)
	for empire_index in range(empire_records.size()):
		_register_primary_species(empire_records[empire_index], empire_index)

	_bootstrapped = true
	if not capital_context.is_empty():
		create_capital_colony(capital_context)


func register_known_species(empire_id: String, species_data: Dictionary) -> String:
	empire_id = empire_id.strip_edges()
	if empire_id.is_empty():
		return ""

	var species = SPECIES_RUNTIME_SCRIPT.from_dict(species_data)
	species.empire_id = empire_id
	species.ensure_defaults(_species_by_id.size())
	_species_by_id[species.species_id] = species

	var known_species_ids: PackedStringArray = _species_ids_by_empire_id.get(empire_id, PackedStringArray())
	if not known_species_ids.has(species.species_id):
		known_species_ids.append(species.species_id)
	_species_ids_by_empire_id[empire_id] = known_species_ids
	species_registry_changed.emit(empire_id)
	return species.species_id


func create_capital_colony(capital_context: Dictionary) -> String:
	var empire_id := str(capital_context.get("empire_id", "")).strip_edges()
	var system_id := str(capital_context.get("system_id", "")).strip_edges()
	var planet_record: Dictionary = capital_context.get("planet", {}).duplicate(true)
	var planet_orbital_id := str(capital_context.get("planet_orbital_id", planet_record.get("id", ""))).strip_edges()
	if empire_id.is_empty() or system_id.is_empty() or planet_orbital_id.is_empty():
		return ""

	var primary_species_id := get_primary_species_id_for_empire(empire_id)
	if primary_species_id.is_empty():
		primary_species_id = register_known_species(empire_id, _build_fallback_species_data(empire_id, 0))
	if primary_species_id.is_empty():
		return ""

	var colony = COLONY_RUNTIME_SCRIPT.new()
	colony.colony_id = _build_colony_id(empire_id, system_id, planet_orbital_id)
	colony.empire_id = empire_id
	colony.system_id = system_id
	colony.planet_orbital_id = planet_orbital_id
	colony.name = str(capital_context.get("colony_name", planet_record.get("name", "Capital"))).strip_edges()
	colony.is_capital = true
	colony.buildings = PackedStringArray(CAPITAL_BUILDING_IDS)
	colony.building_slots = _build_starter_building_slots()
	colony.planet_record = planet_record.duplicate(true)
	colony.pop_units = []
	for pop_index in range(STARTING_POP_UNIT_COUNT):
		var pop_unit = POP_UNIT_RUNTIME_SCRIPT.new()
		pop_unit.pop_unit_id = "%s:pop_%02d" % [colony.colony_id, pop_index]
		pop_unit.species_id = primary_species_id
		pop_unit.size = POP_UNIT_SIZE
		pop_unit.assigned_job_id = ""
		pop_unit.ensure_defaults(pop_index)
		colony.pop_units.append(pop_unit)
	colony.ensure_defaults(_colonies_by_id.size())
	_refresh_colony_runtime_cache(colony)

	_register_colony(colony)
	sync_colony_source(colony.colony_id)
	colony_created.emit(colony.colony_id)
	colony_updated.emit(colony.colony_id)
	return colony.colony_id


func get_primary_species_id_for_empire(empire_id: String) -> String:
	var species_ids: PackedStringArray = _species_ids_by_empire_id.get(empire_id, PackedStringArray())
	if species_ids.is_empty():
		return ""
	return species_ids[0]


func get_known_species_for_empire(empire_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var species_ids: PackedStringArray = _species_ids_by_empire_id.get(empire_id, PackedStringArray())
	for species_id in species_ids:
		var species = _species_by_id.get(species_id, null)
		if species == null:
			continue
		result.append(species.to_dict())
	return result


func get_species(species_id: String) -> Dictionary:
	var species = _species_by_id.get(species_id, null)
	if species == null:
		return {}
	return species.to_dict()


func get_colony_ids_for_system(system_id: String, empire_id: String = "") -> PackedStringArray:
	var result := PackedStringArray()
	var colony_ids: PackedStringArray = _colony_ids_by_system_id.get(system_id, PackedStringArray())
	for colony_id in colony_ids:
		var colony = _colonies_by_id.get(colony_id, null)
		if colony == null:
			continue
		if not empire_id.is_empty() and colony.empire_id != empire_id:
			continue
		result.append(colony_id)
	return result


func get_colony_ids_for_empire(empire_id: String) -> PackedStringArray:
	return _colony_ids_by_empire_id.get(empire_id, PackedStringArray()).duplicate()


func get_first_manageable_colony_id(system_id: String, empire_id: String) -> String:
	var colony_ids := get_colony_ids_for_system(system_id, empire_id)
	if colony_ids.is_empty():
		return ""
	return colony_ids[0]


func has_colony(colony_id: String) -> bool:
	return _colonies_by_id.has(colony_id)


func get_colony_details(colony_id: String, system_name: String = "") -> Dictionary:
	var colony = _colonies_by_id.get(colony_id, null)
	if colony == null:
		return {}

	var stats := _get_cached_colony_stats(colony)
	var economy := _get_cached_colony_economy(colony)
	var pop_entries: Array[Dictionary] = []
	for pop_variant in colony.pop_units:
		var pop_unit = pop_variant
		if pop_unit == null:
			continue

		var species = _species_by_id.get(pop_unit.species_id, null)
		var job_definition: Dictionary = _jobs_by_id.get(pop_unit.assigned_job_id, {})
		pop_entries.append({
			"id": pop_unit.pop_unit_id,
			"species_id": pop_unit.species_id,
			"species_name": species.species_name if species != null else pop_unit.species_id,
			"size": pop_unit.size,
			"assigned_job_id": pop_unit.assigned_job_id,
			"assigned_job_name": str(job_definition.get("display_name", "")),
			"is_idle": pop_unit.assigned_job_id.is_empty(),
		})

	var species_count_entries: Array[Dictionary] = []
	var species_counts: Dictionary = stats.get("species_counts", {})
	for species_id_variant in species_counts.keys():
		var species_id := str(species_id_variant)
		var species = _species_by_id.get(species_id, null)
		species_count_entries.append({
			"species_id": species_id,
			"species_name": species.species_name if species != null else species_id,
			"population": int(species_counts.get(species_id_variant, 0)),
			"trait_ids": _packed_string_array_to_array(species.trait_ids) if species != null else [],
		})
	species_count_entries.sort_custom(_sort_species_count_entries)

	var job_slots := _get_job_slots_for_colony(colony)
	var effective_job_slots := _get_effective_job_slots_for_colony(colony)
	var assigned_by_job: Dictionary = stats.get("assigned_by_job", {})
	var job_entries: Array[Dictionary] = []
	for job_id in _job_ids:
		var slot_count := int(job_slots.get(job_id, 0))
		if slot_count <= 0:
			continue
		var job_cap := _get_job_cap_for_colony(colony, job_id, slot_count)
		var fillable_slots := int(effective_job_slots.get(job_id, 0))
		var job_definition: Dictionary = _jobs_by_id.get(job_id, {})
		job_entries.append({
			"id": job_id,
			"display_name": str(job_definition.get("display_name", job_id)),
			"description": str(job_definition.get("description", "")),
			"priority": int(job_definition.get("priority", 0)),
			"used_slots": int(assigned_by_job.get(job_id, 0)),
			"job_cap": job_cap,
			"fillable_slots": fillable_slots,
			"max_slots": slot_count,
			"income": job_definition.get("income", []).duplicate(true),
			"expense": job_definition.get("expense", []).duplicate(true),
		})

	var building_entries := _build_colony_building_entries(colony)

	return {
		"id": colony.colony_id,
		"empire_id": colony.empire_id,
		"system_id": colony.system_id,
		"system_name": system_name,
		"planet_orbital_id": colony.planet_orbital_id,
		"planet_name": str(colony.planet_record.get("name", colony.planet_orbital_id)),
		"planet_record": colony.planet_record.duplicate(true),
		"planet_type": _get_planet_type(colony.planet_record),
		"habitability_points": int(stats.get("habitability_points", 0)),
		"name": colony.name,
		"is_capital": colony.is_capital,
		"total_population": int(stats.get("total_population", 0)),
		"assigned_pop_count": int(stats.get("assigned_pop_count", 0)),
		"idle_pop_count": int(stats.get("idle_pop_count", 0)),
		"pop_units": pop_entries,
		"species_counts": species_count_entries,
		"buildings": building_entries,
		"building_slots": colony.building_slots.duplicate(true),
		"building_grid_slots": _build_grid_slot_entries(colony),
		"building_catalog": _build_building_catalog(colony),
		"owner_stockpile": EconomyManager.get_stockpile_map(colony.empire_id) if not colony.empire_id.is_empty() else {},
		"last_build_error": str(_last_build_error_by_colony_id.get(colony.colony_id, "")),
		"jobs": job_entries,
		"monthly_income": economy.get("income_map", {}),
		"monthly_expense": economy.get("expense_map", {}),
		"monthly_net": economy.get("net_map", {}),
	}


func get_colony_summary(colony_id: String) -> Dictionary:
	var colony = _colonies_by_id.get(colony_id, null)
	if colony == null:
		return {}

	var stats := _get_cached_colony_stats(colony)
	var economy := _get_cached_colony_economy(colony)
	return {
		"id": colony.colony_id,
		"empire_id": colony.empire_id,
		"system_id": colony.system_id,
		"planet_orbital_id": colony.planet_orbital_id,
		"planet_name": str(colony.planet_record.get("name", colony.planet_orbital_id)),
		"planet_type": _get_planet_type(colony.planet_record),
		"habitability_points": int(stats.get("habitability_points", 0)),
		"name": colony.name,
		"is_capital": colony.is_capital,
		"total_population": int(stats.get("total_population", 0)),
		"assigned_pop_count": int(stats.get("assigned_pop_count", 0)),
		"idle_pop_count": int(stats.get("idle_pop_count", 0)),
		"monthly_income": economy.get("income_map", {}),
		"monthly_expense": economy.get("expense_map", {}),
		"monthly_net": economy.get("net_map", {}),
	}


func assign_pop_to_job(colony_id: String, pop_unit_id: String, job_id: String) -> bool:
	var colony = _colonies_by_id.get(colony_id, null)
	if colony == null or not _jobs_by_id.has(job_id):
		return false
	var pop_unit = colony.find_pop_unit(pop_unit_id)
	if pop_unit == null:
		return false
	if pop_unit.assigned_job_id == job_id:
		return true

	var job_slots := _get_effective_job_slots_for_colony(colony)
	var used_slots := _get_used_job_slots(colony, job_id)
	if used_slots >= int(job_slots.get(job_id, 0)):
		return false

	pop_unit.assigned_job_id = job_id
	_refresh_colony_runtime_cache(colony)
	sync_colony_source(colony.colony_id)
	colony_updated.emit(colony.colony_id)
	return true


func set_job_cap(colony_id: String, job_id: String, cap: int) -> bool:
	var colony = _colonies_by_id.get(colony_id, null)
	job_id = job_id.strip_edges()
	if colony == null or job_id.is_empty() or not _jobs_by_id.has(job_id):
		return false

	var job_slots := _get_job_slots_for_colony(colony)
	var max_slots := int(job_slots.get(job_id, 0))
	if max_slots <= 0:
		return false

	_ensure_job_caps_for_colony(colony)
	var clamped_cap := clampi(cap, 0, max_slots)
	var current_cap := int(colony.job_caps.get(job_id, max_slots))
	var changed := current_cap != clamped_cap
	colony.job_caps[job_id] = clamped_cap
	changed = _refresh_colony_runtime_cache(colony) or changed
	if not changed:
		return true

	sync_colony_source(colony.colony_id)
	colony_updated.emit(colony.colony_id)
	return true


func place_building(colony_id: String, slot_id: String, building_id: String) -> bool:
	var colony = _colonies_by_id.get(colony_id, null)
	slot_id = slot_id.strip_edges()
	building_id = building_id.strip_edges()
	if colony == null:
		return false
	if slot_id.is_empty() or not _is_valid_building_slot_id(slot_id):
		_set_build_error(colony, "Invalid building slot.")
		return false
	if building_id.is_empty() or not _buildings_by_id.has(building_id):
		_set_build_error(colony, "Unknown building.")
		return false
	_ensure_building_slots_for_colony(colony)
	if not str(colony.building_slots.get(slot_id, "")).is_empty():
		_set_build_error(colony, "That slot is already occupied.")
		return false

	var building_definition: Dictionary = _buildings_by_id.get(building_id, {})
	if not bool(building_definition.get("buildable", true)):
		_set_build_error(colony, "That building cannot be built manually.")
		return false

	var max_per_colony := int(building_definition.get("max_per_colony", 0))
	if max_per_colony > 0 and _count_buildings_on_colony(colony, building_id) >= max_per_colony:
		_set_build_error(colony, "Colony limit reached for %s." % str(building_definition.get("display_name", building_id)))
		return false

	var previous_job_slots := _get_job_slots_for_colony(colony)
	var build_cost: Array = building_definition.get("build_cost", [])
	if not build_cost.is_empty():
		if not EconomyManager.can_afford(colony.empire_id, build_cost):
			_set_build_error(colony, "Not enough resources.")
			return false
		if not EconomyManager.commit_cost(colony.empire_id, build_cost):
			_set_build_error(colony, "Could not spend resources.")
			return false

	colony.building_slots[slot_id] = building_id
	_sync_flat_buildings_from_slots(colony)
	_expand_default_job_caps_after_building(colony, building_definition, previous_job_slots)
	_last_build_error_by_colony_id[colony.colony_id] = ""
	_refresh_colony_runtime_cache(colony)
	sync_colony_source(colony.colony_id)
	colony_updated.emit(colony.colony_id)
	return true


func unassign_pop_from_job(colony_id: String, pop_unit_id: String) -> bool:
	var colony = _colonies_by_id.get(colony_id, null)
	if colony == null:
		return false
	var pop_unit = colony.find_pop_unit(pop_unit_id)
	if pop_unit == null:
		return false
	if pop_unit.assigned_job_id.is_empty():
		return true
	pop_unit.assigned_job_id = ""
	_refresh_colony_runtime_cache(colony)
	sync_colony_source(colony.colony_id)
	colony_updated.emit(colony.colony_id)
	return true


func transfer_colonies_in_system(system_id: String, new_owner_empire_id: String) -> void:
	var colony_ids: PackedStringArray = _colony_ids_by_system_id.get(system_id, PackedStringArray()).duplicate()
	for colony_id in colony_ids:
		var colony = _colonies_by_id.get(colony_id, null)
		if colony == null:
			continue
		var previous_owner_id: String = colony.empire_id
		if previous_owner_id == new_owner_empire_id:
			continue
		_remove_colony_from_empire_index(colony.colony_id, previous_owner_id)
		colony.empire_id = new_owner_empire_id.strip_edges()
		if not colony.empire_id.is_empty():
			_add_colony_to_empire_index(colony.colony_id, colony.empire_id)
		_refresh_colony_runtime_cache(colony)
		sync_colony_source(colony.colony_id)
		colony_updated.emit(colony.colony_id)


func sync_colony_source(colony_id: String) -> bool:
	var colony = _colonies_by_id.get(colony_id, null)
	if colony == null:
		return false
	var source_id := _build_colony_source_id(colony.colony_id)
	if not EconomyManager.is_bootstrapped():
		return false
	if colony.empire_id.is_empty():
		if EconomyManager.has_source(source_id):
			EconomyManager.remove_source(source_id)
		return true

	var economy := _get_cached_colony_economy(colony)
	var source_tags := PackedStringArray([colony.system_id, colony.colony_id, colony.planet_orbital_id])
	if EconomyManager.has_source(source_id):
		EconomyManager.transfer_source(source_id, colony.empire_id)
		return EconomyManager.update_source(
			source_id,
			economy.get("income", []),
			economy.get("expense", []),
			[]
		)

	return EconomyManager.register_source(
		source_id,
		colony.empire_id,
		economy.get("income", []),
		economy.get("expense", []),
		[],
		"colony",
		source_tags
	)


func calculate_colony_habitability_points(colony_id: String) -> int:
	var colony = _colonies_by_id.get(colony_id, null)
	if colony == null:
		return 0
	return int(_get_cached_colony_stats(colony).get("habitability_points", 0))


func _calculate_colony_habitability_points_uncached(colony, species_counts: Dictionary, representative_pops_by_species_id: Dictionary) -> int:
	var base_points := clampi(int(colony.planet_record.get("habitability_points", 0)), 0, 100)
	var total_population := 0
	for species_id_variant in species_counts.keys():
		total_population += int(species_counts[species_id_variant])
	if total_population <= 0:
		return base_points

	var weighted_points := 0
	for species_id_variant in species_counts.keys():
		var species_id := str(species_id_variant)
		var pop_unit = representative_pops_by_species_id.get(species_id, null)
		if pop_unit == null:
			continue
		var context := _build_modifier_context(colony, pop_unit, "")
		weighted_points += _apply_point_trait_modifiers(base_points, "habitability", context) * int(species_counts[species_id_variant])
	return clampi(int(round(float(weighted_points) / float(total_population))), 0, 100)


func build_snapshot() -> Dictionary:
	var species_snapshots: Array[Dictionary] = []
	for species_id_variant in _species_by_id.keys():
		var species = _species_by_id[species_id_variant]
		if species != null:
			species_snapshots.append(species.to_dict())
	species_snapshots.sort_custom(_sort_snapshots_by_id)

	var colony_snapshots: Array[Dictionary] = []
	for colony_id_variant in _colonies_by_id.keys():
		var colony = _colonies_by_id[colony_id_variant]
		if colony != null:
			colony_snapshots.append(colony.to_dict())
	colony_snapshots.sort_custom(_sort_snapshots_by_id)

	return {
		"bootstrapped": _bootstrapped,
		"pop_unit_size": POP_UNIT_SIZE,
		"species": species_snapshots,
		"species_ids_by_empire_id": _packed_string_array_map_to_arrays(_species_ids_by_empire_id),
		"colonies": colony_snapshots,
	}


func load_snapshot(snapshot: Dictionary) -> void:
	if _jobs_by_id.is_empty() or _buildings_by_id.is_empty() or _traits_by_id.is_empty():
		load_definitions()
	reset_runtime_state(false)
	_bootstrapped = bool(snapshot.get("bootstrapped", true))

	for species_index in range(snapshot.get("species", []).size()):
		var species_variant: Variant = snapshot.get("species", [])[species_index]
		if species_variant is not Dictionary:
			continue
		var species = SPECIES_RUNTIME_SCRIPT.from_dict(species_variant, species_index)
		_species_by_id[species.species_id] = species

	var species_map_variant: Variant = snapshot.get("species_ids_by_empire_id", {})
	if species_map_variant is Dictionary:
		for empire_id_variant in species_map_variant.keys():
			_species_ids_by_empire_id[str(empire_id_variant)] = _variant_to_packed_string_array(species_map_variant[empire_id_variant])

	for colony_index in range(snapshot.get("colonies", []).size()):
		var colony_variant: Variant = snapshot.get("colonies", [])[colony_index]
		if colony_variant is not Dictionary:
			continue
		var colony = COLONY_RUNTIME_SCRIPT.from_dict(colony_variant, colony_index)
		_refresh_colony_runtime_cache(colony)
		_register_colony(colony)
		sync_colony_source(colony.colony_id)


func _register_colony(colony) -> void:
	_colonies_by_id[colony.colony_id] = colony
	var system_colony_ids: PackedStringArray = _colony_ids_by_system_id.get(colony.system_id, PackedStringArray())
	if not system_colony_ids.has(colony.colony_id):
		system_colony_ids.append(colony.colony_id)
	_colony_ids_by_system_id[colony.system_id] = system_colony_ids
	_add_colony_to_empire_index(colony.colony_id, colony.empire_id)


func _add_colony_to_empire_index(colony_id: String, empire_id: String) -> void:
	if empire_id.is_empty():
		return
	var empire_colony_ids: PackedStringArray = _colony_ids_by_empire_id.get(empire_id, PackedStringArray())
	if not empire_colony_ids.has(colony_id):
		empire_colony_ids.append(colony_id)
	_colony_ids_by_empire_id[empire_id] = empire_colony_ids


func _remove_colony_from_empire_index(colony_id: String, empire_id: String) -> void:
	if empire_id.is_empty():
		return
	var empire_colony_ids: PackedStringArray = _colony_ids_by_empire_id.get(empire_id, PackedStringArray())
	if not empire_colony_ids.has(colony_id):
		return
	empire_colony_ids.remove_at(empire_colony_ids.find(colony_id))
	if empire_colony_ids.is_empty():
		_colony_ids_by_empire_id.erase(empire_id)
	else:
		_colony_ids_by_empire_id[empire_id] = empire_colony_ids


func _register_primary_species(empire_record: Dictionary, empire_index: int) -> String:
	var empire_id := str(empire_record.get("id", "")).strip_edges()
	if empire_id.is_empty():
		return ""

	var species_data := _resolve_species_data_for_empire(empire_record, empire_index)
	return register_known_species(empire_id, species_data)


func _resolve_species_data_for_empire(empire_record: Dictionary, empire_index: int) -> Dictionary:
	var empire_id := str(empire_record.get("id", "")).strip_edges()
	var archetype_id := str(empire_record.get("species_archetype_id", "")).strip_edges()
	var species_type_id := str(empire_record.get("species_type_id", "")).strip_edges()
	var catalog_entry := _find_species_catalog_entry(archetype_id, species_type_id, empire_index)
	if archetype_id.is_empty():
		archetype_id = str(catalog_entry.get("archetype_id", "organic"))
	if species_type_id.is_empty():
		species_type_id = str(catalog_entry.get("species_type_id", "humanoid"))

	var trait_ids := _variant_to_packed_string_array(empire_record.get("trait_ids", []))
	if trait_ids.is_empty():
		trait_ids = _variant_to_packed_string_array(catalog_entry.get("trait_ids", []))

	return {
		"id": str(empire_record.get("primary_species_id", "")),
		"empire_id": empire_id,
		"archetype_id": archetype_id,
		"species_type_id": species_type_id,
		"species_visuals_id": str(empire_record.get("species_visuals_id", catalog_entry.get("species_visuals_id", ""))),
		"display_name": str(catalog_entry.get("display_name", empire_record.get("species_name", ""))),
		"species_name": str(empire_record.get("species_name", catalog_entry.get("species_name", ""))),
		"species_plural_name": str(empire_record.get("species_plural_name", catalog_entry.get("species_plural_name", ""))),
		"species_adjective": str(empire_record.get("species_adjective", catalog_entry.get("species_adjective", ""))),
		"trait_ids": _packed_string_array_to_array(trait_ids),
	}


func _find_species_catalog_entry(archetype_id: String, species_type_id: String, fallback_index: int) -> Dictionary:
	var catalog: Dictionary = SPECIES_LIBRARY_SCRIPT.load_catalog()
	if not archetype_id.is_empty() and not species_type_id.is_empty():
		var exact_entry: Dictionary = SPECIES_LIBRARY_SCRIPT.get_species_entry(catalog, archetype_id, species_type_id)
		if not exact_entry.is_empty():
			return exact_entry

	var flattened_entries: Array[Dictionary] = []
	for archetype_entry in SPECIES_LIBRARY_SCRIPT.get_archetype_entries(catalog):
		for species_entry in SPECIES_LIBRARY_SCRIPT.get_species_entries(catalog, str(archetype_entry.get("id", ""))):
			flattened_entries.append(species_entry)
	if flattened_entries.is_empty():
		return _build_fallback_species_data("", fallback_index)
	return flattened_entries[abs(fallback_index) % flattened_entries.size()]


func _build_fallback_species_data(empire_id: String, fallback_index: int) -> Dictionary:
	var archetype_id := "organic"
	var species_type_id := "humanoid"
	if fallback_index % 5 == 0:
		archetype_id = "machine"
		species_type_id = "machine"
	return {
		"empire_id": empire_id,
		"archetype_id": archetype_id,
		"species_type_id": species_type_id,
		"species_visuals_id": "%s/%s" % [archetype_id, species_type_id],
		"display_name": species_type_id.capitalize(),
		"species_name": species_type_id.capitalize(),
		"species_plural_name": "%ss" % species_type_id.capitalize(),
		"species_adjective": species_type_id.capitalize(),
		"trait_ids": ["technical", "adaptive"] if archetype_id == "organic" else ["industrious", "efficient"],
	}


func _refresh_colony_runtime_cache(colony) -> bool:
	if colony == null:
		return false
	_ensure_building_slots_for_colony(colony)
	_ensure_job_caps_for_colony(colony)
	var assignment_changed := _rebalance_colony_jobs(colony)
	_refresh_colony_stats_cache(colony)
	_refresh_colony_economy_cache(colony)
	return assignment_changed


func _get_cached_colony_stats(colony) -> Dictionary:
	if colony == null:
		return {}
	if not _colony_stats_cache.has(colony.colony_id):
		_refresh_colony_stats_cache(colony)
	return (_colony_stats_cache.get(colony.colony_id, {}) as Dictionary).duplicate(true)


func _get_cached_colony_economy(colony) -> Dictionary:
	if colony == null:
		return {}
	if not _colony_economy_cache.has(colony.colony_id):
		_refresh_colony_economy_cache(colony)
	return (_colony_economy_cache.get(colony.colony_id, {}) as Dictionary).duplicate(true)


func _refresh_colony_stats_cache(colony) -> void:
	var species_counts: Dictionary = {}
	var representative_pops_by_species_id: Dictionary = {}
	var assigned_by_job: Dictionary = {}
	var total_population := 0
	var assigned_pop_count := 0
	var valid_pop_count := 0

	for pop_variant in colony.pop_units:
		var pop_unit = pop_variant
		if pop_unit == null:
			continue
		valid_pop_count += 1
		total_population += pop_unit.size
		species_counts[pop_unit.species_id] = int(species_counts.get(pop_unit.species_id, 0)) + pop_unit.size
		if not representative_pops_by_species_id.has(pop_unit.species_id):
			representative_pops_by_species_id[pop_unit.species_id] = pop_unit
		if not pop_unit.assigned_job_id.is_empty():
			assigned_pop_count += 1
			assigned_by_job[pop_unit.assigned_job_id] = int(assigned_by_job.get(pop_unit.assigned_job_id, 0)) + 1

	_colony_stats_cache[colony.colony_id] = {
		"total_population": total_population,
		"assigned_pop_count": assigned_pop_count,
		"idle_pop_count": maxi(valid_pop_count - assigned_pop_count, 0),
		"species_counts": species_counts,
		"assigned_by_job": assigned_by_job,
		"habitability_points": _calculate_colony_habitability_points_uncached(colony, species_counts, representative_pops_by_species_id),
	}


func _refresh_colony_economy_cache(colony) -> void:
	_colony_economy_cache[colony.colony_id] = _compile_colony_economy(colony)


func _set_build_error(colony, message: String) -> void:
	if colony == null:
		return
	_last_build_error_by_colony_id[colony.colony_id] = message.strip_edges()


func _build_starter_building_slots() -> Dictionary:
	var result: Dictionary = {}
	for building_id in CAPITAL_BUILDING_IDS:
		var slot_id := str(STARTER_BUILDING_SLOT_IDS.get(building_id, "")).strip_edges()
		if slot_id.is_empty() or not _is_valid_building_slot_id(slot_id):
			continue
		result[slot_id] = building_id
	return result


func _ensure_building_slots_for_colony(colony) -> void:
	if colony == null:
		return

	var normalized_slots: Dictionary = {}
	var source_slots: Dictionary = colony.building_slots if colony.building_slots is Dictionary else {}
	for slot_id_variant in source_slots.keys():
		var slot_id := str(slot_id_variant).strip_edges()
		var building_id := str(source_slots[slot_id_variant]).strip_edges()
		if slot_id.is_empty() or building_id.is_empty():
			continue
		if not _is_valid_building_slot_id(slot_id) or not _buildings_by_id.has(building_id):
			continue
		normalized_slots[slot_id] = building_id

	if normalized_slots.is_empty() and not colony.buildings.is_empty():
		normalized_slots = _migrate_flat_buildings_to_slots(colony.buildings)
	if normalized_slots.is_empty() and bool(colony.is_capital):
		normalized_slots = _build_starter_building_slots()

	colony.building_slots = normalized_slots
	_sync_flat_buildings_from_slots(colony)


func _migrate_flat_buildings_to_slots(flat_buildings: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	var grid_slot_ids := _build_grid_slot_ids()
	for building_id in flat_buildings:
		if building_id.is_empty() or not _buildings_by_id.has(building_id):
			continue

		var preferred_slot_id := str(STARTER_BUILDING_SLOT_IDS.get(building_id, "")).strip_edges()
		if not preferred_slot_id.is_empty() and _is_valid_building_slot_id(preferred_slot_id) and not result.has(preferred_slot_id):
			result[preferred_slot_id] = building_id
			continue

		for slot_id in grid_slot_ids:
			if result.has(slot_id):
				continue
			result[slot_id] = building_id
			break
	return result


func _sync_flat_buildings_from_slots(colony) -> void:
	if colony == null:
		return
	var buildings := PackedStringArray()
	var grid_slot_ids := _build_grid_slot_ids()
	for slot_id in grid_slot_ids:
		var building_id := str(colony.building_slots.get(slot_id, "")).strip_edges()
		if building_id.is_empty() or not _buildings_by_id.has(building_id):
			continue
		buildings.append(building_id)
	colony.buildings = buildings


func _build_colony_building_entries(colony) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if colony == null:
		return result
	_ensure_building_slots_for_colony(colony)
	for slot_id in _build_grid_slot_ids():
		var building_id := str(colony.building_slots.get(slot_id, "")).strip_edges()
		if building_id.is_empty():
			continue
		var building_definition: Dictionary = _buildings_by_id.get(building_id, {})
		if building_definition.is_empty():
			continue
		result.append(_build_building_entry(building_id, building_definition, slot_id))
	return result


func _build_grid_slot_entries(colony) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if colony == null:
		return result
	_ensure_building_slots_for_colony(colony)
	for slot_id in _build_grid_slot_ids():
		var coordinates := _parse_building_slot_id(slot_id)
		var building_id := str(colony.building_slots.get(slot_id, "")).strip_edges()
		var building_definition: Dictionary = _buildings_by_id.get(building_id, {}) if not building_id.is_empty() else {}
		result.append({
			"id": slot_id,
			"q": coordinates.x,
			"r": coordinates.y,
			"building_id": building_id,
			"building_name": str(building_definition.get("display_name", "")),
			"building": _build_building_entry(building_id, building_definition, slot_id) if not building_definition.is_empty() else {},
		})
	return result


func _build_building_catalog(colony) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if colony == null:
		return result
	_ensure_building_slots_for_colony(colony)
	var has_empty_slot := _has_empty_building_slot(colony)
	for building_id in _building_ids:
		var building_definition: Dictionary = _buildings_by_id.get(building_id, {})
		if building_definition.is_empty() or not bool(building_definition.get("buildable", true)):
			continue

		var build_cost: Array = building_definition.get("build_cost", [])
		var max_per_colony := int(building_definition.get("max_per_colony", 0))
		var current_count := _count_buildings_on_colony(colony, building_id)
		var under_limit := max_per_colony <= 0 or current_count < max_per_colony
		var can_afford := build_cost.is_empty() or EconomyManager.can_afford(colony.empire_id, build_cost)
		var can_place := has_empty_slot and under_limit and can_afford
		var unavailable_reason := ""
		if not has_empty_slot:
			unavailable_reason = "No empty building slots."
		elif not under_limit:
			unavailable_reason = "Colony limit reached."
		elif not can_afford:
			unavailable_reason = "Not enough resources."

		var entry := _build_building_entry(building_id, building_definition, "")
		entry["current_count"] = current_count
		entry["can_place"] = can_place
		entry["unavailable_reason"] = unavailable_reason
		result.append(entry)
	return result


func _build_building_entry(building_id: String, building_definition: Dictionary, slot_id: String) -> Dictionary:
	if building_id.is_empty() or building_definition.is_empty():
		return {}
	return {
		"id": building_id,
		"slot_id": slot_id,
		"display_name": str(building_definition.get("display_name", building_id)),
		"description": str(building_definition.get("description", "")),
		"sort_key": int(building_definition.get("sort_key", 0)),
		"job_slots": (building_definition.get("job_slots", {}) as Dictionary).duplicate(true),
		"build_cost": (building_definition.get("build_cost", []) as Array).duplicate(true),
		"buildable": bool(building_definition.get("buildable", true)),
		"max_per_colony": int(building_definition.get("max_per_colony", 0)),
	}


func _expand_default_job_caps_after_building(colony, building_definition: Dictionary, previous_job_slots: Dictionary) -> void:
	if colony == null or building_definition.is_empty():
		return
	var building_job_slots: Dictionary = building_definition.get("job_slots", {})
	if building_job_slots.is_empty():
		return
	var updated_job_slots := _get_job_slots_for_colony(colony)
	for job_id_variant in building_job_slots.keys():
		var job_id := str(job_id_variant).strip_edges()
		if job_id.is_empty():
			continue
		var previous_max := int(previous_job_slots.get(job_id, 0))
		var current_cap := int(colony.job_caps.get(job_id, previous_max))
		if current_cap >= previous_max:
			colony.job_caps[job_id] = int(updated_job_slots.get(job_id, previous_max))


func _has_empty_building_slot(colony) -> bool:
	if colony == null:
		return false
	_ensure_building_slots_for_colony(colony)
	for slot_id in _build_grid_slot_ids():
		if str(colony.building_slots.get(slot_id, "")).strip_edges().is_empty():
			return true
	return false


func _count_buildings_on_colony(colony, building_id: String) -> int:
	if colony == null or building_id.is_empty():
		return 0
	_ensure_building_slots_for_colony(colony)
	var count := 0
	for slot_id in _build_grid_slot_ids():
		if str(colony.building_slots.get(slot_id, "")).strip_edges() == building_id:
			count += 1
	return count


func _is_valid_building_slot_id(slot_id: String) -> bool:
	var parts := _parse_building_slot_parts(slot_id)
	if parts.size() != 2:
		return false
	var q := int(parts[0])
	var r := int(parts[1])
	var s := -q - r
	return maxi(abs(q), maxi(abs(r), abs(s))) <= BUILDING_GRID_RADIUS


func _build_grid_slot_ids() -> PackedStringArray:
	if not _building_grid_slot_ids_cache.is_empty():
		return _building_grid_slot_ids_cache.duplicate()

	for r in range(-BUILDING_GRID_RADIUS, BUILDING_GRID_RADIUS + 1):
		for q in range(-BUILDING_GRID_RADIUS, BUILDING_GRID_RADIUS + 1):
			var s := -q - r
			if maxi(abs(q), maxi(abs(r), abs(s))) > BUILDING_GRID_RADIUS:
				continue
			_building_grid_slot_ids_cache.append(_build_slot_id(q, r))
	return _building_grid_slot_ids_cache.duplicate()


func _build_slot_id(q: int, r: int) -> String:
	return "q%d_r%d" % [q, r]


func _parse_building_slot_id(slot_id: String) -> Vector2i:
	var parts := _parse_building_slot_parts(slot_id)
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func _parse_building_slot_parts(slot_id: String) -> Array:
	slot_id = slot_id.strip_edges()
	var parts := slot_id.split("_r")
	if parts.size() != 2:
		return []
	var q_text := str(parts[0])
	var r_text := str(parts[1])
	if not q_text.begins_with("q"):
		return []
	q_text = q_text.substr(1)
	if not _is_integer_text(q_text) or not _is_integer_text(r_text):
		return []
	return [int(q_text), int(r_text)]


func _is_integer_text(value: String) -> bool:
	if value.is_empty():
		return false
	var start_index := 0
	if value.begins_with("-"):
		start_index = 1
	if start_index >= value.length():
		return false
	for index in range(start_index, value.length()):
		var character := value.substr(index, 1)
		if character < "0" or character > "9":
			return false
	return true


func _compile_colony_economy(colony) -> Dictionary:
	var income_map: Dictionary = {}
	var expense_map: Dictionary = {}
	var grouped_units: Dictionary = {}
	var representative_pops_by_group: Dictionary = {}
	for pop_variant in colony.pop_units:
		var pop_unit = pop_variant
		if pop_unit == null or pop_unit.assigned_job_id.is_empty():
			continue
		var group_key := "%s\n%s" % [pop_unit.species_id, pop_unit.assigned_job_id]
		grouped_units[group_key] = int(grouped_units.get(group_key, 0)) + 1
		if not representative_pops_by_group.has(group_key):
			representative_pops_by_group[group_key] = pop_unit

	for group_key_variant in grouped_units.keys():
		var group_key := str(group_key_variant)
		var pop_unit = representative_pops_by_group.get(group_key, null)
		if pop_unit == null:
			continue
		var job_definition: Dictionary = _jobs_by_id.get(pop_unit.assigned_job_id, {})
		if job_definition.is_empty():
			continue
		var context := _build_modifier_context(colony, pop_unit, pop_unit.assigned_job_id)
		var unit_count := int(grouped_units.get(group_key, 0))
		_add_modified_amounts_to_map(income_map, job_definition.get("income", []), "job_output", context, unit_count)
		_add_modified_amounts_to_map(expense_map, job_definition.get("expense", []), "job_upkeep", context, unit_count)

	var net_map: Dictionary = {}
	for resource_id_variant in income_map.keys():
		net_map[str(resource_id_variant)] = int(net_map.get(str(resource_id_variant), 0)) + int(income_map[resource_id_variant])
	for resource_id_variant in expense_map.keys():
		net_map[str(resource_id_variant)] = int(net_map.get(str(resource_id_variant), 0)) - int(expense_map[resource_id_variant])

	return {
		"income": _resource_map_to_amount_array(income_map),
		"expense": _resource_map_to_amount_array(expense_map),
		"income_map": income_map,
		"expense_map": expense_map,
		"net_map": net_map,
	}


func _add_modified_amounts_to_map(target: Dictionary, amounts_variant: Variant, scope: String, context: Dictionary, multiplier: int = 1) -> void:
	if multiplier <= 0:
		return
	var amounts: Array = amounts_variant if amounts_variant is Array else []
	for amount_variant in amounts:
		if amount_variant is not Dictionary:
			continue
		var amount: Dictionary = amount_variant
		var resource_id := str(amount.get("resource_id", "")).strip_edges()
		if resource_id.is_empty():
			continue
		var modified_amount := _apply_trait_modifiers_to_amount(int(amount.get("milliunits", 0)), scope, resource_id, context)
		if modified_amount == 0:
			continue
		target[resource_id] = int(target.get(resource_id, 0)) + modified_amount * multiplier


func _apply_trait_modifiers_to_amount(base_amount: int, scope: String, resource_id: String, context: Dictionary) -> int:
	var modified_amount := base_amount
	var species = context.get("species", null)
	if species == null:
		return maxi(modified_amount, 0)

	for trait_id in species.trait_ids:
		var trait_definition: Dictionary = _traits_by_id.get(trait_id, {})
		var rules: Array = trait_definition.get("rules", [])
		for rule_variant in rules:
			if rule_variant is not Dictionary:
				continue
			var rule: Dictionary = rule_variant
			if not _rule_matches(rule, scope, resource_id, context):
				continue
			match str(rule.get("operation", "percent")):
				"percent":
					modified_amount += int(round(float(modified_amount) * float(rule.get("value_bp", 0)) / 10000.0))
				"add_milliunits", "add":
					modified_amount += int(rule.get("value", rule.get("milliunits", 0)))
	return maxi(modified_amount, 0)


func _apply_point_trait_modifiers(base_points: int, scope: String, context: Dictionary) -> int:
	var modified_points := base_points
	var species = context.get("species", null)
	if species == null:
		return clampi(modified_points, 0, 100)

	for trait_id in species.trait_ids:
		var trait_definition: Dictionary = _traits_by_id.get(trait_id, {})
		var rules: Array = trait_definition.get("rules", [])
		for rule_variant in rules:
			if rule_variant is not Dictionary:
				continue
			var rule: Dictionary = rule_variant
			if not _rule_matches(rule, scope, "", context):
				continue
			match str(rule.get("operation", "percent")):
				"percent":
					modified_points += int(round(float(modified_points) * float(rule.get("value_bp", 0)) / 10000.0))
				"add_points", "add":
					modified_points += int(rule.get("value", 0))
	return clampi(modified_points, 0, 100)


func _rule_matches(rule: Dictionary, scope: String, resource_id: String, context: Dictionary) -> bool:
	if str(rule.get("scope", "")) != scope:
		return false
	if not _matches_optional_filter(str(rule.get("resource_id", "")), resource_id):
		return false
	if not _matches_optional_filter(str(rule.get("job_id", "")), str(context.get("job_id", ""))):
		return false
	if not _matches_optional_filter(str(rule.get("species_archetype_id", "")), str(context.get("species_archetype_id", ""))):
		return false
	if not _matches_optional_filter(str(rule.get("planet_type", "")), str(context.get("planet_type", ""))):
		return false
	return true


func _matches_optional_filter(filter_value: String, actual_value: String) -> bool:
	filter_value = filter_value.strip_edges()
	if filter_value.is_empty() or filter_value == "*":
		return true
	return filter_value == actual_value


func _build_modifier_context(colony, pop_unit, job_id: String) -> Dictionary:
	var species = _species_by_id.get(pop_unit.species_id, null)
	return {
		"colony": colony,
		"pop_unit": pop_unit,
		"species": species,
		"species_id": pop_unit.species_id,
		"species_archetype_id": species.archetype_id if species != null else "",
		"job_id": job_id,
		"planet_type": _get_planet_type(colony.planet_record),
	}


func _get_job_slots_for_colony(colony) -> Dictionary:
	var slots: Dictionary = {}
	if colony == null:
		return slots
	_ensure_building_slots_for_colony(colony)
	for building_id_variant in colony.building_slots.values():
		var building_id := str(building_id_variant).strip_edges()
		if building_id.is_empty():
			continue
		var building_definition: Dictionary = _buildings_by_id.get(building_id, {})
		var job_slots: Dictionary = building_definition.get("job_slots", {})
		for job_id_variant in job_slots.keys():
			var job_id := str(job_id_variant).strip_edges()
			if job_id.is_empty():
				continue
			slots[job_id] = int(slots.get(job_id, 0)) + int(job_slots[job_id_variant])
	return slots


func _get_effective_job_slots_for_colony(colony) -> Dictionary:
	var slots := _get_job_slots_for_colony(colony)
	_ensure_job_caps_for_colony(colony, slots)
	var result: Dictionary = {}
	for job_id_variant in slots.keys():
		var job_id := str(job_id_variant)
		var max_slots := int(slots[job_id_variant])
		result[job_id] = mini(max_slots, int(colony.job_caps.get(job_id, max_slots)))
	return result


func _ensure_job_caps_for_colony(colony, job_slots: Dictionary = {}) -> void:
	if colony == null:
		return
	if job_slots.is_empty():
		job_slots = _get_job_slots_for_colony(colony)

	var normalized_caps: Dictionary = {}
	var source_caps: Dictionary = colony.job_caps if colony.job_caps is Dictionary else {}
	for job_id_variant in job_slots.keys():
		var job_id := str(job_id_variant).strip_edges()
		if job_id.is_empty():
			continue
		var max_slots := int(job_slots[job_id_variant])
		normalized_caps[job_id] = clampi(int(source_caps.get(job_id, max_slots)), 0, max_slots)
	colony.job_caps = normalized_caps


func _get_job_cap_for_colony(colony, job_id: String, max_slots: int) -> int:
	_ensure_job_caps_for_colony(colony)
	return clampi(int(colony.job_caps.get(job_id, max_slots)), 0, max_slots)


func _rebalance_colony_jobs(colony) -> bool:
	if colony == null:
		return false

	var effective_slots := _get_effective_job_slots_for_colony(colony)
	var valid_pops: Array = []
	for pop_variant in colony.pop_units:
		var pop_unit = pop_variant
		if pop_unit == null:
			continue
		valid_pops.append(pop_unit)

	var pop_index := 0
	var changed := false
	for job_id in _job_ids:
		var fillable_slots := int(effective_slots.get(job_id, 0))
		for _slot_index in range(fillable_slots):
			if pop_index >= valid_pops.size():
				break
			var pop_unit = valid_pops[pop_index]
			if pop_unit.assigned_job_id != job_id:
				changed = true
				pop_unit.assigned_job_id = job_id
			pop_index += 1
		if pop_index >= valid_pops.size():
			break

	while pop_index < valid_pops.size():
		var idle_pop = valid_pops[pop_index]
		if not idle_pop.assigned_job_id.is_empty():
			changed = true
			idle_pop.assigned_job_id = ""
		pop_index += 1
	return changed


func _get_used_job_slots(colony, job_id: String) -> int:
	var used_slots := 0
	for pop_variant in colony.pop_units:
		var pop_unit = pop_variant
		if pop_unit != null and pop_unit.assigned_job_id == job_id:
			used_slots += 1
	return used_slots


func _get_planet_type(planet_record: Dictionary) -> String:
	var metadata: Dictionary = planet_record.get("metadata", {})
	var planet_visual: Dictionary = metadata.get("planet_visual", {})
	var planet_type := str(planet_record.get("planet_class_id", "")).strip_edges()
	if planet_type.is_empty():
		planet_type = str(metadata.get("planet_class_id", "")).strip_edges()
	if planet_type.is_empty():
		planet_type = str(planet_visual.get("kind", "")).strip_edges()
	if planet_type.is_empty():
		planet_type = str(planet_record.get("type", "planet"))
	return planet_type


func _load_job_definitions() -> void:
	_job_ids.clear()
	_jobs_by_id.clear()
	var config := ConfigFile.new()
	if config.load(JOB_DEFINITION_PATH) != OK:
		_install_fallback_job_definitions()
		return
	for section in config.get_sections():
		var job_id := str(section).strip_edges()
		if job_id.is_empty():
			continue
		_jobs_by_id[job_id] = {
			"id": job_id,
			"display_name": str(config.get_value(section, "display_name", job_id.capitalize())),
			"description": str(config.get_value(section, "description", "")),
			"priority": int(config.get_value(section, "priority", 0)),
			"income": _normalize_amounts_to_dict_array(config.get_value(section, "income", {})),
			"expense": _normalize_amounts_to_dict_array(config.get_value(section, "expense", {})),
		}
		_job_ids.append(job_id)
	_job_ids.sort_custom(_sort_job_ids)


func _load_building_definitions() -> void:
	_building_ids.clear()
	_buildings_by_id.clear()
	var config := ConfigFile.new()
	if config.load(BUILDING_DEFINITION_PATH) != OK:
		_install_fallback_building_definitions()
		return
	for section in config.get_sections():
		var building_id := str(section).strip_edges()
		if building_id.is_empty():
			continue
		_buildings_by_id[building_id] = {
			"id": building_id,
			"display_name": str(config.get_value(section, "display_name", building_id.capitalize())),
			"description": str(config.get_value(section, "description", "")),
			"sort_key": int(config.get_value(section, "sort_key", 0)),
			"job_slots": _normalize_int_dictionary(config.get_value(section, "job_slots", {})),
			"build_cost": _normalize_amounts_to_dict_array(config.get_value(section, "build_cost", {})),
			"buildable": bool(config.get_value(section, "buildable", true)),
			"max_per_colony": int(config.get_value(section, "max_per_colony", 0)),
		}
		_building_ids.append(building_id)
	_building_ids.sort_custom(_sort_building_ids)


func _load_trait_definitions() -> void:
	_traits_by_id.clear()
	var config := ConfigFile.new()
	if config.load(TRAIT_DEFINITION_PATH) != OK:
		_install_fallback_trait_definitions()
		return
	for section in config.get_sections():
		var trait_id := str(section).strip_edges()
		if trait_id.is_empty():
			continue
		var rules := _normalize_trait_rules(config.get_value(section, "rules", []), config, section)
		_traits_by_id[trait_id] = {
			"id": trait_id,
			"display_name": str(config.get_value(section, "display_name", trait_id.capitalize())),
			"description": str(config.get_value(section, "description", "")),
			"rules": rules,
		}


func _normalize_trait_rules(rules_variant: Variant, config: ConfigFile, section: String) -> Array[Dictionary]:
	var rules: Array[Dictionary] = []
	if rules_variant is Array:
		for rule_variant in rules_variant:
			if rule_variant is Dictionary:
				rules.append((rule_variant as Dictionary).duplicate(true))
	elif rules_variant is Dictionary:
		rules.append((rules_variant as Dictionary).duplicate(true))

	if rules.is_empty() and config.has_section_key(section, "scope"):
		rules.append({
			"scope": str(config.get_value(section, "scope", "")),
			"resource_id": str(config.get_value(section, "resource_id", "")),
			"job_id": str(config.get_value(section, "job_id", "")),
			"planet_type": str(config.get_value(section, "planet_type", "")),
			"species_archetype_id": str(config.get_value(section, "species_archetype_id", "")),
			"operation": str(config.get_value(section, "operation", "percent")),
			"value_bp": int(config.get_value(section, "value_bp", 0)),
			"value": int(config.get_value(section, "value", 0)),
		})

	for rule in rules:
		rule["scope"] = str(rule.get("scope", "")).strip_edges()
		rule["resource_id"] = str(rule.get("resource_id", "")).strip_edges()
		rule["job_id"] = str(rule.get("job_id", "")).strip_edges()
		rule["planet_type"] = str(rule.get("planet_type", "")).strip_edges()
		rule["species_archetype_id"] = str(rule.get("species_archetype_id", "")).strip_edges()
		rule["operation"] = str(rule.get("operation", "percent")).strip_edges()
		rule["value_bp"] = int(rule.get("value_bp", 0))
		rule["value"] = int(rule.get("value", rule.get("milliunits", 0)))
	return rules


func _install_fallback_job_definitions() -> void:
	_jobs_by_id = {
		"administrator": {"id": "administrator", "display_name": "Administrator", "description": "", "priority": 100, "income": _normalize_amounts_to_dict_array({"energy": 1.0, "matter": 1.0}), "expense": _normalize_amounts_to_dict_array({"food": 0.5})},
		"farmer": {"id": "farmer", "display_name": "Farmer", "description": "", "priority": 70, "income": _normalize_amounts_to_dict_array({"food": 6.0}), "expense": _normalize_amounts_to_dict_array({"energy": 0.5})},
		"technician": {"id": "technician", "display_name": "Technician", "description": "", "priority": 80, "income": _normalize_amounts_to_dict_array({"energy": 6.0}), "expense": []},
		"miner": {"id": "miner", "display_name": "Miner", "description": "", "priority": 75, "income": _normalize_amounts_to_dict_array({"matter": 6.0}), "expense": _normalize_amounts_to_dict_array({"energy": 0.5})},
	}
	_job_ids = ["administrator", "technician", "miner", "farmer"]


func _install_fallback_building_definitions() -> void:
	_buildings_by_id = {
		"capital_hub": {"id": "capital_hub", "display_name": "Capital Hub", "description": "", "sort_key": 10, "job_slots": {"administrator": 30}, "build_cost": [], "buildable": false, "max_per_colony": 1},
		"basic_farm": {"id": "basic_farm", "display_name": "Basic Farm", "description": "", "sort_key": 20, "job_slots": {"farmer": 120}, "build_cost": _normalize_amounts_to_dict_array({"matter": 350.0, "energy": 100.0}), "buildable": true, "max_per_colony": 0},
		"basic_reactor": {"id": "basic_reactor", "display_name": "Basic Reactor", "description": "", "sort_key": 30, "job_slots": {"technician": 100}, "build_cost": _normalize_amounts_to_dict_array({"matter": 500.0, "alloys": 100.0}), "buildable": true, "max_per_colony": 0},
		"basic_extractor": {"id": "basic_extractor", "display_name": "Basic Extractor", "description": "", "sort_key": 40, "job_slots": {"miner": 140}, "build_cost": _normalize_amounts_to_dict_array({"matter": 450.0, "energy": 150.0}), "buildable": true, "max_per_colony": 0},
	}
	_building_ids = ["capital_hub", "basic_farm", "basic_reactor", "basic_extractor"]


func _install_fallback_trait_definitions() -> void:
	_traits_by_id = {
		"technical": {"id": "technical", "display_name": "Technical", "description": "", "rules": [{"scope": "job_output", "resource_id": "energy", "operation": "percent", "value_bp": 1000}]},
		"adaptive": {"id": "adaptive", "display_name": "Adaptive", "description": "", "rules": [{"scope": "habitability", "operation": "add_points", "value": 5}]},
	}


func _normalize_amounts_to_dict_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for amount in RESOURCE_AMOUNT_DEF_SCRIPT.normalize_array(value):
		result.append(amount.to_dict())
	return result


func _normalize_int_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is not Dictionary:
		return result
	var source: Dictionary = value
	for key_variant in source.keys():
		var key := str(key_variant).strip_edges()
		if key.is_empty():
			continue
		var amount := int(source[key_variant])
		if amount <= 0:
			continue
		result[key] = amount
	return result


func _normalize_empire_records(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is not Array:
		return result
	for empire_variant in value:
		if empire_variant is Dictionary:
			result.append((empire_variant as Dictionary).duplicate(true))
	return result


func _resource_map_to_amount_array(resource_map: Dictionary) -> Array[Dictionary]:
	var resource_ids: Array[String] = []
	for resource_id_variant in resource_map.keys():
		var resource_id := str(resource_id_variant).strip_edges()
		if resource_id.is_empty():
			continue
		resource_ids.append(resource_id)
	resource_ids.sort()

	var result: Array[Dictionary] = []
	for resource_id in resource_ids:
		var milliunits := int(resource_map.get(resource_id, 0))
		if milliunits == 0:
			continue
		result.append({"resource_id": resource_id, "milliunits": milliunits})
	return result


func _build_colony_id(empire_id: String, system_id: String, planet_orbital_id: String) -> String:
	return "capital_%s_%s_%s" % [_sanitize_id(empire_id), _sanitize_id(system_id), _sanitize_id(planet_orbital_id)]


func _build_colony_source_id(colony_id: String) -> String:
	return "colony:%s" % colony_id


func _sanitize_id(value: String) -> String:
	var result := ""
	for index in range(value.length()):
		var character := value.substr(index, 1).to_lower()
		var is_letter := character >= "a" and character <= "z"
		var is_number := character >= "0" and character <= "9"
		if is_letter or is_number:
			result += character
		elif not result.ends_with("_"):
			result += "_"
	return result.strip_edges()


func _variant_to_packed_string_array(values: Variant) -> PackedStringArray:
	return SPECIES_RUNTIME_SCRIPT._variant_to_packed_string_array(values)


func _packed_string_array_to_array(values: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(value)
	return result


func _packed_string_array_map_to_arrays(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_variant in source.keys():
		result[str(key_variant)] = _packed_string_array_to_array(source[key_variant])
	return result


func _sort_job_ids(a: String, b: String) -> bool:
	var priority_a := int(_jobs_by_id.get(a, {}).get("priority", 0))
	var priority_b := int(_jobs_by_id.get(b, {}).get("priority", 0))
	if priority_a == priority_b:
		return a < b
	return priority_a > priority_b


func _sort_building_ids(a: String, b: String) -> bool:
	var sort_a := int(_buildings_by_id.get(a, {}).get("sort_key", 0))
	var sort_b := int(_buildings_by_id.get(b, {}).get("sort_key", 0))
	if sort_a == sort_b:
		return a < b
	return sort_a < sort_b


static func _sort_species_count_entries(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("species_name", "")).naturalnocasecmp_to(str(b.get("species_name", ""))) < 0


static func _sort_snapshots_by_id(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("id", "")).naturalnocasecmp_to(str(b.get("id", ""))) < 0
