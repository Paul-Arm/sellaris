extends RefCounted
class_name AnomalyComponent

const COMPONENT_KEY := "anomaly_component"
const MODE_GENERATED := "generated"
const MODE_FIXED := "fixed"
const MODE_ADDITIVE := "additive"
const MODE_NONE := "none"


static func normalize_component(value: Variant) -> Dictionary:
	var source: Dictionary = value.duplicate(true) if value is Dictionary else {}
	var mode := str(source.get("mode", MODE_GENERATED)).strip_edges().to_lower()
	match mode:
		MODE_GENERATED, MODE_FIXED, MODE_ADDITIVE, MODE_NONE:
			pass
		_:
			mode = MODE_GENERATED

	var max_instances := maxi(int(source.get("max_instances", 1)), 0)
	if mode == MODE_NONE:
		max_instances = 0

	return {
		"mode": mode,
		"spawn_chance_multiplier_bp": maxi(int(source.get("spawn_chance_multiplier_bp", 10000)), 0),
		"max_instances": max_instances,
		"spawn_tags": _normalize_string_array(source.get("spawn_tags", PackedStringArray())),
		"fixed_anomaly_ids": _normalize_string_array(source.get("fixed_anomaly_ids", PackedStringArray())),
		"display_metadata": source.get("display_metadata", {}).duplicate(true) if source.get("display_metadata", {}) is Dictionary else {},
		"anomalies": _normalize_visible_anomalies(source.get("anomalies", [])),
	}


static func _normalize_visible_anomalies(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is not Array:
		return result
	for anomaly_variant in value:
		if anomaly_variant is not Dictionary:
			continue
		result.append((anomaly_variant as Dictionary).duplicate(true))
	return result


static func _normalize_string_array(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}
	if value is PackedStringArray:
		value = Array(value)
	if value is String:
		value = [value]
	if value is not Array:
		return result
	for entry_variant in value:
		var entry := str(entry_variant).strip_edges()
		if entry.is_empty() or seen.has(entry):
			continue
		seen[entry] = true
		result.append(entry)
	return result
