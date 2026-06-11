extends RefCounted
class_name ResearchDomainDefinition

## A research discipline (deck of technologies). Domains are data-driven so
## mods can add their own disciplines alongside the core ones.

var domain_id: String = ""
var display_name: String = ""
var description: String = ""
var color: Color = Color(0.6, 0.7, 0.8, 1.0)
var sort_key: int = 0
var base_slots: int = 1
var draft_size: int = 3
## Completed techs in this domain required to unlock each tier (index = tier).
var tier_requirements: PackedInt32Array = PackedInt32Array([0, 3, 7, 12])
## Draft weight bonus per matching momentum level, in basis points.
var momentum_weight_bonus_bp: int = 1200
## Cost discount per matching momentum level, in basis points.
var momentum_discount_bp: int = 300
## Cap for the total momentum discount, in basis points.
var momentum_discount_cap_bp: int = 3000


func get_required_completions_for_tier(tier: int) -> int:
	if tier <= 0:
		return 0
	if tier < tier_requirements.size():
		return tier_requirements[tier]
	if tier_requirements.is_empty():
		return 0
	# Tiers beyond the configured list extend linearly from the last step.
	var last_index := tier_requirements.size() - 1
	var last_step := tier_requirements[last_index] - (tier_requirements[last_index - 1] if last_index > 0 else 0)
	return tier_requirements[last_index] + maxi(last_step, 1) * (tier - last_index)


func to_dict() -> Dictionary:
	return {
		"domain_id": domain_id,
		"display_name": display_name,
		"description": description,
		"color": color.to_html(),
		"sort_key": sort_key,
		"base_slots": base_slots,
		"draft_size": draft_size,
		"tier_requirements": Array(tier_requirements),
		"momentum_weight_bonus_bp": momentum_weight_bonus_bp,
		"momentum_discount_bp": momentum_discount_bp,
		"momentum_discount_cap_bp": momentum_discount_cap_bp,
	}


static func from_dict(domain_id_value: String, data: Dictionary) -> ResearchDomainDefinition:
	var definition := ResearchDomainDefinition.new()
	definition.domain_id = domain_id_value.strip_edges()
	if definition.domain_id.is_empty():
		return null

	definition.display_name = str(data.get("display_name", definition.domain_id.replace("_", " ").capitalize())).strip_edges()
	definition.description = str(data.get("description", ""))
	definition.color = _normalize_color(data.get("color", definition.color))
	definition.sort_key = int(data.get("sort_key", 0))
	definition.base_slots = maxi(int(data.get("base_slots", 1)), 1)
	definition.draft_size = maxi(int(data.get("draft_size", 3)), 1)
	definition.tier_requirements = _normalize_tier_requirements(data.get("tier_requirements", Array(definition.tier_requirements)))
	definition.momentum_weight_bonus_bp = maxi(int(data.get("momentum_weight_bonus_bp", 1200)), 0)
	definition.momentum_discount_bp = maxi(int(data.get("momentum_discount_bp", 300)), 0)
	definition.momentum_discount_cap_bp = maxi(int(data.get("momentum_discount_cap_bp", 3000)), 0)
	return definition


static func _normalize_color(value: Variant) -> Color:
	if value is Color:
		return value
	if value is String and Color.html_is_valid(value):
		return Color.html(value)
	return Color(0.6, 0.7, 0.8, 1.0)


static func _normalize_tier_requirements(values: Variant) -> PackedInt32Array:
	var result := PackedInt32Array()
	if values is not Array and values is not PackedInt32Array:
		return PackedInt32Array([0])
	var previous := 0
	for value_variant in values:
		var requirement := maxi(int(value_variant), previous)
		result.append(requirement)
		previous = requirement
	if result.is_empty() or result[0] != 0:
		var prefixed := PackedInt32Array([0])
		prefixed.append_array(result)
		result = prefixed
	return result
