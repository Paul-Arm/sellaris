extends RefCounted
class_name ShipDesignCatalog

const DESIGN_COMPILER_SCRIPT := preload("res://core/space/design/ShipDesignCompiler.gd")
const SHIP_DESIGN_RUNTIME_SCRIPT := preload("res://core/space/design/ShipDesignRuntime.gd")

var _component_catalog: ShipComponentCatalog = null
var _next_design_id: int = 1
var _designs_by_id: Dictionary = {}
var _design_ids_by_empire: Dictionary = {}
var _default_design_id_by_empire_class: Dictionary = {}
var _unlocked_component_ids_by_empire: Dictionary = {}
var _compiled_stats_cache: Dictionary = {}
var _last_validation_errors := PackedStringArray()


func setup(component_catalog: ShipComponentCatalog) -> void:
	_component_catalog = component_catalog


func get_component_catalog() -> ShipComponentCatalog:
	return _component_catalog


func reset_state() -> void:
	_next_design_id = 1
	_designs_by_id.clear()
	_design_ids_by_empire.clear()
	_default_design_id_by_empire_class.clear()
	_unlocked_component_ids_by_empire.clear()
	_compiled_stats_cache.clear()
	_last_validation_errors = PackedStringArray()


func get_last_validation_errors() -> PackedStringArray:
	return _last_validation_errors.duplicate()


# --- Unlocks ---

func bootstrap_empire_unlocks(empire_id: String) -> void:
	empire_id = empire_id.strip_edges()
	if empire_id.is_empty() or _component_catalog == null:
		return
	var unlocked: Dictionary = _unlocked_component_ids_by_empire.get(empire_id, {})
	for component_id in _component_catalog.get_component_ids_for_tier(0):
		unlocked[component_id] = true
	_unlocked_component_ids_by_empire[empire_id] = unlocked


func unlock_component(empire_id: String, component_id: String) -> bool:
	empire_id = empire_id.strip_edges()
	component_id = component_id.strip_edges()
	if empire_id.is_empty() or _component_catalog == null or not _component_catalog.has_component(component_id):
		return false
	var unlocked: Dictionary = _unlocked_component_ids_by_empire.get(empire_id, {})
	if unlocked.has(component_id):
		return false
	unlocked[component_id] = true
	_unlocked_component_ids_by_empire[empire_id] = unlocked
	return true


func is_component_unlocked(empire_id: String, component_id: String) -> bool:
	var unlocked: Dictionary = _unlocked_component_ids_by_empire.get(empire_id, {})
	return unlocked.has(component_id)


func get_unlocked_component_ids(empire_id: String) -> Array[String]:
	var unlocked: Dictionary = _unlocked_component_ids_by_empire.get(empire_id, {})
	var result: Array[String] = []
	for component_id_variant in unlocked.keys():
		result.append(str(component_id_variant))
	result.sort()
	return result


# --- Designs ---

func create_design(empire_id: String, unit_class: SpaceUnitClass, slot_assignments: Dictionary, options: Dictionary = {}) -> String:
	_last_validation_errors = PackedStringArray()
	empire_id = empire_id.strip_edges()
	if empire_id.is_empty() or unit_class == null:
		_last_validation_errors.append("invalid_arguments")
		return ""

	var normalized_assignments: Dictionary = SHIP_DESIGN_RUNTIME_SCRIPT._normalize_slot_assignments(slot_assignments)
	var unlocked: Dictionary = _unlocked_component_ids_by_empire.get(empire_id, {})
	_last_validation_errors = DESIGN_COMPILER_SCRIPT.validate(unit_class, normalized_assignments, _component_catalog, unlocked)
	if not _last_validation_errors.is_empty():
		return ""

	var design_id := str(options.get("design_id", "")).strip_edges()
	if design_id.is_empty():
		design_id = "design_%04d" % _next_design_id
		_next_design_id += 1
	if _designs_by_id.has(design_id):
		_last_validation_errors.append("duplicate_design_id:%s" % design_id)
		return ""

	var design := SHIP_DESIGN_RUNTIME_SCRIPT.new() as ShipDesignRuntime
	design.design_id = design_id
	design.empire_id = empire_id
	design.class_id = unit_class.class_id
	design.display_name = str(options.get("display_name", "%s Design" % unit_class.display_name)).strip_edges()
	design.slot_assignments = normalized_assignments
	design.is_default = bool(options.get("is_default", false))
	design.revision = 0

	_designs_by_id[design_id] = design
	var empire_design_ids: Array = _design_ids_by_empire.get(empire_id, [])
	empire_design_ids.append(design_id)
	_design_ids_by_empire[empire_id] = empire_design_ids
	if design.is_default:
		_set_default_design(empire_id, design.class_id, design_id)
	return design_id


func update_design(design_id: String, unit_class: SpaceUnitClass, slot_assignments: Dictionary) -> bool:
	_last_validation_errors = PackedStringArray()
	var design: ShipDesignRuntime = _designs_by_id.get(design_id, null)
	if design == null or unit_class == null or unit_class.class_id != design.class_id:
		_last_validation_errors.append("unknown_design:%s" % design_id)
		return false

	var normalized_assignments: Dictionary = SHIP_DESIGN_RUNTIME_SCRIPT._normalize_slot_assignments(slot_assignments)
	var unlocked: Dictionary = _unlocked_component_ids_by_empire.get(design.empire_id, {})
	_last_validation_errors = DESIGN_COMPILER_SCRIPT.validate(unit_class, normalized_assignments, _component_catalog, unlocked)
	if not _last_validation_errors.is_empty():
		return false

	design.slot_assignments = normalized_assignments
	design.revision += 1
	_compiled_stats_cache.erase(design_id)
	return true


func remove_design(design_id: String) -> bool:
	var design: ShipDesignRuntime = _designs_by_id.get(design_id, null)
	if design == null:
		return false
	_designs_by_id.erase(design_id)
	_compiled_stats_cache.erase(design_id)
	var empire_design_ids: Array = _design_ids_by_empire.get(design.empire_id, [])
	empire_design_ids.erase(design_id)
	if empire_design_ids.is_empty():
		_design_ids_by_empire.erase(design.empire_id)
	else:
		_design_ids_by_empire[design.empire_id] = empire_design_ids
	var class_defaults: Dictionary = _default_design_id_by_empire_class.get(design.empire_id, {})
	if str(class_defaults.get(design.class_id, "")) == design_id:
		class_defaults.erase(design.class_id)
		_default_design_id_by_empire_class[design.empire_id] = class_defaults
	return true


func set_default_design(design_id: String) -> bool:
	var design: ShipDesignRuntime = _designs_by_id.get(design_id, null)
	if design == null:
		return false
	var previous_default_id := get_default_design_id(design.empire_id, design.class_id)
	if previous_default_id == design_id:
		return false
	var previous_default: ShipDesignRuntime = _designs_by_id.get(previous_default_id, null)
	if previous_default != null:
		previous_default.is_default = false
	design.is_default = true
	_set_default_design(design.empire_id, design.class_id, design_id)
	return true


func rename_design(design_id: String, display_name: String) -> bool:
	var design: ShipDesignRuntime = _designs_by_id.get(design_id, null)
	display_name = display_name.strip_edges()
	if design == null or display_name.is_empty() or design.display_name == display_name:
		return false
	design.display_name = display_name
	design.revision += 1
	return true


func has_design(design_id: String) -> bool:
	return _designs_by_id.has(design_id)


func get_design(design_id: String) -> ShipDesignRuntime:
	return _designs_by_id.get(design_id, null)


func get_design_ids_for_empire(empire_id: String) -> Array[String]:
	var result: Array[String] = []
	for design_id_variant in _design_ids_by_empire.get(empire_id, []):
		result.append(str(design_id_variant))
	return result


func get_default_design_id(empire_id: String, class_id: String) -> String:
	var class_defaults: Dictionary = _default_design_id_by_empire_class.get(empire_id, {})
	return str(class_defaults.get(class_id, ""))


func get_compiled_stats(design_id: String, unit_class: SpaceUnitClass) -> Dictionary:
	var design: ShipDesignRuntime = _designs_by_id.get(design_id, null)
	if design == null or unit_class == null or _component_catalog == null:
		return {}

	var cache_key := "%s|%d|%d" % [design_id, design.revision, _component_catalog.get_catalog_version()]
	var cached_variant: Variant = _compiled_stats_cache.get(design_id, {})
	if cached_variant is Dictionary and str(cached_variant.get("cache_key", "")) == cache_key:
		return cached_variant.get("stats", {})

	var stats: Dictionary = DESIGN_COMPILER_SCRIPT.compile(unit_class, design.slot_assignments, _component_catalog)
	_compiled_stats_cache[design_id] = {
		"cache_key": cache_key,
		"stats": stats,
	}
	return stats


func _set_default_design(empire_id: String, class_id: String, design_id: String) -> void:
	var class_defaults: Dictionary = _default_design_id_by_empire_class.get(empire_id, {})
	class_defaults[class_id] = design_id
	_default_design_id_by_empire_class[empire_id] = class_defaults


# --- Default designs ---

func ensure_default_designs(empire_id: String, unit_classes: Array[SpaceUnitClass]) -> void:
	empire_id = empire_id.strip_edges()
	if empire_id.is_empty() or _component_catalog == null:
		return
	for unit_class in unit_classes:
		if unit_class == null:
			continue
		unit_class.ensure_defaults()
		if unit_class.get_design_slots().is_empty():
			continue
		if not get_default_design_id(empire_id, unit_class.class_id).is_empty():
			continue
		var assignments := _build_default_assignments(empire_id, unit_class)
		var design_id := create_design(empire_id, unit_class, assignments, {
			"display_name": "%s Mk I" % unit_class.display_name,
			"is_default": true,
		})
		if design_id.is_empty():
			push_warning("ShipDesignCatalog: failed to build default design for %s/%s: %s" % [
				empire_id,
				unit_class.class_id,
				", ".join(_last_validation_errors),
			])


func _build_default_assignments(empire_id: String, unit_class: SpaceUnitClass) -> Dictionary:
	var assignments: Dictionary = {}
	var defense_rotation_index := 0
	for slot in unit_class.get_design_slots():
		var slot_id := str(slot.get("slot_id", ""))
		var slot_kind := str(slot.get("slot_kind", ""))
		var slot_size := str(slot.get("slot_size", ShipComponentDefinition.SLOT_SIZE_MEDIUM))
		var fill_optional := slot_kind != ShipComponentDefinition.SLOT_KIND_UTILITY
		if not bool(slot.get("required", false)) and not fill_optional:
			continue
		var candidates := _get_unlocked_components_for_slot(empire_id, unit_class, slot_kind, slot_size)
		if candidates.is_empty():
			continue
		if slot_kind == ShipComponentDefinition.SLOT_KIND_DEFENSE:
			assignments[slot_id] = candidates[defense_rotation_index % candidates.size()]
			defense_rotation_index += 1
		else:
			assignments[slot_id] = candidates[0]
	return assignments


func _get_unlocked_components_for_slot(empire_id: String, unit_class: SpaceUnitClass, slot_kind: String, slot_size: String) -> Array[String]:
	var result: Array[String] = []
	var unlocked: Dictionary = _unlocked_component_ids_by_empire.get(empire_id, {})
	for component_id in _component_catalog.get_component_ids_for_slot_kind(slot_kind):
		if not unlocked.has(component_id):
			continue
		var definition := _component_catalog.get_component(component_id)
		if definition == null or not definition.fits_slot(slot_kind, slot_size):
			continue
		if not definition.allows_unit_kind(unit_class.unit_kind):
			continue
		if definition.requires_mobility and not unit_class.has_mobility():
			continue
		result.append(component_id)
	return result


# --- Snapshots ---

func build_snapshot() -> Dictionary:
	var design_snapshots: Array[Dictionary] = []
	for design_variant in _designs_by_id.values():
		var design: ShipDesignRuntime = design_variant
		design_snapshots.append(design.to_dict())

	var unlocks_snapshot: Dictionary = {}
	for empire_id_variant in _unlocked_component_ids_by_empire.keys():
		var empire_id := str(empire_id_variant)
		unlocks_snapshot[empire_id] = get_unlocked_component_ids(empire_id)

	return {
		"next_design_id": _next_design_id,
		"designs": design_snapshots,
		"unlocked_components_by_empire": unlocks_snapshot,
	}


func load_snapshot(snapshot: Dictionary) -> void:
	reset_state()
	if snapshot.is_empty():
		return

	_next_design_id = maxi(int(snapshot.get("next_design_id", 1)), 1)

	var unlocks_variant: Variant = snapshot.get("unlocked_components_by_empire", {})
	if unlocks_variant is Dictionary:
		for empire_id_variant in unlocks_variant.keys():
			var empire_id := str(empire_id_variant).strip_edges()
			if empire_id.is_empty():
				continue
			var unlocked: Dictionary = {}
			for component_id_variant in unlocks_variant.get(empire_id_variant, []):
				var component_id := str(component_id_variant).strip_edges()
				if component_id.is_empty():
					continue
				unlocked[component_id] = true
			_unlocked_component_ids_by_empire[empire_id] = unlocked

	for design_variant in snapshot.get("designs", []):
		if design_variant is not Dictionary:
			continue
		var design := SHIP_DESIGN_RUNTIME_SCRIPT.from_dict(design_variant) as ShipDesignRuntime
		if design == null or _designs_by_id.has(design.design_id):
			continue
		_designs_by_id[design.design_id] = design
		var empire_design_ids: Array = _design_ids_by_empire.get(design.empire_id, [])
		empire_design_ids.append(design.design_id)
		_design_ids_by_empire[design.empire_id] = empire_design_ids
		if design.is_default:
			_set_default_design(design.empire_id, design.class_id, design.design_id)
