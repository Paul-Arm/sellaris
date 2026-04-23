extends Resource
class_name CustomSystemOrbital

const TYPE_PLANET := "planet"
const TYPE_ASTEROID_BELT := "asteroid_belt"
const TYPE_STRUCTURE := "structure"
const TYPE_RUIN := "ruin"

@export var orbital_id: String = ""
@export var display_name: String = ""
@export_enum("planet", "asteroid_belt", "structure", "ruin") var orbital_type: String = TYPE_PLANET
@export var color: Color = Color(0.62, 0.74, 0.96, 1.0)
@export_range(0.4, 8.0, 0.01) var size: float = 1.0
@export_range(14.0, 240.0, 0.1) var orbit_radius: float = 36.0
@export_range(0.0, 360.0, 0.1) var orbit_angle_degrees: float = 0.0
@export_range(-18.0, 18.0, 0.1) var vertical_offset: float = 0.0
@export_range(0.0, 48.0, 0.1) var orbit_width: float = 0.0
@export var is_colonizable: bool = false
@export_range(0.0, 1.0, 0.01) var habitability: float = 0.0
@export_range(0, 100, 1) var resource_richness_points: int = 50
@export_range(0.0, 1.0, 0.01) var resource_richness: float = 0.5
@export_multiline var notes: String = ""
@export var metadata: Dictionary = {}


func to_dictionary(index: int) -> Dictionary:
	var resolved_id := orbital_id if not orbital_id.is_empty() else "%s_%02d" % [orbital_type, index]
	var default_name := "%s %d" % [orbital_type.replace("_", " ").capitalize(), index + 1]
	var resolved_name := display_name if not display_name.is_empty() else default_name
	var resolved_richness_points := _resolve_resource_richness_points()
	var resolved_habitability := clampf(habitability, 0.0, 1.0)
	return {
		"id": resolved_id,
		"name": resolved_name,
		"type": orbital_type,
		"color": color,
		"size": size,
		"orbit_radius": orbit_radius,
		"orbit_angle": deg_to_rad(orbit_angle_degrees),
		"vertical_offset": vertical_offset,
		"orbit_width": orbit_width,
		"is_colonizable": is_colonizable,
		"habitability": resolved_habitability,
		"habitability_points": int(round(resolved_habitability * 100.0)),
		"resource_richness_points": resolved_richness_points,
		"resource_richness": float(resolved_richness_points) / 100.0,
		"notes": notes,
		"metadata": metadata.duplicate(true),
	}


func _resolve_resource_richness_points() -> int:
	if resource_richness_points != 50 or is_equal_approx(resource_richness, 0.5):
		return clampi(resource_richness_points, 0, 100)
	return clampi(int(round(clampf(resource_richness, 0.0, 1.0) * 100.0)), 0, 100)
