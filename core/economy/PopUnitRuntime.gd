class_name PopUnitRuntime
extends RefCounted

const DEFAULT_SIZE := 1000

var pop_unit_id: String = ""
var species_id: String = ""
var size: int = DEFAULT_SIZE
var assigned_job_id: String = ""


func ensure_defaults(index: int = 0) -> void:
	pop_unit_id = pop_unit_id.strip_edges()
	species_id = species_id.strip_edges()
	assigned_job_id = assigned_job_id.strip_edges()
	size = maxi(size, 1)
	if pop_unit_id.is_empty():
		pop_unit_id = "pop_%02d" % index


func to_dict() -> Dictionary:
	ensure_defaults()
	return {
		"id": pop_unit_id,
		"species_id": species_id,
		"size": size,
		"assigned_job_id": assigned_job_id,
	}


static func from_dict(data: Dictionary, index: int = 0):
	var pop_unit = load("res://core/economy/PopUnitRuntime.gd").new()
	pop_unit.pop_unit_id = str(data.get("id", data.get("pop_unit_id", "")))
	pop_unit.species_id = str(data.get("species_id", ""))
	pop_unit.size = int(data.get("size", DEFAULT_SIZE))
	pop_unit.assigned_job_id = str(data.get("assigned_job_id", data.get("job_id", "")))
	pop_unit.ensure_defaults(index)
	return pop_unit
