extends Resource
class_name ShipComponent

@export var component_key: StringName = &""


func to_dict() -> Dictionary:
	return {
		"component_key": str(component_key),
	}
