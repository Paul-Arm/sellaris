extends RefCounted
class_name FleetRuntime

var fleet_id: String = ""
var display_name: String = ""
var owner_empire_id: String = ""
var controller_kind: String = ShipOwnershipComponent.CONTROLLER_UNASSIGNED
var controller_peer_id: int = 0
var ai_role: StringName = &""
var current_system_id: String = ""
var destination_system_id: String = ""
var eta_days_remaining: int = 0
var home_system_id: String = ""
var ship_ids: PackedStringArray = PackedStringArray()
var command_queue: Array[Dictionary] = []
var command_revision: int = 0
var metadata: Dictionary = {}


func add_ship(ship_id: String) -> bool:
	if ship_id.is_empty() or ship_ids.has(ship_id):
		return false
	ship_ids.append(ship_id)
	command_revision += 1
	return true


func remove_ship(ship_id: String) -> bool:
	var ship_index := ship_ids.find(ship_id)
	if ship_index < 0:
		return false
	ship_ids.remove_at(ship_index)
	command_revision += 1
	return true


func is_empty() -> bool:
	return ship_ids.is_empty()


func to_dict() -> Dictionary:
	return {
		"fleet_id": fleet_id,
		"display_name": display_name,
		"owner_empire_id": owner_empire_id,
		"controller_kind": controller_kind,
		"controller_peer_id": controller_peer_id,
		"ai_role": str(ai_role),
		"current_system_id": current_system_id,
		"destination_system_id": destination_system_id,
		"eta_days_remaining": eta_days_remaining,
		"home_system_id": home_system_id,
		"ship_ids": ship_ids.duplicate(),
		"command_queue": command_queue.duplicate(true),
		"command_revision": command_revision,
		"metadata": metadata.duplicate(true),
	}


static func from_dict(data: Dictionary) -> FleetRuntime:
	var fleet := FleetRuntime.new()
	fleet.fleet_id = str(data.get("fleet_id", ""))
	fleet.display_name = str(data.get("display_name", ""))
	fleet.owner_empire_id = str(data.get("owner_empire_id", ""))
	fleet.controller_kind = str(data.get("controller_kind", ShipOwnershipComponent.CONTROLLER_UNASSIGNED))
	fleet.controller_peer_id = int(data.get("controller_peer_id", 0))
	fleet.ai_role = StringName(str(data.get("ai_role", "")))
	fleet.current_system_id = str(data.get("current_system_id", ""))
	fleet.destination_system_id = str(data.get("destination_system_id", ""))
	fleet.eta_days_remaining = maxi(int(data.get("eta_days_remaining", 0)), 0)
	fleet.home_system_id = str(data.get("home_system_id", ""))
	fleet.ship_ids = _variant_to_packed_string_array(data.get("ship_ids", PackedStringArray()))
	var queue_variant: Variant = data.get("command_queue", [])
	if queue_variant is Array:
		fleet.command_queue = queue_variant.duplicate(true)
	fleet.command_revision = maxi(int(data.get("command_revision", 0)), 0)
	fleet.metadata = _sanitize_metadata(data.get("metadata", {}))
	return fleet


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
