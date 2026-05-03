extends Resource
class_name SpaceUnitComponent

@export var component_key: StringName = &""
@export var display_name: String = ""
@export var slot_kind: StringName = &""
@export var tags: PackedStringArray = PackedStringArray()
@export var metadata: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"component_key": str(component_key),
		"display_name": display_name,
		"slot_kind": str(slot_kind),
		"tags": tags.duplicate(),
		"metadata": metadata.duplicate(true) if metadata is Dictionary else {},
	}


func apply_base_dict(data: Dictionary) -> void:
	component_key = StringName(str(data.get("component_key", component_key)))
	display_name = str(data.get("display_name", display_name)).strip_edges()
	slot_kind = StringName(str(data.get("slot_kind", slot_kind)))
	tags = _variant_to_packed_string_array(data.get("tags", tags))
	metadata = data.get("metadata", {}).duplicate(true) if data.get("metadata", {}) is Dictionary else {}


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
