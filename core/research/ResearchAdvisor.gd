extends RefCounted
class_name ResearchAdvisor

## Deterministic scoring helper for picking research options. Built for the
## upcoming AI empires but also usable for player suggestions and tests:
## given the draft options ResearchManager exposes, a persona (role weights),
## and a small context dictionary, it ranks the options reproducibly and
## explains each score.
##
## Personas are plain dictionaries so AI profiles can be data-driven later:
##   roles: {"economy": 1.0, "military": 1.0, "science": 1.0, "expansion": 1.0}
##   cost_aversion, discount_affinity, specialist_affinity, rare_affinity,
##   bottleneck_relief, slot_value
##
## Context (all optional): empire_id, bottleneck_resource_id.

const SCORE_PRECISION := 1000.0


static func build_default_persona() -> Dictionary:
	return {
		"roles": {
			"economy": 1.0,
			"military": 1.0,
			"science": 1.0,
			"expansion": 1.0,
		},
		"cost_aversion": 1.0,
		"discount_affinity": 1.0,
		"specialist_affinity": 0.5,
		"rare_affinity": 1.0,
		"bottleneck_relief": 2.0,
		"slot_value": 1.5,
	}


## Ranks draft options descending by score. Ties break on a stable hash of
## empire and tech id, so results are reproducible across runs and machines.
static func rank_options(options: Array, context: Dictionary = {}, persona: Dictionary = {}) -> Array[Dictionary]:
	var scored: Array[Dictionary] = []
	for option_variant in options:
		if option_variant is Dictionary:
			scored.append(score_option(option_variant, context, persona))
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("score_milli", 0)) != int(b.get("score_milli", 0)):
			return int(a.get("score_milli", 0)) > int(b.get("score_milli", 0))
		return int(a.get("tie_break", 0)) < int(b.get("tie_break", 0))
	)
	return scored


static func score_option(option: Dictionary, context: Dictionary = {}, persona: Dictionary = {}) -> Dictionary:
	var resolved_persona := _merge_persona(persona)
	var tech_id := str(option.get("tech_id", ""))
	var reasons: Array[String] = []
	var score := 0.0

	# Role alignment: ai_hints.roles dot persona.roles.
	var persona_roles: Dictionary = resolved_persona.get("roles", {})
	var ai_hints: Dictionary = option.get("ai_hints", {}) if option.get("ai_hints", {}) is Dictionary else {}
	var hint_roles: Dictionary = ai_hints.get("roles", {}) if ai_hints.get("roles", {}) is Dictionary else {}
	for role_variant in hint_roles.keys():
		var role := str(role_variant)
		var alignment := float(hint_roles.get(role_variant, 0.0)) * float(persona_roles.get(role, 0.0))
		if absf(alignment) > 0.0001:
			score += alignment * 10.0
			reasons.append("role %s %+.1f" % [role, alignment * 10.0])

	# Cost aversion: expensive projects bind the shared research stockpile.
	var effective_cost := float(option.get("effective_cost_milliunits", option.get("base_cost_milliunits", 0)))
	var cost_penalty := float(resolved_persona.get("cost_aversion", 1.0)) * effective_cost / 100000.0
	if cost_penalty > 0.0001:
		score -= cost_penalty
		reasons.append("cost %+.1f" % -cost_penalty)

	# Discounts make an option opportunistically attractive.
	var discount_bp := int(option.get("discount_bp", 0))
	if discount_bp > 0:
		var discount_bonus := float(resolved_persona.get("discount_affinity", 1.0)) * float(discount_bp) / 1000.0
		score += discount_bonus
		reasons.append("discount %+.1f" % discount_bonus)

	# Momentum synergy rewards specialists staying on a path.
	var momentum_levels := int(option.get("momentum_levels", 0))
	if momentum_levels > 0:
		var momentum_bonus := float(resolved_persona.get("specialist_affinity", 0.5)) * float(momentum_levels)
		score += momentum_bonus
		reasons.append("momentum %+.1f" % momentum_bonus)

	# Rare techs are usually strong picks.
	if str(option.get("rarity", "")) == ResearchTechDefinition.RARITY_RARE:
		var rare_bonus := float(resolved_persona.get("rare_affinity", 1.0)) * 3.0
		score += rare_bonus
		reasons.append("rare %+.1f" % rare_bonus)

	# Effects that relieve the current economic bottleneck score highly.
	var bottleneck_resource_id := str(context.get("bottleneck_resource_id", "")).strip_edges()
	for effect_variant in option.get("effects", []):
		if effect_variant is not Dictionary:
			continue
		var effect: Dictionary = effect_variant
		var effect_type := str(effect.get("type", ""))
		if effect_type == ResearchTechDefinition.EFFECT_RESEARCH_SLOT:
			var slot_bonus := float(resolved_persona.get("slot_value", 1.5)) * 4.0
			score += slot_bonus
			reasons.append("slot %+.1f" % slot_bonus)
		if not bottleneck_resource_id.is_empty() and effect_type == ResearchTechDefinition.EFFECT_MONTHLY_RESOURCES:
			if _effect_produces_resource(effect, bottleneck_resource_id):
				var relief_bonus := float(resolved_persona.get("bottleneck_relief", 2.0)) * 6.0
				score += relief_bonus
				reasons.append("bottleneck %s %+.1f" % [bottleneck_resource_id, relief_bonus])

	var score_milli := int(round(score * SCORE_PRECISION))
	return {
		"tech_id": tech_id,
		"score": score,
		"score_milli": score_milli,
		"reasons": reasons,
		"tie_break": ResearchCatalog.stable_hash("%s:%s:advisor" % [str(context.get("empire_id", "")), tech_id]),
	}


static func _merge_persona(persona: Dictionary) -> Dictionary:
	var merged := build_default_persona()
	for key_variant in persona.keys():
		var key := str(key_variant)
		if key == "roles" and persona.get(key_variant) is Dictionary:
			var merged_roles: Dictionary = merged.get("roles", {})
			for role_variant in (persona.get(key_variant) as Dictionary).keys():
				merged_roles[str(role_variant)] = float((persona.get(key_variant) as Dictionary).get(role_variant, 0.0))
			merged["roles"] = merged_roles
			continue
		merged[key] = persona.get(key_variant)
	return merged


static func _effect_produces_resource(effect: Dictionary, resource_id: String) -> bool:
	for amount_variant in effect.get("resources", []):
		if amount_variant is not Dictionary:
			continue
		var amount: Dictionary = amount_variant
		if str(amount.get("resource_id", "")) == resource_id and int(amount.get("milliunits", 0)) > 0:
			return true
	return false
