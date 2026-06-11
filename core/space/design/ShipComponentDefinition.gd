extends RefCounted
class_name ShipComponentDefinition

const RESOURCE_AMOUNT_DEF_SCRIPT := preload("res://core/economy/ResourceAmountDef.gd")

const SLOT_KIND_WEAPON := "weapon"
const SLOT_KIND_DEFENSE := "defense"
const SLOT_KIND_DRIVE := "drive"
const SLOT_KIND_UTILITY := "utility"
const EQUIPMENT_SLOT_KINDS: Array[String] = [
	SLOT_KIND_WEAPON,
	SLOT_KIND_DEFENSE,
	SLOT_KIND_DRIVE,
	SLOT_KIND_UTILITY,
]

const SLOT_SIZE_SMALL := "small"
const SLOT_SIZE_MEDIUM := "medium"
const SLOT_SIZE_LARGE := "large"
const SLOT_SIZES: Array[String] = [SLOT_SIZE_SMALL, SLOT_SIZE_MEDIUM, SLOT_SIZE_LARGE]

const ABILITY_TRIGGER_AUTO := "auto"
const ABILITY_TRIGGER_MANUAL := "manual"

const INT_STAT_KEYS: Array[String] = [
	"hull_add",
	"shield_add",
	"shield_regen_per_day",
	"armor_add",
	"evasion_bp",
]
const FLOAT_STAT_KEYS: Array[String] = [
	"cruise_speed",
	"combat_speed",
	"auto_engage_radius_add",
	"sensor_range_add",
]

var component_id: String = ""
var display_name: String = ""
var description: String = ""
var slot_kind: String = SLOT_KIND_UTILITY
var slot_size: String = SLOT_SIZE_MEDIUM
var unlock_tier: int = 0
var sort_key: int = 0
var allowed_unit_kinds: PackedStringArray = PackedStringArray(["ship", "station"])
var requires_mobility: bool = false
var build_cost: Array[Dictionary] = []
var monthly_upkeep: Array[Dictionary] = []
var build_time_days_add: int = 0
var stats: Dictionary = {}
var weapon: Dictionary = {}
var ability: Dictionary = {}


func is_weapon() -> bool:
	return not weapon.is_empty()


func has_ability() -> bool:
	return not ability.is_empty()


func is_manual_ability() -> bool:
	return has_ability() and str(ability.get("trigger", ABILITY_TRIGGER_AUTO)) == ABILITY_TRIGGER_MANUAL


func allows_unit_kind(unit_kind: String) -> bool:
	return allowed_unit_kinds.has(unit_kind)


func fits_slot(target_slot_kind: String, target_slot_size: String) -> bool:
	if slot_kind != target_slot_kind:
		return false
	return slot_size == _normalize_slot_size(target_slot_size)


func get_stat_int(stat_key: String, default_value: int = 0) -> int:
	return int(stats.get(stat_key, default_value))


func get_stat_float(stat_key: String, default_value: float = 0.0) -> float:
	return float(stats.get(stat_key, default_value))


func to_dict() -> Dictionary:
	return {
		"component_id": component_id,
		"display_name": display_name,
		"description": description,
		"slot_kind": slot_kind,
		"slot_size": slot_size,
		"unlock_tier": unlock_tier,
		"sort_key": sort_key,
		"allowed_unit_kinds": Array(allowed_unit_kinds),
		"requires_mobility": requires_mobility,
		"build_cost": build_cost.duplicate(true),
		"monthly_upkeep": monthly_upkeep.duplicate(true),
		"build_time_days_add": build_time_days_add,
		"stats": stats.duplicate(true),
		"weapon": weapon.duplicate(true),
		"ability": ability.duplicate(true),
	}


static func from_dict(component_id_value: String, data: Dictionary) -> ShipComponentDefinition:
	var definition := ShipComponentDefinition.new()
	definition.component_id = component_id_value.strip_edges()
	if definition.component_id.is_empty():
		return null

	definition.display_name = str(data.get("display_name", definition.component_id.replace("_", " ").capitalize())).strip_edges()
	definition.description = str(data.get("description", ""))
	definition.slot_kind = _normalize_slot_kind(str(data.get("slot_kind", SLOT_KIND_UTILITY)))
	if definition.slot_kind.is_empty():
		return null
	definition.slot_size = _normalize_slot_size(str(data.get("slot_size", SLOT_SIZE_MEDIUM)))
	definition.unlock_tier = maxi(int(data.get("unlock_tier", 0)), 0)
	definition.sort_key = int(data.get("sort_key", 0))
	definition.allowed_unit_kinds = _normalize_unit_kinds(data.get("allowed_unit_kinds", ["ship", "station"]))
	definition.requires_mobility = bool(data.get("requires_mobility", definition.slot_kind == SLOT_KIND_DRIVE))
	definition.build_cost = RESOURCE_AMOUNT_DEF_SCRIPT.to_dict_array(RESOURCE_AMOUNT_DEF_SCRIPT.normalize_array(data.get("build_cost", {})))
	definition.monthly_upkeep = RESOURCE_AMOUNT_DEF_SCRIPT.to_dict_array(RESOURCE_AMOUNT_DEF_SCRIPT.normalize_array(data.get("monthly_upkeep", {})))
	definition.build_time_days_add = maxi(int(data.get("build_time_days_add", 0)), 0)
	definition.stats = _normalize_stats(data.get("stats", {}))
	definition.weapon = _normalize_weapon(data.get("weapon", {}))
	definition.ability = _normalize_ability(data.get("ability", {}))
	return definition


static func _normalize_slot_kind(value: String) -> String:
	var normalized := value.strip_edges()
	if EQUIPMENT_SLOT_KINDS.has(normalized):
		return normalized
	return ""


static func _normalize_slot_size(value: String) -> String:
	var normalized := value.strip_edges()
	if SLOT_SIZES.has(normalized):
		return normalized
	return SLOT_SIZE_MEDIUM


static func _normalize_unit_kinds(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if value is not Array and value is not PackedStringArray:
		return PackedStringArray(["ship", "station"])
	for entry_variant in value:
		var entry := str(entry_variant).strip_edges()
		if entry.is_empty() or result.has(entry):
			continue
		result.append(entry)
	if result.is_empty():
		return PackedStringArray(["ship", "station"])
	return result


static func _normalize_stats(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var data: Dictionary = value
	var result: Dictionary = {}
	for key_variant in data.keys():
		var key := str(key_variant).strip_edges()
		if key.is_empty():
			continue
		if INT_STAT_KEYS.has(key):
			result[key] = int(data.get(key_variant, 0))
		elif FLOAT_STAT_KEYS.has(key):
			result[key] = float(data.get(key_variant, 0.0))
		else:
			result[key] = data.get(key_variant)
	return result


static func _normalize_weapon(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var data: Dictionary = value
	if data.is_empty():
		return {}
	return {
		"damage": maxi(int(data.get("damage", 0)), 0),
		"cooldown_days": maxi(int(data.get("cooldown_days", 1)), 1),
		"range": maxf(float(data.get("range", 1.0)), 0.0),
		"accuracy_bp": clampi(int(data.get("accuracy_bp", 10000)), 0, 10000),
		"shield_damage_bp": maxi(int(data.get("shield_damage_bp", 10000)), 0),
		"armor_penetration_bp": clampi(int(data.get("armor_penetration_bp", 0)), 0, 10000),
	}


static func _normalize_ability(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var data: Dictionary = value
	if data.is_empty():
		return {}
	var effect_id := str(data.get("effect_id", "")).strip_edges()
	if effect_id.is_empty():
		return {}
	var trigger := str(data.get("trigger", ABILITY_TRIGGER_AUTO)).strip_edges()
	if trigger != ABILITY_TRIGGER_MANUAL:
		trigger = ABILITY_TRIGGER_AUTO
	var params_variant: Variant = data.get("params", {})
	return {
		"trigger": trigger,
		"effect_id": effect_id,
		"cooldown_days": maxi(int(data.get("cooldown_days", 1)), 1),
		"radius": maxf(float(data.get("radius", 0.0)), 0.0),
		"params": params_variant.duplicate(true) if params_variant is Dictionary else {},
	}
