extends SpaceUnitComponent
class_name SpaceUnitExplorerComponent

const DEFAULT_SCAN_MIN_DAYS := 5
const DEFAULT_SCAN_MAX_DAYS := 15
const DEFAULT_SCAN_OFFSET_RADIUS := 4.0
const DEFAULT_ARRIVAL_DISTANCE := 0.45

@export_range(1, 365, 1) var scan_min_days: int = DEFAULT_SCAN_MIN_DAYS
@export_range(1, 365, 1) var scan_max_days: int = DEFAULT_SCAN_MAX_DAYS
@export_range(0.1, 50.0, 0.05) var scan_offset_radius: float = DEFAULT_SCAN_OFFSET_RADIUS
@export_range(0.05, 10.0, 0.05) var arrival_distance: float = DEFAULT_ARRIVAL_DISTANCE
@export var scan_body_types: PackedStringArray = PackedStringArray(["star", "planet", "asteroid_belt", "structure", "ruin"])
@export var discover_anomalies_per_body: bool = true
@export var grants_full_system_intel: bool = true


func _init() -> void:
	component_key = &"explorer"
	display_name = "Explorer"
	slot_kind = &"science"


func ensure_defaults() -> void:
	scan_min_days = maxi(scan_min_days, 1)
	scan_max_days = maxi(scan_max_days, scan_min_days)
	scan_offset_radius = maxf(scan_offset_radius, 0.1)
	arrival_distance = maxf(arrival_distance, 0.05)
	scan_body_types = _normalize_string_array(scan_body_types)
	if scan_body_types.is_empty():
		scan_body_types = PackedStringArray(["star", "planet", "asteroid_belt", "structure", "ruin"])


func supports_body_type(body_type: String) -> bool:
	return scan_body_types.has(body_type.strip_edges())


func get_scan_days(unit_id: String, system_id: String, body_id: String, galaxy_seed: int) -> int:
	ensure_defaults()
	var span: int = maxi(scan_max_days - scan_min_days, 0)
	if span <= 0:
		return scan_min_days
	var hash_value: int = _stable_hash("%d:%s:%s:%s" % [galaxy_seed, unit_id, system_id, body_id])
	return scan_min_days + (absi(hash_value) % (span + 1))


func to_dict() -> Dictionary:
	ensure_defaults()
	var data := super.to_dict()
	data.merge({
		"component_key": str(component_key),
		"scan_min_days": scan_min_days,
		"scan_max_days": scan_max_days,
		"scan_offset_radius": scan_offset_radius,
		"arrival_distance": arrival_distance,
		"scan_body_types": scan_body_types.duplicate(),
		"discover_anomalies_per_body": discover_anomalies_per_body,
		"grants_full_system_intel": grants_full_system_intel,
	}, true)
	return data


static func from_dict(data: Dictionary):
	var component = load("res://core/space/components/SpaceUnitExplorerComponent.gd").new()
	component.apply_base_dict(data)
	component.component_key = StringName(str(data.get("component_key", "explorer")))
	component.scan_min_days = int(data.get("scan_min_days", DEFAULT_SCAN_MIN_DAYS))
	component.scan_max_days = int(data.get("scan_max_days", DEFAULT_SCAN_MAX_DAYS))
	component.scan_offset_radius = float(data.get("scan_offset_radius", DEFAULT_SCAN_OFFSET_RADIUS))
	component.arrival_distance = float(data.get("arrival_distance", DEFAULT_ARRIVAL_DISTANCE))
	component.scan_body_types = _variant_to_packed_string_array(data.get("scan_body_types", component.scan_body_types))
	component.discover_anomalies_per_body = bool(data.get("discover_anomalies_per_body", true))
	component.grants_full_system_intel = bool(data.get("grants_full_system_intel", true))
	component.ensure_defaults()
	return component


static func _normalize_string_array(values: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}
	for value_variant in values:
		var value: String = str(value_variant).strip_edges()
		if value.is_empty() or seen.has(value):
			continue
		seen[value] = true
		result.append(value)
	return result


static func _variant_to_packed_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if values is PackedStringArray:
		return _normalize_string_array(values)
	if values is not Array:
		return result
	for value_variant in values:
		var value: String = str(value_variant).strip_edges()
		if value.is_empty():
			continue
		result.append(value)
	return _normalize_string_array(result)


static func _stable_hash(value: String) -> int:
	var hash_value := 2166136261
	for index in range(value.length()):
		hash_value = int((hash_value ^ value.unicode_at(index)) * 16777619) & 0x7fffffff
	return hash_value
