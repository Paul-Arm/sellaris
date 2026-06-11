extends RefCounted
class_name ShipComponentCatalog

const COMPONENT_DEFINITION_PATH := "res://core/space/design/ship_components.cfg"

var _components_by_id: Dictionary = {}
var _component_ids: Array[String] = []
var _catalog_version: int = 0


func load_definitions(definition_path: String = COMPONENT_DEFINITION_PATH) -> void:
	_components_by_id.clear()
	_component_ids.clear()
	_catalog_version += 1

	var config := ConfigFile.new()
	if config.load(definition_path) != OK:
		_install_fallback_definitions()
		return

	for section in config.get_sections():
		var data: Dictionary = {}
		for key in config.get_section_keys(section):
			data[key] = config.get_value(section, key)
		var definition := ShipComponentDefinition.from_dict(str(section), data)
		if definition == null:
			push_warning("ShipComponentCatalog: skipped invalid component definition '%s'" % str(section))
			continue
		_components_by_id[definition.component_id] = definition
		_component_ids.append(definition.component_id)

	if _components_by_id.is_empty():
		_install_fallback_definitions()
		return
	_sort_component_ids()


func get_catalog_version() -> int:
	return _catalog_version


func has_component(component_id: String) -> bool:
	return _components_by_id.has(component_id)


func get_component(component_id: String) -> ShipComponentDefinition:
	return _components_by_id.get(component_id, null)


func get_component_ids() -> Array[String]:
	return _component_ids.duplicate()


func get_component_ids_for_tier(unlock_tier: int) -> Array[String]:
	var result: Array[String] = []
	for component_id in _component_ids:
		var definition: ShipComponentDefinition = _components_by_id[component_id]
		if definition.unlock_tier == unlock_tier:
			result.append(component_id)
	return result


func get_component_ids_for_slot_kind(slot_kind: String) -> Array[String]:
	var result: Array[String] = []
	for component_id in _component_ids:
		var definition: ShipComponentDefinition = _components_by_id[component_id]
		if definition.slot_kind == slot_kind:
			result.append(component_id)
	return result


func _sort_component_ids() -> void:
	_component_ids.sort_custom(func(a: String, b: String) -> bool:
		var definition_a: ShipComponentDefinition = _components_by_id[a]
		var definition_b: ShipComponentDefinition = _components_by_id[b]
		if definition_a.sort_key == definition_b.sort_key:
			return a < b
		return definition_a.sort_key < definition_b.sort_key
	)


func _install_fallback_definitions() -> void:
	push_warning("ShipComponentCatalog: component config missing, installing fallback definitions")
	var fallback := {
		"basic_laser": {
			"display_name": "Basic Laser",
			"slot_kind": "weapon",
			"unlock_tier": 0,
			"sort_key": 10,
			"build_cost": {"alloys": 40.0},
			"monthly_upkeep": {"energy": 1.0},
			"build_time_days_add": 4,
			"weapon": {"damage": 12, "cooldown_days": 2, "range": 14.0, "accuracy_bp": 8500},
		},
		"basic_shield_emitter": {
			"display_name": "Basic Shield Emitter",
			"slot_kind": "defense",
			"unlock_tier": 0,
			"sort_key": 10,
			"build_cost": {"alloys": 35.0, "energy": 10.0},
			"monthly_upkeep": {"energy": 0.8},
			"build_time_days_add": 3,
			"stats": {"shield_add": 60, "shield_regen_per_day": 4},
		},
		"basic_armor_plating": {
			"display_name": "Basic Armor Plating",
			"slot_kind": "defense",
			"unlock_tier": 0,
			"sort_key": 20,
			"build_cost": {"alloys": 30.0},
			"monthly_upkeep": {"alloys": 0.1},
			"build_time_days_add": 3,
			"stats": {"armor_add": 8, "hull_add": 20},
		},
		"basic_drive": {
			"display_name": "Basic Drive",
			"slot_kind": "drive",
			"unlock_tier": 0,
			"sort_key": 10,
			"allowed_unit_kinds": ["ship"],
			"requires_mobility": true,
			"build_cost": {"alloys": 25.0, "energy": 10.0},
			"monthly_upkeep": {"energy": 0.5},
			"build_time_days_add": 2,
			"stats": {"cruise_speed": 6.0, "combat_speed": 9.0, "evasion_bp": 500},
		},
	}
	for component_id_variant in fallback.keys():
		var component_id := str(component_id_variant)
		var definition := ShipComponentDefinition.from_dict(component_id, fallback[component_id_variant])
		if definition == null:
			continue
		_components_by_id[component_id] = definition
		_component_ids.append(component_id)
	_sort_component_ids()
