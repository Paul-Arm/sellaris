extends ShipComponent
class_name ShipOwnershipComponent

const CONTROLLER_UNASSIGNED := "unassigned"
const CONTROLLER_LOCAL_PLAYER := "local_player"
const CONTROLLER_REMOTE_PLAYER := "remote_player"
const CONTROLLER_AI := "ai"
const CONTROLLER_SERVER_AUTHORITY := "server_authority"

@export var requires_owner: bool = true
@export var allow_local_player_control: bool = true
@export var allow_remote_player_control: bool = true
@export var allow_ai_control: bool = true
@export var authoritative_server_only: bool = true
@export var transfer_clears_fleet_assignment: bool = true


func _init() -> void:
	component_key = &"ownership"


func supports_controller(controller_kind: String) -> bool:
	match controller_kind:
		CONTROLLER_LOCAL_PLAYER:
			return allow_local_player_control
		CONTROLLER_REMOTE_PLAYER:
			return allow_remote_player_control
		CONTROLLER_AI:
			return allow_ai_control
		CONTROLLER_SERVER_AUTHORITY, CONTROLLER_UNASSIGNED, "":
			return true
		_:
			return false


func to_dict() -> Dictionary:
	return {
		"component_key": str(component_key),
		"requires_owner": requires_owner,
		"allow_local_player_control": allow_local_player_control,
		"allow_remote_player_control": allow_remote_player_control,
		"allow_ai_control": allow_ai_control,
		"authoritative_server_only": authoritative_server_only,
		"transfer_clears_fleet_assignment": transfer_clears_fleet_assignment,
	}


static func from_dict(data: Dictionary) -> ShipOwnershipComponent:
	var component := ShipOwnershipComponent.new()
	component.component_key = StringName(str(data.get("component_key", "ownership")))
	component.requires_owner = bool(data.get("requires_owner", true))
	component.allow_local_player_control = bool(data.get("allow_local_player_control", true))
	component.allow_remote_player_control = bool(data.get("allow_remote_player_control", true))
	component.allow_ai_control = bool(data.get("allow_ai_control", true))
	component.authoritative_server_only = bool(data.get("authoritative_server_only", true))
	component.transfer_clears_fleet_assignment = bool(data.get("transfer_clears_fleet_assignment", true))
	return component
