extends ShipComponent
class_name ShipUpkeepComponent

const RESOURCE_AMOUNT_DEF_SCRIPT := preload("res://core/economy/ResourceAmountDef.gd")

@export var build_costs: Array[ResourceAmountDef] = []
@export var monthly_costs: Array[ResourceAmountDef] = []
@export_range(0.0, 1000.0, 0.01) var crew_requirement: float = 0.0
@export_range(0.0, 1000.0, 0.01) var command_point_cost: float = 0.0


func _init() -> void:
	component_key = &"upkeep"


func get_build_costs() -> Array[ResourceAmountDef]:
	return RESOURCE_AMOUNT_DEF_SCRIPT.normalize_array(build_costs)


func get_monthly_costs() -> Array[ResourceAmountDef]:
	return RESOURCE_AMOUNT_DEF_SCRIPT.normalize_array(monthly_costs)


func to_dict() -> Dictionary:
	return {
		"component_key": str(component_key),
		"build_costs": RESOURCE_AMOUNT_DEF_SCRIPT.to_dict_array(get_build_costs()),
		"monthly_costs": RESOURCE_AMOUNT_DEF_SCRIPT.to_dict_array(get_monthly_costs()),
		"crew_requirement": crew_requirement,
		"command_point_cost": command_point_cost,
	}


static func from_dict(data: Dictionary) -> ShipUpkeepComponent:
	var component := ShipUpkeepComponent.new()
	component.component_key = StringName(str(data.get("component_key", "upkeep")))
	component.build_costs = RESOURCE_AMOUNT_DEF_SCRIPT.normalize_array(data.get("build_costs", []))
	component.monthly_costs = RESOURCE_AMOUNT_DEF_SCRIPT.normalize_array(data.get("monthly_costs", []))
	component.crew_requirement = maxf(float(data.get("crew_requirement", 0.0)), 0.0)
	component.command_point_cost = maxf(float(data.get("command_point_cost", 0.0)), 0.0)
	return component
