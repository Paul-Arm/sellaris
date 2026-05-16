extends Resource
class_name ColonyHostComponent

@export var habitat_kind: String = "habitat"
@export_range(0, 100, 1) var base_habitability_points: int = 50
@export_range(0, 12, 1) var building_grid_radius: int = 3
@export var starter_buildings: PackedStringArray = PackedStringArray()
@export var starter_building_slots: Dictionary = {}
@export var auto_create_colony: bool = false
@export var display_metadata: Dictionary = {}


func ensure_defaults() -> void:
	habitat_kind = habitat_kind.strip_edges()
	if habitat_kind.is_empty():
		habitat_kind = "habitat"
	base_habitability_points = clampi(base_habitability_points, 0, 100)
	building_grid_radius = clampi(building_grid_radius, 0, 12)
	starter_buildings = _normalize_string_array(starter_buildings)
	starter_building_slots = _normalize_string_dictionary(starter_building_slots)
	display_metadata = _sanitize_metadata(display_metadata)


func to_dict() -> Dictionary:
	ensure_defaults()
	return {
		"habitat_kind": habitat_kind,
		"base_habitability_points": base_habitability_points,
		"building_grid_radius": building_grid_radius,
		"starter_buildings": _packed_string_array_to_array(starter_buildings),
		"starter_building_slots": starter_building_slots.duplicate(true),
		"auto_create_colony": auto_create_colony,
		"display_metadata": display_metadata.duplicate(true),
	}


static func from_dict(data: Dictionary):
	var component = load("res://core/economy/components/ColonyHostComponent.gd").new()
	component.habitat_kind = str(data.get("habitat_kind", data.get("kind", "habitat")))
	component.base_habitability_points = int(data.get("base_habitability_points", data.get("habitability_points", 50)))
	component.building_grid_radius = int(data.get("building_grid_radius", 3))
	component.starter_buildings = _variant_to_packed_string_array(data.get("starter_buildings", []))
	component.starter_building_slots = data.get("starter_building_slots", {}).duplicate(true) if data.get("starter_building_slots", {}) is Dictionary else {}
	component.auto_create_colony = bool(data.get("auto_create_colony", false))
	component.display_metadata = data.get("display_metadata", {}).duplicate(true) if data.get("display_metadata", {}) is Dictionary else {}
	component.ensure_defaults()
	return component


static func _normalize_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	for value_variant in _variant_to_packed_string_array(values):
		var value := str(value_variant).strip_edges()
		if value.is_empty() or result.has(value):
			continue
		result.append(value)
	return result


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


static func _sanitize_metadata(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}


static func _packed_string_array_to_array(values: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(value)
	return result
