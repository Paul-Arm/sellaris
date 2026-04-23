extends Resource
class_name ResourceAmountDef

@export var resource_id: String = ""
@export var milliunits: int = 0


func ensure_defaults() -> void:
	resource_id = resource_id.strip_edges()


func duplicate_amount() -> ResourceAmountDef:
	var copy := ResourceAmountDef.new()
	copy.resource_id = resource_id
	copy.milliunits = milliunits
	return copy


func to_dict() -> Dictionary:
	ensure_defaults()
	return {
		"resource_id": resource_id,
		"milliunits": milliunits,
	}


static func from_variant(value: Variant) -> ResourceAmountDef:
	if value is ResourceAmountDef:
		return (value as ResourceAmountDef).duplicate_amount()
	if value is not Dictionary:
		return null

	var data: Dictionary = value
	var amount := ResourceAmountDef.new()
	amount.resource_id = str(data.get("resource_id", data.get("id", ""))).strip_edges()
	if amount.resource_id.is_empty():
		return null

	if data.has("milliunits"):
		amount.milliunits = int(data.get("milliunits", 0))
	elif data.has("amount"):
		amount.milliunits = _convert_decimal_to_milliunits(float(data.get("amount", 0.0)))
	elif data.has("value"):
		amount.milliunits = int(data.get("value", 0))
	else:
		amount.milliunits = 0

	return amount


static func from_cost_map(cost_map: Dictionary) -> Array[ResourceAmountDef]:
	var result: Array[ResourceAmountDef] = []
	for resource_key_variant in cost_map.keys():
		var normalized_resource_id: String = str(resource_key_variant).strip_edges()
		if normalized_resource_id.is_empty():
			continue
		var amount := ResourceAmountDef.new()
		amount.resource_id = normalized_resource_id
		amount.milliunits = _convert_decimal_to_milliunits(float(cost_map.get(resource_key_variant, 0.0)))
		result.append(amount)
	return normalize_array(result)


static func normalize_array(values: Variant) -> Array[ResourceAmountDef]:
	var raw_values: Array = []
	if values is Array:
		raw_values = values
	elif values is Dictionary:
		return from_cost_map(values)
	else:
		return []

	var merged_by_resource_id: Dictionary = {}
	for value_variant in raw_values:
		var amount := from_variant(value_variant)
		if amount == null:
			continue
		amount.ensure_defaults()
		if amount.resource_id.is_empty() or amount.milliunits == 0:
			continue
		merged_by_resource_id[amount.resource_id] = int(merged_by_resource_id.get(amount.resource_id, 0)) + amount.milliunits

	var resource_ids: Array[String] = []
	for resource_id_variant in merged_by_resource_id.keys():
		resource_ids.append(str(resource_id_variant))
	resource_ids.sort()

	var result: Array[ResourceAmountDef] = []
	for normalized_resource_id in resource_ids:
		var merged_milliunits: int = int(merged_by_resource_id.get(normalized_resource_id, 0))
		if merged_milliunits == 0:
			continue
		var amount := ResourceAmountDef.new()
		amount.resource_id = normalized_resource_id
		amount.milliunits = merged_milliunits
		result.append(amount)

	return result


static func to_dict_array(values: Array[ResourceAmountDef]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in normalize_array(values):
		result.append(value.to_dict())
	return result


static func _convert_decimal_to_milliunits(value: float) -> int:
	return int(round(value * 1000.0))
