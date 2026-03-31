extends RefCounted
class_name ShipRuntime

var ship_id: String = ""
var class_id: String = ""
var display_name: String = ""
var owner_empire_id: String = ""
var controller_kind: String = ShipOwnershipComponent.CONTROLLER_UNASSIGNED
var controller_peer_id: int = 0
var ai_role: StringName = &""
var current_system_id: String = ""
var destination_system_id: String = ""
var eta_days_remaining: int = 0
var fleet_id: String = ""
var max_hull_points: float = 100.0
var current_hull_points: float = 100.0
var command_revision: int = 0
var capability_mask: int = 0
var command_tags: PackedStringArray = PackedStringArray()
var metadata: Dictionary = {}


func is_mobile() -> bool:
	return (capability_mask & ShipClass.CAPABILITY_MOBILITY) != 0


func is_stationary() -> bool:
	return not is_mobile()


func can_join_fleet() -> bool:
	return is_mobile()


func get_hull_ratio() -> float:
	return current_hull_points / maxf(max_hull_points, 1.0)


func clear_fleet_assignment() -> void:
	fleet_id = ""


func to_dict() -> Dictionary:
	return {
		"ship_id": ship_id,
		"class_id": class_id,
		"display_name": display_name,
		"owner_empire_id": owner_empire_id,
		"controller_kind": controller_kind,
		"controller_peer_id": controller_peer_id,
		"ai_role": str(ai_role),
		"current_system_id": current_system_id,
		"destination_system_id": destination_system_id,
		"eta_days_remaining": eta_days_remaining,
		"fleet_id": fleet_id,
		"max_hull_points": max_hull_points,
		"current_hull_points": current_hull_points,
		"command_revision": command_revision,
		"capability_mask": capability_mask,
		"command_tags": command_tags.duplicate(),
		"metadata": metadata.duplicate(true),
	}


static func from_dict(data: Dictionary) -> ShipRuntime:
	var ship := ShipRuntime.new()
	ship.ship_id = str(data.get("ship_id", ""))
	ship.class_id = str(data.get("class_id", ""))
	ship.display_name = str(data.get("display_name", ""))
	ship.owner_empire_id = str(data.get("owner_empire_id", ""))
	ship.controller_kind = str(data.get("controller_kind", ShipOwnershipComponent.CONTROLLER_UNASSIGNED))
	ship.controller_peer_id = int(data.get("controller_peer_id", 0))
	ship.ai_role = StringName(str(data.get("ai_role", "")))
	ship.current_system_id = str(data.get("current_system_id", ""))
	ship.destination_system_id = str(data.get("destination_system_id", ""))
	ship.eta_days_remaining = maxi(int(data.get("eta_days_remaining", 0)), 0)
	ship.fleet_id = str(data.get("fleet_id", ""))
	ship.max_hull_points = maxf(float(data.get("max_hull_points", 100.0)), 1.0)
	ship.current_hull_points = clampf(float(data.get("current_hull_points", ship.max_hull_points)), 0.0, ship.max_hull_points)
	ship.command_revision = maxi(int(data.get("command_revision", 0)), 0)
	ship.capability_mask = int(data.get("capability_mask", 0))
	ship.command_tags = _variant_to_packed_string_array(data.get("command_tags", PackedStringArray()))
	ship.metadata = _sanitize_metadata(data.get("metadata", {}))
	return ship


static func _variant_to_packed_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if values is PackedStringArray:
		return values
	if values is not Array:
		return result
	for value_variant in values:
		var value: String = str(value_variant).strip_edges()
		if value.is_empty():
			continue
		result.append(value)
	return result


static func _sanitize_metadata(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}
