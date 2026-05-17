extends Resource
class_name SpaceUnitClass

const COLONY_HOST_COMPONENT_SCRIPT := preload("res://core/economy/components/ColonyHostComponent.gd")
const BUILDABLE_COMPONENT_SCRIPT := preload("res://core/space/components/SpaceUnitBuildableComponent.gd")
const BUILDER_COMPONENT_SCRIPT := preload("res://core/space/components/SpaceUnitBuilderComponent.gd")
const EXPLORER_COMPONENT_SCRIPT := preload("res://core/space/components/SpaceUnitExplorerComponent.gd")

const UNIT_KIND_SHIP := "ship"
const UNIT_KIND_STATION := "station"
const UNIT_KIND_CREATURE := "creature"

const CATEGORY_COMBAT := "combat"
const CATEGORY_CIVILIAN := "civilian"
const CATEGORY_SUPPORT := "support"
const CATEGORY_STATION := "station"
const CATEGORY_CREATURE := "creature"

const CAPABILITY_OWNERSHIP := 1
const CAPABILITY_UPKEEP := 2
const CAPABILITY_MOBILITY := 4
const CAPABILITY_COLONY := 8
const CAPABILITY_BUILDER := 16
const CAPABILITY_BUILDABLE := 32
const CAPABILITY_EXPLORER := 64

@export var class_id: String = ""
@export var display_name: String = ""
@export_enum("ship", "station", "creature") var unit_kind: String = UNIT_KIND_SHIP
@export_enum("combat", "civilian", "support", "station", "creature") var category: String = CATEGORY_COMBAT
@export_range(1.0, 1000000.0, 1.0) var max_hull_points: float = 100.0
@export var default_ai_role: StringName = &""
@export var command_tags: PackedStringArray = PackedStringArray()
@export var ownership_component: SpaceUnitOwnershipComponent
@export var upkeep_component: SpaceUnitUpkeepComponent
@export var mobility_component: SpaceUnitMobilityComponent
@export var colony_host_component: Resource
@export var builder_component: Resource
@export var buildable_component: Resource
@export var explorer_component: Resource
@export var component_slots: Array[Dictionary] = []
@export var loadout_components: Array[SpaceUnitComponent] = []
@export var metadata: Dictionary = {}


func ensure_defaults() -> void:
	class_id = class_id.strip_edges()
	display_name = display_name.strip_edges()
	if display_name.is_empty():
		display_name = resource_name.strip_edges()
	if class_id.is_empty():
		class_id = _slugify(display_name if not display_name.is_empty() else "space_unit_class")
	if display_name.is_empty():
		display_name = class_id.replace("_", " ").capitalize()
	if ownership_component == null:
		ownership_component = SpaceUnitOwnershipComponent.new()
	if upkeep_component == null:
		upkeep_component = SpaceUnitUpkeepComponent.new()
	if colony_host_component != null and colony_host_component.has_method("ensure_defaults"):
		colony_host_component.call("ensure_defaults")
	if builder_component != null and builder_component.has_method("ensure_defaults"):
		builder_component.call("ensure_defaults")
	if buildable_component != null and buildable_component.has_method("ensure_defaults"):
		buildable_component.call("ensure_defaults")
	if explorer_component != null and explorer_component.has_method("ensure_defaults"):
		explorer_component.call("ensure_defaults")
	command_tags = _normalize_tags(command_tags)
	unit_kind = _normalize_unit_kind(unit_kind)
	category = _normalize_category(category)
	component_slots = _normalize_component_slots(component_slots)
	loadout_components = _normalize_loadout_components(loadout_components)
	metadata = _sanitize_metadata(metadata)


func has_mobility() -> bool:
	return mobility_component != null and mobility_component.is_mobile()


func is_stationary() -> bool:
	return not has_mobility()


func can_join_fleet() -> bool:
	return mobility_component != null and mobility_component.is_mobile() and mobility_component.can_join_fleets


func has_colony_host() -> bool:
	return colony_host_component != null


func has_builder() -> bool:
	return builder_component != null


func has_explorer() -> bool:
	return explorer_component != null


func is_buildable() -> bool:
	return buildable_component != null


func get_build_time_days() -> int:
	if buildable_component == null:
		return 0
	return maxi(int(buildable_component.get("build_time_days")), 1)


func get_build_tags() -> PackedStringArray:
	if buildable_component == null:
		return PackedStringArray()
	return _variant_to_packed_string_array(buildable_component.get("build_tags"))


func can_builder_construct(builder_class: SpaceUnitClass) -> bool:
	if builder_class == null or builder_class.builder_component == null or buildable_component == null:
		return false
	if not bool(buildable_component.get("buildable_by_builder_ships")):
		return false
	if not builder_class.builder_component.has_method("can_build_tags"):
		return false
	return bool(builder_class.builder_component.call("can_build_tags", buildable_component.get("build_tags")))


func get_capability_mask() -> int:
	var mask := 0
	if ownership_component != null:
		mask |= CAPABILITY_OWNERSHIP
	if upkeep_component != null:
		mask |= CAPABILITY_UPKEEP
	if mobility_component != null and mobility_component.is_mobile():
		mask |= CAPABILITY_MOBILITY
	if colony_host_component != null:
		mask |= CAPABILITY_COLONY
	if builder_component != null:
		mask |= CAPABILITY_BUILDER
	if buildable_component != null:
		mask |= CAPABILITY_BUILDABLE
	if explorer_component != null:
		mask |= CAPABILITY_EXPLORER
	return mask


func get_monthly_upkeep() -> Array[ResourceAmountDef]:
	if upkeep_component == null:
		return []
	return upkeep_component.get_monthly_costs()


func get_build_costs() -> Array[ResourceAmountDef]:
	if upkeep_component == null:
		return []
	return upkeep_component.get_build_costs()


func get_in_system_speed() -> float:
	if mobility_component == null or not mobility_component.is_mobile():
		return 0.0
	return maxf(mobility_component.cruise_speed, 0.0)


func get_formation_radius() -> float:
	if mobility_component == null:
		return 0.0
	return maxf(mobility_component.formation_radius, 0.0)


func to_dict() -> Dictionary:
	ensure_defaults()
	return {
		"class_id": class_id,
		"display_name": display_name,
		"unit_kind": unit_kind,
		"category": category,
		"max_hull_points": max_hull_points,
		"default_ai_role": str(default_ai_role),
		"command_tags": command_tags.duplicate(),
		"ownership_component": ownership_component.to_dict() if ownership_component != null else {},
		"upkeep_component": upkeep_component.to_dict() if upkeep_component != null else {},
		"mobility_component": mobility_component.to_dict() if mobility_component != null else {},
		"colony_host_component": colony_host_component.call("to_dict") if colony_host_component != null and colony_host_component.has_method("to_dict") else {},
		"builder_component": builder_component.call("to_dict") if builder_component != null and builder_component.has_method("to_dict") else {},
		"buildable_component": buildable_component.call("to_dict") if buildable_component != null and buildable_component.has_method("to_dict") else {},
		"explorer_component": explorer_component.call("to_dict") if explorer_component != null and explorer_component.has_method("to_dict") else {},
		"component_slots": component_slots.duplicate(true),
		"loadout_components": _loadout_components_to_dict_array(loadout_components),
		"metadata": metadata.duplicate(true),
	}


static func from_dict(data: Dictionary) -> SpaceUnitClass:
	var unit_class := SpaceUnitClass.new()
	unit_class.class_id = str(data.get("class_id", ""))
	unit_class.display_name = str(data.get("display_name", ""))
	unit_class.unit_kind = str(data.get("unit_kind", data.get("kind", UNIT_KIND_SHIP)))
	unit_class.category = str(data.get("category", CATEGORY_COMBAT))
	unit_class.max_hull_points = maxf(float(data.get("max_hull_points", 100.0)), 1.0)
	unit_class.default_ai_role = StringName(str(data.get("default_ai_role", "")))
	unit_class.command_tags = _variant_to_packed_string_array(data.get("command_tags", PackedStringArray()))
	unit_class.component_slots = _normalize_component_slots(data.get("component_slots", []))
	unit_class.metadata = _sanitize_metadata(data.get("metadata", {}))
	var ownership_data: Dictionary = data.get("ownership_component", {})
	if not ownership_data.is_empty():
		unit_class.ownership_component = SpaceUnitOwnershipComponent.from_dict(ownership_data)
	var upkeep_data: Dictionary = data.get("upkeep_component", {})
	if not upkeep_data.is_empty():
		unit_class.upkeep_component = SpaceUnitUpkeepComponent.from_dict(upkeep_data)
	var mobility_data: Dictionary = data.get("mobility_component", {})
	if not mobility_data.is_empty():
		unit_class.mobility_component = SpaceUnitMobilityComponent.from_dict(mobility_data)
	var colony_host_data: Dictionary = data.get("colony_host_component", {})
	if not colony_host_data.is_empty():
		unit_class.colony_host_component = COLONY_HOST_COMPONENT_SCRIPT.from_dict(colony_host_data)
	var builder_data: Dictionary = data.get("builder_component", {})
	if not builder_data.is_empty():
		unit_class.builder_component = BUILDER_COMPONENT_SCRIPT.from_dict(builder_data)
	var buildable_data: Dictionary = data.get("buildable_component", {})
	if not buildable_data.is_empty():
		unit_class.buildable_component = BUILDABLE_COMPONENT_SCRIPT.from_dict(buildable_data)
	var explorer_data: Dictionary = data.get("explorer_component", {})
	if not explorer_data.is_empty():
		unit_class.explorer_component = EXPLORER_COMPONENT_SCRIPT.from_dict(explorer_data)
	unit_class.loadout_components = _variant_to_loadout_components(data.get("loadout_components", []))
	unit_class.ensure_defaults()
	return unit_class


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


static func _normalize_unit_kind(value: String) -> String:
	match value:
		UNIT_KIND_STATION, UNIT_KIND_CREATURE, UNIT_KIND_SHIP:
			return value
		_:
			return UNIT_KIND_SHIP


static func _normalize_category(value: String) -> String:
	match value:
		CATEGORY_COMBAT, CATEGORY_CIVILIAN, CATEGORY_SUPPORT, CATEGORY_STATION, CATEGORY_CREATURE:
			return value
		_:
			return CATEGORY_COMBAT


static func _normalize_component_slots(values: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if values is not Array:
		return result
	for value_variant in values:
		if value_variant is not Dictionary:
			continue
		var data: Dictionary = value_variant
		var slot_id := str(data.get("slot_id", data.get("id", ""))).strip_edges()
		var slot_kind := str(data.get("slot_kind", data.get("kind", ""))).strip_edges()
		if slot_id.is_empty() or slot_kind.is_empty():
			continue
		result.append({
			"slot_id": slot_id,
			"slot_kind": slot_kind,
			"required": bool(data.get("required", false)),
			"metadata": data.get("metadata", {}).duplicate(true) if data.get("metadata", {}) is Dictionary else {},
		})
	return result


static func _normalize_loadout_components(values: Variant) -> Array[SpaceUnitComponent]:
	if values is Array:
		return _variant_to_loadout_components(values)
	return []


static func _variant_to_loadout_components(values: Variant) -> Array[SpaceUnitComponent]:
	var result: Array[SpaceUnitComponent] = []
	if values is not Array:
		return result
	for value_variant in values:
		if value_variant is SpaceUnitComponent:
			result.append(value_variant)
			continue
		if value_variant is not Dictionary:
			continue
		var data: Dictionary = value_variant
		var component := SpaceUnitComponent.new()
		component.apply_base_dict(data)
		if component.component_key == &"":
			component.component_key = StringName(str(data.get("id", "")))
		result.append(component)
	return result


static func _loadout_components_to_dict_array(values: Array[SpaceUnitComponent]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for component in values:
		if component == null:
			continue
		result.append(component.to_dict())
	return result


static func _slugify(value: String) -> String:
	var source := value.to_lower().strip_edges()
	if source.is_empty():
		return "space_unit_class"

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
		return "space_unit_class"
	return result
