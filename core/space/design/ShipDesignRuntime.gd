extends RefCounted
class_name ShipDesignRuntime

var design_id: String = ""
var empire_id: String = ""
var class_id: String = ""
var display_name: String = ""
var slot_assignments: Dictionary = {}
var is_default: bool = false
var revision: int = 0


func get_assigned_component_id(slot_id: String) -> String:
	return str(slot_assignments.get(slot_id, ""))


func to_dict() -> Dictionary:
	return {
		"design_id": design_id,
		"empire_id": empire_id,
		"class_id": class_id,
		"display_name": display_name,
		"slot_assignments": slot_assignments.duplicate(true),
		"is_default": is_default,
		"revision": revision,
	}


static func from_dict(data: Dictionary) -> ShipDesignRuntime:
	var design := ShipDesignRuntime.new()
	design.design_id = str(data.get("design_id", "")).strip_edges()
	if design.design_id.is_empty():
		return null
	design.empire_id = str(data.get("empire_id", "")).strip_edges()
	design.class_id = str(data.get("class_id", "")).strip_edges()
	design.display_name = str(data.get("display_name", design.design_id)).strip_edges()
	design.slot_assignments = _normalize_slot_assignments(data.get("slot_assignments", {}))
	design.is_default = bool(data.get("is_default", false))
	design.revision = maxi(int(data.get("revision", 0)), 0)
	return design


static func _normalize_slot_assignments(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var data: Dictionary = value
	var result: Dictionary = {}
	for slot_id_variant in data.keys():
		var slot_id := str(slot_id_variant).strip_edges()
		var component_id := str(data.get(slot_id_variant, "")).strip_edges()
		if slot_id.is_empty() or component_id.is_empty():
			continue
		result[slot_id] = component_id
	return result
