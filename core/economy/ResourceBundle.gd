extends RefCounted
class_name ResourceBundle

var resource_indices: PackedInt32Array = PackedInt32Array()
var amounts: PackedInt64Array = PackedInt64Array()


func is_empty() -> bool:
	return resource_indices.is_empty()


func size() -> int:
	return resource_indices.size()


func duplicate_bundle() -> ResourceBundle:
	var copy := ResourceBundle.new()
	copy.resource_indices = resource_indices.duplicate()
	copy.amounts = amounts.duplicate()
	return copy


func is_equal_to(other: ResourceBundle) -> bool:
	if other == null:
		return false
	if resource_indices.size() != other.resource_indices.size():
		return false
	for entry_index in range(resource_indices.size()):
		if resource_indices[entry_index] != other.resource_indices[entry_index]:
			return false
		if amounts[entry_index] != other.amounts[entry_index]:
			return false
	return true


func to_dict() -> Dictionary:
	return {
		"resource_indices": _packed_int32_to_array(resource_indices),
		"amounts": _packed_int64_to_array(amounts),
	}


static func from_dict(data: Dictionary) -> ResourceBundle:
	var bundle := ResourceBundle.new()
	var index_values: Variant = data.get("resource_indices", [])
	if index_values is Array:
		var packed_indices := PackedInt32Array()
		for index_variant in index_values:
			packed_indices.append(int(index_variant))
		bundle.resource_indices = packed_indices

	var amount_values: Variant = data.get("amounts", [])
	if amount_values is Array:
		var packed_amounts := PackedInt64Array()
		for amount_variant in amount_values:
			packed_amounts.append(int(amount_variant))
		bundle.amounts = packed_amounts

	return bundle


static func _packed_int32_to_array(values: PackedInt32Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(value)
	return result


static func _packed_int64_to_array(values: PackedInt64Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(value)
	return result
