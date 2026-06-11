extends RefCounted
class_name ResearchTechDefinition

## One researchable technology. Definitions are data-driven (cfg sections or
## runtime dictionaries) so mods can add techs without touching code.

const RESOURCE_AMOUNT_DEF_SCRIPT := preload("res://core/economy/ResourceAmountDef.gd")

const RARITY_COMMON := "common"
const RARITY_RARE := "rare"
const RARITIES: Array[String] = [RARITY_COMMON, RARITY_RARE]

const EFFECT_UNLOCK_COMPONENT := "unlock_component"
const EFFECT_UNLOCK_BUILDING := "unlock_building"
const EFFECT_GRANT_RESOURCES := "grant_resources"
const EFFECT_MONTHLY_RESOURCES := "monthly_resources"
const EFFECT_MODIFIER := "modifier"
const EFFECT_RESEARCH_SLOT := "research_slot"
const EFFECT_CUSTOM := "custom"
const EFFECT_TYPES: Array[String] = [
	EFFECT_UNLOCK_COMPONENT,
	EFFECT_UNLOCK_BUILDING,
	EFFECT_GRANT_RESOURCES,
	EFFECT_MONTHLY_RESOURCES,
	EFFECT_MODIFIER,
	EFFECT_RESEARCH_SLOT,
	EFFECT_CUSTOM,
]

var tech_id: String = ""
var display_name: String = ""
var description: String = ""
var domain_id: String = ""
var tier: int = 0
var cost_milliunits: int = 0
var min_days: int = 1
var weight: int = 1000
var sort_key: int = 0
var tags: PackedStringArray = PackedStringArray()
var rarity: String = RARITY_COMMON
var requires: PackedStringArray = PackedStringArray()
var exclusive_group: String = ""
var max_level: int = 1
var repeat_cost_growth_bp: int = 2500
var effects: Array[Dictionary] = []
var ai_hints: Dictionary = {}
var source: String = ""


func is_repeatable() -> bool:
	return max_level != 1


func has_tag(tag: String) -> bool:
	return tags.has(tag.strip_edges())


## Effective cost for researching the given level (1 = first completion).
## Repeatable techs grow by repeat_cost_growth_bp per completed level.
func get_cost_for_level(level: int) -> int:
	var normalized_level := maxi(level, 1)
	var cost := cost_milliunits
	for _step in range(normalized_level - 1):
		cost += int(cost * repeat_cost_growth_bp / 10000.0)
	return maxi(cost, 1)


func to_dict() -> Dictionary:
	return {
		"tech_id": tech_id,
		"display_name": display_name,
		"description": description,
		"domain_id": domain_id,
		"tier": tier,
		"cost_milliunits": cost_milliunits,
		"min_days": min_days,
		"weight": weight,
		"sort_key": sort_key,
		"tags": Array(tags),
		"rarity": rarity,
		"requires": Array(requires),
		"exclusive_group": exclusive_group,
		"max_level": max_level,
		"repeat_cost_growth_bp": repeat_cost_growth_bp,
		"effects": effects.duplicate(true),
		"ai_hints": ai_hints.duplicate(true),
		"source": source,
	}


static func from_dict(tech_id_value: String, data: Dictionary, source_value: String = "") -> ResearchTechDefinition:
	var definition := ResearchTechDefinition.new()
	definition.tech_id = tech_id_value.strip_edges()
	if definition.tech_id.is_empty():
		return null

	definition.domain_id = str(data.get("domain", data.get("domain_id", ""))).strip_edges()
	if definition.domain_id.is_empty():
		return null

	definition.display_name = str(data.get("display_name", definition.tech_id.replace("_", " ").capitalize())).strip_edges()
	definition.description = str(data.get("description", ""))
	definition.tier = maxi(int(data.get("tier", 0)), 0)
	definition.cost_milliunits = _resolve_cost_milliunits(data)
	if definition.cost_milliunits <= 0:
		return null
	definition.min_days = maxi(int(data.get("min_days", 30)), 1)
	definition.weight = maxi(int(data.get("weight", 1000)), 0)
	definition.sort_key = int(data.get("sort_key", 0))
	definition.tags = _normalize_string_list(data.get("tags", []))
	definition.rarity = _normalize_rarity(str(data.get("rarity", RARITY_COMMON)))
	definition.requires = _normalize_string_list(data.get("requires", []))
	definition.exclusive_group = str(data.get("exclusive_group", "")).strip_edges()
	definition.max_level = maxi(int(data.get("max_level", 0 if bool(data.get("repeatable", false)) else 1)), 0)
	definition.repeat_cost_growth_bp = maxi(int(data.get("repeat_cost_growth_bp", 2500)), 0)
	definition.effects = _normalize_effects(data.get("effects", []))
	var ai_hints_variant: Variant = data.get("ai_hints", {})
	definition.ai_hints = ai_hints_variant.duplicate(true) if ai_hints_variant is Dictionary else {}
	definition.source = source_value.strip_edges()
	return definition


static func _resolve_cost_milliunits(data: Dictionary) -> int:
	if data.has("cost_milliunits"):
		return maxi(int(data.get("cost_milliunits", 0)), 0)
	return maxi(int(round(float(data.get("cost", 0.0)) * 1000.0)), 0)


static func _normalize_rarity(value: String) -> String:
	var normalized := value.strip_edges()
	if RARITIES.has(normalized):
		return normalized
	return RARITY_COMMON


static func _normalize_string_list(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if values is String:
		values = [values]
	if values is not Array and values is not PackedStringArray:
		return result
	for value_variant in values:
		var value := str(value_variant).strip_edges()
		if value.is_empty() or result.has(value):
			continue
		result.append(value)
	return result


static func _normalize_effects(values: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if values is not Array:
		return result
	for effect_variant in values:
		if effect_variant is not Dictionary:
			continue
		var effect := _normalize_effect(effect_variant)
		if not effect.is_empty():
			result.append(effect)
	return result


static func _normalize_effect(value: Dictionary) -> Dictionary:
	var effect_type := str(value.get("type", "")).strip_edges()
	if not EFFECT_TYPES.has(effect_type):
		return {}
	var result: Dictionary = value.duplicate(true)
	result["type"] = effect_type
	match effect_type:
		EFFECT_UNLOCK_COMPONENT:
			if str(result.get("component_id", "")).strip_edges().is_empty():
				return {}
		EFFECT_UNLOCK_BUILDING:
			if str(result.get("building_id", "")).strip_edges().is_empty():
				return {}
		EFFECT_GRANT_RESOURCES, EFFECT_MONTHLY_RESOURCES:
			var amounts: Array[Dictionary] = RESOURCE_AMOUNT_DEF_SCRIPT.to_dict_array(
				RESOURCE_AMOUNT_DEF_SCRIPT.normalize_array(result.get("resources", {}))
			)
			if amounts.is_empty():
				return {}
			result["resources"] = amounts
		EFFECT_MODIFIER:
			if str(result.get("key", "")).strip_edges().is_empty():
				return {}
			result["value_bp"] = int(result.get("value_bp", 0))
		EFFECT_RESEARCH_SLOT:
			result["domain"] = str(result.get("domain", "")).strip_edges()
			result["amount"] = maxi(int(result.get("amount", 1)), 1)
		EFFECT_CUSTOM:
			if str(result.get("effect_id", "")).strip_edges().is_empty():
				return {}
	return result
