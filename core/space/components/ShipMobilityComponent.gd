extends ShipComponent
class_name ShipMobilityComponent

@export_range(0.0, 10000.0, 0.01) var cruise_speed: float = 1.0
@export_range(0.0, 10000.0, 0.01) var acceleration: float = 1.0
@export_range(0.0, 3600.0, 0.1) var turn_rate_degrees: float = 180.0
@export_range(0.0, 1000.0, 0.01) var formation_radius: float = 3.0
@export var can_join_fleets: bool = true
@export var uses_hyperlanes: bool = true
@export var can_orbit_system_objects: bool = true


func _init() -> void:
	component_key = &"mobility"


func is_mobile() -> bool:
	return cruise_speed > 0.0


func to_dict() -> Dictionary:
	return {
		"component_key": str(component_key),
		"cruise_speed": maxf(cruise_speed, 0.0),
		"acceleration": maxf(acceleration, 0.0),
		"turn_rate_degrees": maxf(turn_rate_degrees, 0.0),
		"formation_radius": maxf(formation_radius, 0.0),
		"can_join_fleets": can_join_fleets,
		"uses_hyperlanes": uses_hyperlanes,
		"can_orbit_system_objects": can_orbit_system_objects,
	}


static func from_dict(data: Dictionary) -> ShipMobilityComponent:
	var component := ShipMobilityComponent.new()
	component.component_key = StringName(str(data.get("component_key", "mobility")))
	component.cruise_speed = maxf(float(data.get("cruise_speed", 1.0)), 0.0)
	component.acceleration = maxf(float(data.get("acceleration", 1.0)), 0.0)
	component.turn_rate_degrees = maxf(float(data.get("turn_rate_degrees", 180.0)), 0.0)
	component.formation_radius = maxf(float(data.get("formation_radius", 3.0)), 0.0)
	component.can_join_fleets = bool(data.get("can_join_fleets", true))
	component.uses_hyperlanes = bool(data.get("uses_hyperlanes", true))
	component.can_orbit_system_objects = bool(data.get("can_orbit_system_objects", true))
	return component
