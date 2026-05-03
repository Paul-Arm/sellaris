extends RefCounted
class_name SpaceFleetRuntime

var fleet_id: String = ""
var display_name: String = ""
var owner_empire_id: String = ""
var controller_kind: String = SpaceUnitOwnershipComponent.CONTROLLER_UNASSIGNED
var controller_peer_id: int = 0
var ai_role: StringName = &""
var current_system_id: String = ""
var destination_system_id: String = ""
var eta_days_remaining: int = 0
var home_system_id: String = ""
var unit_ids: PackedStringArray = PackedStringArray()
var command_queue: Array[Dictionary] = []
var command_revision: int = 0
var local_position: Vector3 = Vector3.ZERO
var previous_local_position: Vector3 = Vector3.ZERO
var target_local_position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var movement_state: String = SpaceUnitRuntime.MOVEMENT_IDLE
var movement_order_id: int = 0
var last_movement_day_serial: int = 0
var metadata: Dictionary = {}


func add_unit(unit_id: String) -> bool:
	if unit_id.is_empty() or unit_ids.has(unit_id):
		return false
	unit_ids.append(unit_id)
	command_revision += 1
	return true


func remove_unit(unit_id: String) -> bool:
	var unit_index := unit_ids.find(unit_id)
	if unit_index < 0:
		return false
	unit_ids.remove_at(unit_index)
	command_revision += 1
	return true


func is_empty() -> bool:
	return unit_ids.is_empty()


func has_active_movement() -> bool:
	return movement_state == SpaceUnitRuntime.MOVEMENT_MOVING


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
		"unit_ids": unit_ids.duplicate(),
		"command_queue": command_queue.duplicate(true),
		"command_revision": command_revision,
		"local_position": SpaceUnitRuntime._vector3_to_dict(local_position),
		"previous_local_position": SpaceUnitRuntime._vector3_to_dict(previous_local_position),
		"target_local_position": SpaceUnitRuntime._vector3_to_dict(target_local_position),
		"velocity": SpaceUnitRuntime._vector3_to_dict(velocity),
		"movement_state": movement_state,
		"movement_order_id": movement_order_id,
		"last_movement_day_serial": last_movement_day_serial,
		"metadata": metadata.duplicate(true),
	}


static func from_dict(data: Dictionary) -> SpaceFleetRuntime:
	var fleet := SpaceFleetRuntime.new()
	fleet.fleet_id = str(data.get("fleet_id", ""))
	fleet.display_name = str(data.get("display_name", ""))
	fleet.owner_empire_id = str(data.get("owner_empire_id", ""))
	fleet.controller_kind = str(data.get("controller_kind", SpaceUnitOwnershipComponent.CONTROLLER_UNASSIGNED))
	fleet.controller_peer_id = int(data.get("controller_peer_id", 0))
	fleet.ai_role = StringName(str(data.get("ai_role", "")))
	fleet.current_system_id = str(data.get("current_system_id", ""))
	fleet.destination_system_id = str(data.get("destination_system_id", ""))
	fleet.eta_days_remaining = maxi(int(data.get("eta_days_remaining", 0)), 0)
	fleet.home_system_id = str(data.get("home_system_id", ""))
	fleet.unit_ids = _variant_to_packed_string_array(data.get("unit_ids", data.get("ship_ids", PackedStringArray())))
	var queue_variant: Variant = data.get("command_queue", [])
	if queue_variant is Array:
		fleet.command_queue = queue_variant.duplicate(true)
	fleet.command_revision = maxi(int(data.get("command_revision", 0)), 0)
	fleet.local_position = SpaceUnitRuntime._variant_to_vector3(data.get("local_position", Vector3.ZERO))
	fleet.previous_local_position = SpaceUnitRuntime._variant_to_vector3(data.get("previous_local_position", fleet.local_position))
	fleet.target_local_position = SpaceUnitRuntime._variant_to_vector3(data.get("target_local_position", fleet.local_position))
	fleet.velocity = SpaceUnitRuntime._variant_to_vector3(data.get("velocity", Vector3.ZERO))
	fleet.movement_state = str(data.get("movement_state", SpaceUnitRuntime.MOVEMENT_IDLE))
	if fleet.movement_state != SpaceUnitRuntime.MOVEMENT_MOVING:
		fleet.movement_state = SpaceUnitRuntime.MOVEMENT_IDLE
	fleet.movement_order_id = maxi(int(data.get("movement_order_id", 0)), 0)
	fleet.last_movement_day_serial = maxi(int(data.get("last_movement_day_serial", 0)), 0)
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
