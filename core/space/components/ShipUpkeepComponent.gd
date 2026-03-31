extends ShipComponent
class_name ShipUpkeepComponent

@export var build_costs: Dictionary = {}
@export var monthly_costs: Dictionary = {}
@export_range(0.0, 1000.0, 0.01) var crew_requirement: float = 0.0
@export_range(0.0, 1000.0, 0.01) var command_point_cost: float = 0.0


func _init() -> void:
	component_key = &"upkeep"


func get_build_costs() -> Dictionary:
	return _sanitize_cost_map(build_costs)


func get_monthly_costs() -> Dictionary:
	return _sanitize_cost_map(monthly_costs)


func get_daily_costs(days_per_month: float = 30.0) -> Dictionary:
	var safe_days_per_month := maxf(days_per_month, 1.0)
	var sanitized_monthly_costs := get_monthly_costs()
	var daily_costs: Dictionary = {}

	for resource_key_variant in sanitized_monthly_costs.keys():
		var resource_key: String = str(resource_key_variant)
		daily_costs[resource_key] = float(sanitized_monthly_costs.get(resource_key_variant, 0.0)) / safe_days_per_month

	return daily_costs


func to_dict() -> Dictionary:
	return {
		"component_key": str(component_key),
		"build_costs": get_build_costs(),
		"monthly_costs": get_monthly_costs(),
		"crew_requirement": crew_requirement,
		"command_point_cost": command_point_cost,
	}


static func from_dict(data: Dictionary) -> ShipUpkeepComponent:
	var component := ShipUpkeepComponent.new()
	component.component_key = StringName(str(data.get("component_key", "upkeep")))
	component.build_costs = _sanitize_cost_map(data.get("build_costs", {}))
	component.monthly_costs = _sanitize_cost_map(data.get("monthly_costs", {}))
	component.crew_requirement = maxf(float(data.get("crew_requirement", 0.0)), 0.0)
	component.command_point_cost = maxf(float(data.get("command_point_cost", 0.0)), 0.0)
	return component


static func merge_cost_maps(base: Dictionary, addition: Dictionary, scale: float = 1.0) -> Dictionary:
	var result: Dictionary = _sanitize_cost_map(base)
	for resource_key_variant in addition.keys():
		var resource_key: String = str(resource_key_variant).strip_edges()
		if resource_key.is_empty():
			continue
		result[resource_key] = float(result.get(resource_key, 0.0)) + float(addition.get(resource_key_variant, 0.0)) * scale
		if is_zero_approx(float(result.get(resource_key, 0.0))):
			result.erase(resource_key)
	return result


static func subtract_cost_maps(base: Dictionary, removal: Dictionary, scale: float = 1.0) -> Dictionary:
	return merge_cost_maps(base, removal, -scale)


static func _sanitize_cost_map(source: Variant) -> Dictionary:
	var result: Dictionary = {}
	if source is not Dictionary:
		return result

	for resource_key_variant in source.keys():
		var resource_key: String = str(resource_key_variant).strip_edges()
		if resource_key.is_empty():
			continue
		var amount: float = float(source.get(resource_key_variant, 0.0))
		if is_zero_approx(amount):
			continue
		result[resource_key] = amount

	return result
