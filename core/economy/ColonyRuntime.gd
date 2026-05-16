class_name ColonyRuntime
extends RefCounted

const POP_UNIT_RUNTIME_SCRIPT := preload("res://core/economy/PopUnitRuntime.gd")

const HOST_KIND_ORBITAL := "orbital"
const HOST_KIND_SPACE_UNIT := "space_unit"

var colony_id: String = ""
var empire_id: String = ""
var system_id: String = ""
var host_kind: String = HOST_KIND_ORBITAL
var host_id: String = ""
var host_display_name: String = ""
var habitat_kind: String = "planet"
var host_record: Dictionary = {}
var planet_orbital_id: String = ""
var name: String = ""
var is_capital: bool = false
var buildings: PackedStringArray = PackedStringArray()
var building_slots: Dictionary = {}
var building_grid_radius: int = 3
var planet_record: Dictionary = {}
var pop_units: Array = []
var job_caps: Dictionary = {}
var command_revision: int = 0


func ensure_defaults(index: int = 0) -> void:
	colony_id = colony_id.strip_edges()
	empire_id = empire_id.strip_edges()
	system_id = system_id.strip_edges()
	host_kind = _normalize_host_kind(host_kind)
	host_id = host_id.strip_edges()
	host_display_name = host_display_name.strip_edges()
	habitat_kind = habitat_kind.strip_edges()
	planet_orbital_id = planet_orbital_id.strip_edges()
	name = name.strip_edges()
	host_record = _sanitize_dictionary(host_record)
	planet_record = _sanitize_dictionary(planet_record)
	if colony_id.is_empty():
		colony_id = "colony_%02d" % index
	if planet_orbital_id.is_empty():
		planet_orbital_id = str(planet_record.get("id", ""))
	if host_kind == HOST_KIND_ORBITAL:
		if host_id.is_empty():
			host_id = planet_orbital_id
		if host_record.is_empty() and not planet_record.is_empty():
			host_record = planet_record.duplicate(true)
		if planet_record.is_empty() and not host_record.is_empty():
			planet_record = host_record.duplicate(true)
		if planet_orbital_id.is_empty():
			planet_orbital_id = host_id
		if habitat_kind.is_empty():
			habitat_kind = _resolve_planet_type(planet_record)
	else:
		if habitat_kind.is_empty():
			habitat_kind = "habitat"
		if planet_record.is_empty():
			planet_record = host_record.duplicate(true)
	if host_id.is_empty():
		host_id = planet_orbital_id
	if host_display_name.is_empty():
		host_display_name = str(host_record.get("name", host_record.get("display_name", planet_record.get("name", host_id))))
	if name.is_empty():
		name = host_display_name if not host_display_name.is_empty() else colony_id
	building_grid_radius = clampi(building_grid_radius, 0, 12)
	command_revision = maxi(command_revision, 0)

	var normalized_pops: Array = []
	for pop_index in range(pop_units.size()):
		var pop_unit = null
		var pop_variant: Variant = pop_units[pop_index]
		if pop_variant is Dictionary:
			pop_unit = POP_UNIT_RUNTIME_SCRIPT.from_dict(pop_variant, pop_index)
		else:
			pop_unit = pop_variant
		if pop_unit == null:
			continue
		pop_unit.ensure_defaults(pop_index)
		normalized_pops.append(pop_unit)
	pop_units = normalized_pops
	job_caps = _normalize_int_dictionary(job_caps)
	building_slots = _normalize_string_dictionary(building_slots)


func get_total_population() -> int:
	var total := 0
	for pop_variant in pop_units:
		var pop_unit = pop_variant
		if pop_unit == null:
			continue
		total += pop_unit.size
	return total


func get_assigned_pop_count() -> int:
	var count := 0
	for pop_variant in pop_units:
		var pop_unit = pop_variant
		if pop_unit != null and not pop_unit.assigned_job_id.is_empty():
			count += 1
	return count


func get_idle_pop_count() -> int:
	var count := 0
	for pop_variant in pop_units:
		var pop_unit = pop_variant
		if pop_unit != null and pop_unit.assigned_job_id.is_empty():
			count += 1
	return count


func find_pop_unit(pop_unit_id: String):
	pop_unit_id = pop_unit_id.strip_edges()
	if pop_unit_id.is_empty():
		return null
	for pop_variant in pop_units:
		var pop_unit = pop_variant
		if pop_unit != null and pop_unit.pop_unit_id == pop_unit_id:
			return pop_unit
	return null


func to_dict() -> Dictionary:
	ensure_defaults()
	var pop_snapshots: Array[Dictionary] = []
	for pop_variant in pop_units:
		var pop_unit = pop_variant
		if pop_unit == null:
			continue
		pop_snapshots.append(pop_unit.to_dict())
	return {
		"id": colony_id,
		"empire_id": empire_id,
		"system_id": system_id,
		"host_kind": host_kind,
		"host_id": host_id,
		"host_display_name": host_display_name,
		"habitat_kind": habitat_kind,
		"host_record": host_record.duplicate(true),
		"planet_orbital_id": planet_orbital_id,
		"name": name,
		"is_capital": is_capital,
		"buildings": _packed_string_array_to_array(buildings),
		"building_slots": building_slots.duplicate(true),
		"building_grid_radius": building_grid_radius,
		"planet_record": planet_record.duplicate(true),
		"pop_units": pop_snapshots,
		"job_caps": job_caps.duplicate(true),
		"command_revision": command_revision,
	}


static func from_dict(data: Dictionary, index: int = 0):
	var colony = load("res://core/economy/ColonyRuntime.gd").new()
	colony.colony_id = str(data.get("id", data.get("colony_id", "")))
	colony.empire_id = str(data.get("empire_id", ""))
	colony.system_id = str(data.get("system_id", ""))
	colony.host_kind = str(data.get("host_kind", HOST_KIND_ORBITAL))
	colony.host_id = str(data.get("host_id", ""))
	colony.host_display_name = str(data.get("host_display_name", ""))
	colony.habitat_kind = str(data.get("habitat_kind", ""))
	colony.host_record = data.get("host_record", {}).duplicate(true) if data.get("host_record", {}) is Dictionary else {}
	colony.planet_orbital_id = str(data.get("planet_orbital_id", ""))
	colony.name = str(data.get("name", ""))
	colony.is_capital = bool(data.get("is_capital", false))
	colony.buildings = _variant_to_packed_string_array(data.get("buildings", []))
	colony.building_slots = data.get("building_slots", {}).duplicate(true) if data.get("building_slots", {}) is Dictionary else {}
	colony.building_grid_radius = int(data.get("building_grid_radius", 3))
	colony.planet_record = data.get("planet_record", data.get("planet", {})).duplicate(true)
	colony.job_caps = data.get("job_caps", {}).duplicate(true) if data.get("job_caps", {}) is Dictionary else {}
	colony.command_revision = int(data.get("command_revision", 0))
	colony.pop_units = []
	for pop_index in range(data.get("pop_units", []).size()):
		var pop_variant: Variant = data.get("pop_units", [])[pop_index]
		if pop_variant is Dictionary:
			colony.pop_units.append(POP_UNIT_RUNTIME_SCRIPT.from_dict(pop_variant, pop_index))
	colony.ensure_defaults(index)
	return colony


static func _variant_to_packed_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if values is PackedStringArray:
		return values.duplicate()
	if values is not Array:
		return result
	for value_variant in values:
		var value := str(value_variant).strip_edges()
		if value.is_empty():
			continue
		result.append(value)
	return result


static func _normalize_string_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is not Dictionary:
		return result
	var source: Dictionary = value
	for key_variant in source.keys():
		var key := str(key_variant).strip_edges()
		var entry_value := str(source[key_variant]).strip_edges()
		if key.is_empty() or entry_value.is_empty():
			continue
		result[key] = entry_value
	return result


static func _normalize_int_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is not Dictionary:
		return result
	var source: Dictionary = value
	for key_variant in source.keys():
		var key := str(key_variant).strip_edges()
		if key.is_empty():
			continue
		result[key] = maxi(int(source[key_variant]), 0)
	return result


static func _normalize_host_kind(value: String) -> String:
	match value.strip_edges():
		HOST_KIND_SPACE_UNIT:
			return HOST_KIND_SPACE_UNIT
		HOST_KIND_ORBITAL, "":
			return HOST_KIND_ORBITAL
		_:
			return value.strip_edges()


static func _sanitize_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}


static func _resolve_planet_type(record: Dictionary) -> String:
	var metadata: Dictionary = record.get("metadata", {}) if record.get("metadata", {}) is Dictionary else {}
	var planet_visual: Dictionary = metadata.get("planet_visual", {}) if metadata.get("planet_visual", {}) is Dictionary else {}
	var planet_type := str(record.get("planet_class_id", "")).strip_edges()
	if planet_type.is_empty():
		planet_type = str(metadata.get("planet_class_id", "")).strip_edges()
	if planet_type.is_empty():
		planet_type = str(planet_visual.get("kind", "")).strip_edges()
	if planet_type.is_empty():
		planet_type = str(record.get("type", "planet")).strip_edges()
	return planet_type if not planet_type.is_empty() else "planet"


static func _packed_string_array_to_array(values: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(value)
	return result
