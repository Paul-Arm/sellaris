extends Resource
class_name CustomStarSystem

@export var system_id: String = ""
@export var system_name: String = ""
@export var position: Vector3 = Vector3.ZERO
@export var star_color: Color = Color(1.0, 0.95, 0.82, 1.0)
@export var star_class: String = "G"
@export var planet_count_override: int = -1
@export var planet_names: PackedStringArray = PackedStringArray()
@export_multiline var notes: String = ""


func get_resolved_id(index: int) -> String:
	if not system_id.is_empty():
		return system_id
	return "custom_%03d" % index


func get_resolved_name(index: int) -> String:
	if not system_name.is_empty():
		return system_name
	return "Custom System %03d" % index
