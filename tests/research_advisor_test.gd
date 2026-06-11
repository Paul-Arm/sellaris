extends SceneTree

## Validates the deterministic AI scoring helper for research drafts.

const ADVISOR_SCRIPT := preload("res://core/research/ResearchAdvisor.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Research advisor test passed.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _run(failures: Array[String]) -> void:
	var economy_option := {
		"tech_id": "economy_tech",
		"rarity": "common",
		"base_cost_milliunits": 100000,
		"effective_cost_milliunits": 100000,
		"discount_bp": 0,
		"momentum_levels": 0,
		"effects": [{"type": "monthly_resources", "resources": [{"resource_id": "energy", "milliunits": 3000}]}],
		"ai_hints": {"roles": {"economy": 1.2}},
	}
	var military_option := {
		"tech_id": "military_tech",
		"rarity": "common",
		"base_cost_milliunits": 100000,
		"effective_cost_milliunits": 100000,
		"discount_bp": 0,
		"momentum_levels": 0,
		"effects": [{"type": "unlock_component", "component_id": "test_component"}],
		"ai_hints": {"roles": {"military": 1.2}},
	}
	var options := [economy_option, military_option]
	var context := {"empire_id": "empire_advisor"}

	# Determinism: identical input produces identical ranking and scores.
	var first_run := ADVISOR_SCRIPT.rank_options(options, context, {})
	var second_run := ADVISOR_SCRIPT.rank_options(options, context, {})
	_expect(first_run.size() == 2 and second_run.size() == 2, "ranking should score every option", failures)
	for run_index in range(first_run.size()):
		_expect(
			int(first_run[run_index].get("score_milli", 0)) == int(second_run[run_index].get("score_milli", 1)),
			"ranking should be deterministic",
			failures
		)
		_expect(
			str(first_run[run_index].get("tech_id", "")) == str(second_run[run_index].get("tech_id", "?")),
			"ranking order should be deterministic",
			failures
		)

	# Persona steers the ranking: a militarist prefers the military tech.
	var militarist := {"roles": {"economy": 0.2, "military": 2.0}}
	var militarist_ranking := ADVISOR_SCRIPT.rank_options(options, context, militarist)
	_expect(str(militarist_ranking[0].get("tech_id", "")) == "military_tech", "militarist persona should rank military tech first", failures)

	var economist := {"roles": {"economy": 2.0, "military": 0.2}}
	var economist_ranking := ADVISOR_SCRIPT.rank_options(options, context, economist)
	_expect(str(economist_ranking[0].get("tech_id", "")) == "economy_tech", "economist persona should rank economy tech first", failures)

	# A bottleneck resource boosts techs whose monthly effects produce it.
	var balanced_score := ADVISOR_SCRIPT.score_option(economy_option, context, {})
	var bottleneck_context := {"empire_id": "empire_advisor", "bottleneck_resource_id": "energy"}
	var bottleneck_score := ADVISOR_SCRIPT.score_option(economy_option, bottleneck_context, {})
	_expect(
		int(bottleneck_score.get("score_milli", 0)) > int(balanced_score.get("score_milli", 0)),
		"bottleneck relief should raise the score",
		failures
	)

	# Discounts make options more attractive.
	var discounted_option: Dictionary = economy_option.duplicate(true)
	discounted_option["discount_bp"] = 2500
	discounted_option["effective_cost_milliunits"] = 75000
	var discounted_score := ADVISOR_SCRIPT.score_option(discounted_option, context, {})
	_expect(
		int(discounted_score.get("score_milli", 0)) > int(balanced_score.get("score_milli", 0)),
		"discounted option should score higher",
		failures
	)

	# Expensive techs score lower for cost-averse personas.
	var pricey_option: Dictionary = economy_option.duplicate(true)
	pricey_option["effective_cost_milliunits"] = 600000
	var pricey_score := ADVISOR_SCRIPT.score_option(pricey_option, context, {})
	_expect(
		int(pricey_score.get("score_milli", 0)) < int(balanced_score.get("score_milli", 0)),
		"higher cost should lower the score",
		failures
	)

	# Research slot effects are valued.
	var slot_option: Dictionary = economy_option.duplicate(true)
	slot_option["effects"] = [{"type": "research_slot", "domain": "frontier", "amount": 1}]
	var slot_score := ADVISOR_SCRIPT.score_option(slot_option, context, {})
	_expect(
		int(slot_score.get("score_milli", 0)) > int(balanced_score.get("score_milli", 0)),
		"research slot effects should raise the score",
		failures
	)

	# Reasons are reported for explainability.
	_expect(not (balanced_score.get("reasons", []) as Array).is_empty(), "score should include reasons", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
