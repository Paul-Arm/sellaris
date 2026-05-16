extends SpaceUnitComponent
class_name SpaceUnitBuildableComponent

@export_range(1, 100000, 1) var build_time_days: int = 60
@export var buildable_by_builder_ships: bool = true
@export var build_tags: PackedStringArray = PackedStringArray(["orbital_station"])


func _init() -> void:
	component_key = &"buildable"
	display_name = "Buildable"
	slot_kind = &"construction"


func ensure_defaults() -> void:
	build_time_days = maxi(build_time_days, 1)
	build_tags = _normalize_tags(build_tags)
	if build_tags.is_empty():
		build_tags.append("orbital_station")


func to_dict() -> Dictionary:
	ensure_defaults()
	var data := super.to_dict()
	data.merge({
		"component_key": str(component_key),
		"build_time_days": build_time_days,
		"buildable_by_builder_ships": buildable_by_builder_ships,
		"build_tags": build_tags.duplicate(),
	}, true)
	return data


static func from_dict(data: Dictionary):
	var component = load("res://core/space/components/SpaceUnitBuildableComponent.gd").new()
	component.apply_base_dict(data)
	component.component_key = StringName(str(data.get("component_key", "buildable")))
	component.build_time_days = maxi(int(data.get("build_time_days", 60)), 1)
	component.buildable_by_builder_ships = bool(data.get("buildable_by_builder_ships", true))
	component.build_tags = _variant_to_packed_string_array(data.get("build_tags", data.get("tags", PackedStringArray(["orbital_station"]))))
	component.ensure_defaults()
	return component


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


static func _normalize_tags(values: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}
	for value_variant in values:
		var value := str(value_variant).strip_edges()
		if value.is_empty() or seen.has(value):
			continue
		seen[value] = true
		result.append(value)
	return result
