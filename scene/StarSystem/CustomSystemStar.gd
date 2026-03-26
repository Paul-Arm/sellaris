extends Resource
class_name CustomSystemStar

const SPECIAL_TYPE_NONE := "none"
const SPECIAL_TYPE_BLACK_HOLE := "Black hole"

@export var star_id: String = ""
@export var display_name: String = ""
@export var color: Color = Color(1.0, 0.95, 0.82, 1.0)
@export var star_class: String = "G"
@export_enum("none", "Neutron star", "Black hole", "O class star") var special_type: String = SPECIAL_TYPE_NONE
@export_enum("Gigant", "Normal", "Medium", "Small") var size_name: String = "Normal"
@export_range(0.4, 4.0, 0.01) var scale: float = 1.0
@export_range(0.0, 64.0, 0.1) var orbit_radius: float = 0.0
@export_range(0.0, 360.0, 0.1) var orbit_angle_degrees: float = 0.0
@export_range(-12.0, 12.0, 0.1) var vertical_offset: float = 0.0
@export var is_primary: bool = false


func to_dictionary(index: int) -> Dictionary:
	var resolved_id := star_id if not star_id.is_empty() else "star_%02d" % index
	var resolved_name := display_name if not display_name.is_empty() else "Star %d" % (index + 1)
	var resolved_star_class := star_class
	if special_type == "Neutron star" and resolved_star_class == "G":
		resolved_star_class = "Neutron"
	elif special_type == SPECIAL_TYPE_BLACK_HOLE and resolved_star_class == "G":
		resolved_star_class = "Black Hole"
	elif special_type == "O class star" and resolved_star_class == "G":
		resolved_star_class = "O"
	return {
		"id": resolved_id,
		"name": resolved_name,
		"index": index,
		"kind": "black_hole" if special_type == SPECIAL_TYPE_BLACK_HOLE else "star",
		"color_name": "",
		"color": color,
		"size_name": size_name,
		"scale": scale,
		"is_primary": is_primary or index == 0,
		"special_type": special_type,
		"star_class": resolved_star_class,
		"orbit_radius": orbit_radius,
		"orbit_angle": deg_to_rad(orbit_angle_degrees),
		"vertical_offset": vertical_offset,
	}
