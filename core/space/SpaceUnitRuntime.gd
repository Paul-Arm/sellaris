extends RefCounted
class_name SpaceUnitRuntime

const MOVEMENT_IDLE := "idle"
const MOVEMENT_MOVING := "moving"

const STANCE_AGGRESSIVE := "aggressive"
const STANCE_PASSIVE := "passive"

var unit_id: String = ""
var class_id: String = ""
var design_id: String = ""
var display_name: String = ""
var owner_empire_id: String = ""
var controller_kind: String = SpaceUnitOwnershipComponent.CONTROLLER_UNASSIGNED
var controller_peer_id: int = 0
var ai_role: StringName = &""
var current_system_id: String = ""
var destination_system_id: String = ""
var eta_days_remaining: int = 0
var fleet_id: String = ""
var max_hull_points: int = 100
var current_hull_points: int = 100
var max_shield_points: int = 0
var current_shield_points: int = 0
var armor_points: int = 0
var evasion_bp: int = 0
var stance: String = STANCE_PASSIVE
var auto_engage_radius: float = 12.0
var battle_id: String = ""
var stunned_days_remaining: int = 0
var weapon_cooldowns: Dictionary = {}
var ability_cooldowns: Dictionary = {}
var pending_ability_commands: Array[Dictionary] = []
var command_revision: int = 0
var capability_mask: int = 0
var command_tags: PackedStringArray = PackedStringArray()
var local_position: Vector3 = Vector3.ZERO
var previous_local_position: Vector3 = Vector3.ZERO
var target_local_position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var movement_state: String = MOVEMENT_IDLE
var movement_order_id: int = 0
var last_movement_day_serial: int = 0
var metadata: Dictionary = {}


func is_mobile() -> bool:
	return (capability_mask & SpaceUnitClass.CAPABILITY_MOBILITY) != 0


func can_host_colony() -> bool:
	return (capability_mask & SpaceUnitClass.CAPABILITY_COLONY) != 0


func can_build_units() -> bool:
	return (capability_mask & SpaceUnitClass.CAPABILITY_BUILDER) != 0


func can_explore_systems() -> bool:
	return (capability_mask & SpaceUnitClass.CAPABILITY_EXPLORER) != 0


func is_stationary() -> bool:
	return not is_mobile()


func can_join_fleet() -> bool:
	return is_mobile()


func get_hull_ratio() -> float:
	return float(current_hull_points) / float(maxi(max_hull_points, 1))


func get_shield_ratio() -> float:
	if max_shield_points <= 0:
		return 0.0
	return float(current_shield_points) / float(max_shield_points)


func is_in_battle() -> bool:
	return not battle_id.is_empty()


func is_stunned() -> bool:
	return stunned_days_remaining > 0


func is_aggressive() -> bool:
	return stance == STANCE_AGGRESSIVE


func clear_fleet_assignment() -> void:
	fleet_id = ""


func has_active_movement() -> bool:
	return movement_state == MOVEMENT_MOVING


func set_local_position(value: Vector3, day_serial: int = 0) -> void:
	previous_local_position = value
	local_position = value
	target_local_position = value
	velocity = Vector3.ZERO
	movement_state = MOVEMENT_IDLE
	last_movement_day_serial = maxi(day_serial, 0)


func get_interpolated_local_position(day_progress: float) -> Vector3:
	if not has_active_movement():
		return local_position
	return previous_local_position.lerp(local_position, clampf(day_progress, 0.0, 1.0))


func to_dict() -> Dictionary:
	return {
		"unit_id": unit_id,
		"class_id": class_id,
		"design_id": design_id,
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
		"max_shield_points": max_shield_points,
		"current_shield_points": current_shield_points,
		"armor_points": armor_points,
		"evasion_bp": evasion_bp,
		"stance": stance,
		"auto_engage_radius": auto_engage_radius,
		"battle_id": battle_id,
		"stunned_days_remaining": stunned_days_remaining,
		"weapon_cooldowns": weapon_cooldowns.duplicate(true),
		"ability_cooldowns": ability_cooldowns.duplicate(true),
		"pending_ability_commands": pending_ability_commands.duplicate(true),
		"command_revision": command_revision,
		"capability_mask": capability_mask,
		"command_tags": command_tags.duplicate(),
		"local_position": _vector3_to_dict(local_position),
		"previous_local_position": _vector3_to_dict(previous_local_position),
		"target_local_position": _vector3_to_dict(target_local_position),
		"velocity": _vector3_to_dict(velocity),
		"movement_state": movement_state,
		"movement_order_id": movement_order_id,
		"last_movement_day_serial": last_movement_day_serial,
		"metadata": metadata.duplicate(true),
	}


static func from_dict(data: Dictionary) -> SpaceUnitRuntime:
	var unit := SpaceUnitRuntime.new()
	unit.unit_id = str(data.get("unit_id", data.get("ship_id", "")))
	unit.class_id = str(data.get("class_id", ""))
	unit.design_id = str(data.get("design_id", ""))
	unit.display_name = str(data.get("display_name", ""))
	unit.owner_empire_id = str(data.get("owner_empire_id", ""))
	unit.controller_kind = str(data.get("controller_kind", SpaceUnitOwnershipComponent.CONTROLLER_UNASSIGNED))
	unit.controller_peer_id = int(data.get("controller_peer_id", 0))
	unit.ai_role = StringName(str(data.get("ai_role", "")))
	unit.current_system_id = str(data.get("current_system_id", ""))
	unit.destination_system_id = str(data.get("destination_system_id", ""))
	unit.eta_days_remaining = maxi(int(data.get("eta_days_remaining", 0)), 0)
	unit.fleet_id = str(data.get("fleet_id", ""))
	unit.max_hull_points = maxi(int(round(float(data.get("max_hull_points", 100)))), 1)
	unit.current_hull_points = clampi(int(round(float(data.get("current_hull_points", unit.max_hull_points)))), 0, unit.max_hull_points)
	unit.max_shield_points = maxi(int(data.get("max_shield_points", 0)), 0)
	unit.current_shield_points = clampi(int(data.get("current_shield_points", unit.max_shield_points)), 0, unit.max_shield_points)
	unit.armor_points = maxi(int(data.get("armor_points", 0)), 0)
	unit.evasion_bp = clampi(int(data.get("evasion_bp", 0)), 0, 9500)
	unit.stance = _normalize_stance(str(data.get("stance", STANCE_PASSIVE)))
	unit.auto_engage_radius = maxf(float(data.get("auto_engage_radius", 12.0)), 0.0)
	unit.battle_id = str(data.get("battle_id", ""))
	unit.stunned_days_remaining = maxi(int(data.get("stunned_days_remaining", 0)), 0)
	unit.weapon_cooldowns = _sanitize_cooldowns(data.get("weapon_cooldowns", {}))
	unit.ability_cooldowns = _sanitize_cooldowns(data.get("ability_cooldowns", {}))
	unit.pending_ability_commands = _sanitize_command_array(data.get("pending_ability_commands", []))
	unit.command_revision = maxi(int(data.get("command_revision", 0)), 0)
	unit.capability_mask = int(data.get("capability_mask", 0))
	unit.command_tags = _variant_to_packed_string_array(data.get("command_tags", PackedStringArray()))
	unit.local_position = _variant_to_vector3(data.get("local_position", Vector3.ZERO))
	unit.previous_local_position = _variant_to_vector3(data.get("previous_local_position", unit.local_position))
	unit.target_local_position = _variant_to_vector3(data.get("target_local_position", unit.local_position))
	unit.velocity = _variant_to_vector3(data.get("velocity", Vector3.ZERO))
	unit.movement_state = str(data.get("movement_state", MOVEMENT_IDLE))
	if unit.movement_state != MOVEMENT_MOVING:
		unit.movement_state = MOVEMENT_IDLE
	unit.movement_order_id = maxi(int(data.get("movement_order_id", 0)), 0)
	unit.last_movement_day_serial = maxi(int(data.get("last_movement_day_serial", 0)), 0)
	unit.metadata = _sanitize_metadata(data.get("metadata", {}))
	return unit


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


static func _normalize_stance(value: String) -> String:
	if value == STANCE_AGGRESSIVE:
		return STANCE_AGGRESSIVE
	return STANCE_PASSIVE


static func _sanitize_cooldowns(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var data: Dictionary = value
	var result: Dictionary = {}
	for slot_id_variant in data.keys():
		var slot_id := str(slot_id_variant).strip_edges()
		var days := maxi(int(data.get(slot_id_variant, 0)), 0)
		if slot_id.is_empty() or days <= 0:
			continue
		result[slot_id] = days
	return result


static func _sanitize_command_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is not Array:
		return result
	for entry_variant in value:
		if entry_variant is Dictionary:
			result.append((entry_variant as Dictionary).duplicate(true))
	return result


static func _vector3_to_dict(value: Vector3) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
		"z": value.z,
	}


static func _variant_to_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return Vector3(
			float(value.get("x", 0.0)),
			float(value.get("y", 0.0)),
			float(value.get("z", 0.0))
		)
	if value is Array:
		var values: Array = value
		if values.size() >= 3:
			return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.ZERO
