extends SpaceUnitComponent
class_name SpaceUnitBuilderComponent

@export var buildable_tags: PackedStringArray = PackedStringArray(["orbital_station"])
@export var single_active_project: bool = true


func _init() -> void:
	component_key = &"builder"
	display_name = "Builder"
	slot_kind = &"construction"


func ensure_defaults() -> void:
	buildable_tags = _normalize_tags(buildable_tags)
	if buildable_tags.is_empty():
		buildable_tags.append("orbital_station")


func can_build_tags(candidate_tags: PackedStringArray) -> bool:
	ensure_defaults()
	if candidate_tags.is_empty():
		return false
	for tag in candidate_tags:
		if buildable_tags.has(tag):
			return true
	return false


func to_dict() -> Dictionary:
	ensure_defaults()
	var data := super.to_dict()
	data.merge({
		"component_key": str(component_key),
		"buildable_tags": buildable_tags.duplicate(),
		"single_active_project": single_active_project,
	}, true)
	return data


static func from_dict(data: Dictionary):
	var component = load("res://core/space/components/SpaceUnitBuilderComponent.gd").new()
	component.apply_base_dict(data)
	component.component_key = StringName(str(data.get("component_key", "builder")))
	component.buildable_tags = _variant_to_packed_string_array(data.get("buildable_tags", data.get("tags", PackedStringArray(["orbital_station"]))))
	component.single_active_project = bool(data.get("single_active_project", true))
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
