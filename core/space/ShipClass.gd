extends Resource
class_name ShipClass

const CATEGORY_COMBAT := "combat"
const CATEGORY_CIVILIAN := "civilian"
const CATEGORY_SUPPORT := "support"
const CATEGORY_STATION := "station"

const CAPABILITY_OWNERSHIP := 1
const CAPABILITY_UPKEEP := 2
const CAPABILITY_MOBILITY := 4

@export var class_id: String = ""
@export var display_name: String = ""
@export_enum("combat", "civilian", "support", "station") var category: String = CATEGORY_COMBAT
@export_range(1.0, 1000000.0, 1.0) var max_hull_points: float = 100.0
@export var default_ai_role: StringName = &""
@export var command_tags: PackedStringArray = PackedStringArray()
@export var ownership_component: ShipOwnershipComponent
@export var upkeep_component: ShipUpkeepComponent
@export var mobility_component: ShipMobilityComponent
@export var metadata: Dictionary = {}


func ensure_defaults() -> void:
	class_id = class_id.strip_edges()
	display_name = display_name.strip_edges()
	if display_name.is_empty():
		display_name = resource_name.strip_edges()
	if class_id.is_empty():
		class_id = _slugify(display_name if not display_name.is_empty() else "ship_class")
	if display_name.is_empty():
		display_name = class_id.replace("_", " ").capitalize()
	if ownership_component == null:
		ownership_component = ShipOwnershipComponent.new()
	if upkeep_component == null:
		upkeep_component = ShipUpkeepComponent.new()
	command_tags = _normalize_tags(command_tags)
	metadata = _sanitize_metadata(metadata)


func has_mobility() -> bool:
	return mobility_component != null and mobility_component.is_mobile()


func is_stationary() -> bool:
	return not has_mobility()


func can_join_fleet() -> bool:
	return mobility_component != null and mobility_component.is_mobile() and mobility_component.can_join_fleets


func get_capability_mask() -> int:
	var mask := 0
	if ownership_component != null:
		mask |= CAPABILITY_OWNERSHIP
	if upkeep_component != null:
		mask |= CAPABILITY_UPKEEP
	if mobility_component != null and mobility_component.is_mobile():
		mask |= CAPABILITY_MOBILITY
	return mask


func get_monthly_upkeep() -> Dictionary:
	if upkeep_component == null:
		return {}
	return upkeep_component.get_monthly_costs()


func to_dict() -> Dictionary:
	ensure_defaults()
	return {
		"class_id": class_id,
		"display_name": display_name,
		"category": category,
		"max_hull_points": max_hull_points,
		"default_ai_role": str(default_ai_role),
		"command_tags": command_tags.duplicate(),
		"ownership_component": ownership_component.to_dict() if ownership_component != null else {},
		"upkeep_component": upkeep_component.to_dict() if upkeep_component != null else {},
		"mobility_component": mobility_component.to_dict() if mobility_component != null else {},
		"metadata": metadata.duplicate(true),
	}


static func from_dict(data: Dictionary) -> ShipClass:
	var ship_class := ShipClass.new()
	ship_class.class_id = str(data.get("class_id", ""))
	ship_class.display_name = str(data.get("display_name", ""))
	ship_class.category = str(data.get("category", CATEGORY_COMBAT))
	ship_class.max_hull_points = maxf(float(data.get("max_hull_points", 100.0)), 1.0)
	ship_class.default_ai_role = StringName(str(data.get("default_ai_role", "")))
	ship_class.command_tags = _variant_to_packed_string_array(data.get("command_tags", PackedStringArray()))
	ship_class.metadata = _sanitize_metadata(data.get("metadata", {}))
	var ownership_data: Dictionary = data.get("ownership_component", {})
	if not ownership_data.is_empty():
		ship_class.ownership_component = ShipOwnershipComponent.from_dict(ownership_data)
	var upkeep_data: Dictionary = data.get("upkeep_component", {})
	if not upkeep_data.is_empty():
		ship_class.upkeep_component = ShipUpkeepComponent.from_dict(upkeep_data)
	var mobility_data: Dictionary = data.get("mobility_component", {})
	if not mobility_data.is_empty():
		ship_class.mobility_component = ShipMobilityComponent.from_dict(mobility_data)
	ship_class.ensure_defaults()
	return ship_class


static func _variant_to_packed_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if values is PackedStringArray:
		return values
	if values is not Array:
		return result
	for value_variant in values:
		var value: String = str(value_variant).strip_edges()
		if value.is_empty():
			continue
		result.append(value)
	return result


static func _normalize_tags(values: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}
	for value_variant in values:
		var value: String = str(value_variant).strip_edges()
		if value.is_empty() or seen.has(value):
			continue
		seen[value] = true
		result.append(value)
	return result


static func _sanitize_metadata(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}


static func _slugify(value: String) -> String:
	var source := value.to_lower().strip_edges()
	if source.is_empty():
		return "ship_class"

	var result := ""
	for index in range(source.length()):
		var character := source.substr(index, 1)
		var is_letter := character >= "a" and character <= "z"
		var is_number := character >= "0" and character <= "9"
		if is_letter or is_number:
			result += character
			continue
		if result.is_empty() or result.ends_with("_"):
			continue
		result += "_"

	if result.is_empty():
		return "ship_class"
	return result
