extends SceneTree

## Validates research definitions loading, mod registration, eligibility
## gating, deterministic drafts, cost quotes, and state snapshots.

const CATALOG_SCRIPT := preload("res://core/research/ResearchCatalog.gd")
const STATE_SCRIPT := preload("res://core/research/ResearchEmpireState.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Research catalog test passed.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _run(failures: Array[String]) -> void:
	var catalog := CATALOG_SCRIPT.new() as ResearchCatalog
	catalog.load_definitions()

	_test_loading(catalog, failures)
	_test_runtime_registration(failures)
	_test_eligibility(catalog, failures)
	_test_exclusive_groups(catalog, failures)
	_test_drafts(catalog, failures)
	_test_cost_quotes(catalog, failures)
	_test_state_snapshot(failures)


func _test_loading(catalog: ResearchCatalog, failures: Array[String]) -> void:
	var domain_ids := catalog.get_domain_ids()
	_expect(domain_ids.has("industry"), "industry domain should load", failures)
	_expect(domain_ids.has("voidcraft"), "voidcraft domain should load", failures)
	_expect(domain_ids.has("frontier"), "frontier domain should load", failures)
	_expect(catalog.size() >= 20, "core tech set should contain at least 20 techs (found %d)" % catalog.size(), failures)

	var tech := catalog.get_tech("efficient_extraction")
	_expect(tech != null, "efficient_extraction should exist", failures)
	if tech != null:
		_expect(tech.cost_milliunits == 70000, "cost should convert decimal units to milliunits", failures)
		_expect(tech.domain_id == "industry", "tech should resolve its domain", failures)
		_expect(tech.tags.has("matter"), "tags should parse", failures)
		_expect(tech.effects.size() == 1, "effects should parse", failures)
		if tech.effects.size() == 1:
			var resources: Array = tech.effects[0].get("resources", [])
			_expect(resources.size() == 1, "effect resources should normalize", failures)
			if resources.size() == 1:
				_expect(int((resources[0] as Dictionary).get("milliunits", 0)) == 3000, "effect resources should convert to milliunits", failures)

	var repeatable := catalog.get_tech("applied_innovation")
	_expect(repeatable != null and repeatable.is_repeatable(), "applied_innovation should be repeatable", failures)
	if repeatable != null:
		_expect(repeatable.get_cost_for_level(1) == 180000, "repeatable level 1 cost should match base", failures)
		_expect(repeatable.get_cost_for_level(2) == 234000, "repeatable level 2 cost should grow by repeat_cost_growth_bp", failures)


func _test_runtime_registration(failures: Array[String]) -> void:
	var catalog := CATALOG_SCRIPT.new() as ResearchCatalog
	catalog.load_definitions()
	var version_before := catalog.get_catalog_version()

	_expect(not catalog.register_tech_dict("mod_orphan", {"domain": "unknown_domain", "cost": 10.0}), "tech with unknown domain should be rejected", failures)
	_expect(catalog.register_domain_dict("mod_domain", {"display_name": "Mod Domain", "sort_key": 99}), "runtime domain registration should work", failures)
	_expect(catalog.register_tech_dict("mod_tech", {
		"domain": "mod_domain",
		"cost": 42.0,
		"tags": ["modded"],
		"effects": [{"type": "grant_resources", "resources": {"energy": 5.0}}],
	}), "runtime tech registration should work", failures)
	_expect(catalog.has_tech("mod_tech"), "registered tech should be queryable", failures)
	_expect(catalog.get_tech_ids_for_domain("mod_domain").has("mod_tech"), "registered tech should index by domain", failures)
	_expect(catalog.get_catalog_version() > version_before, "registration should bump catalog version", failures)

	# Overriding an existing tech id replaces the definition (mod override).
	_expect(catalog.register_tech_dict("mod_tech", {"domain": "mod_domain", "cost": 99.0}), "tech override should be accepted", failures)
	_expect(catalog.get_tech("mod_tech").cost_milliunits == 99000, "tech override should replace the definition", failures)


func _test_eligibility(catalog: ResearchCatalog, failures: Array[String]) -> void:
	var state := STATE_SCRIPT.new() as ResearchEmpireState
	state.empire_id = "empire_test"

	_expect(catalog.is_tech_eligible("efficient_extraction", state), "tier 0 tech should be eligible from the start", failures)
	_expect(not catalog.is_tech_eligible("orbital_extraction_rigs", state), "tier 1 tech should be locked initially", failures)

	state.record_completion("efficient_extraction", 1, 0)
	state.record_completion("grid_balancing", 1, 0)
	_expect(catalog.get_unlocked_tier("industry", state) == 1, "two completions should unlock tier 1", failures)
	_expect(catalog.is_tech_eligible("orbital_extraction_rigs", state), "requires + tier satisfied should make tech eligible", failures)
	_expect(not catalog.is_tech_eligible("efficient_extraction", state), "completed non-repeatable tech should not be eligible", failures)

	state.add_active_project("industry", {"tech_id": "alloy_recycling"})
	_expect(not catalog.is_tech_eligible("alloy_recycling", state), "active tech should not be eligible", failures)
	_expect(not catalog.draw_draft_option_ids("industry", state, "seed").has("alloy_recycling"), "draft should exclude active techs", failures)


func _test_exclusive_groups(catalog: ResearchCatalog, failures: Array[String]) -> void:
	var state := STATE_SCRIPT.new() as ResearchEmpireState
	state.empire_id = "empire_test"
	for tech_id in ["efficient_extraction", "grid_balancing", "alloy_recycling", "hydroponic_vats", "automated_foundries"]:
		state.record_completion(tech_id, 1, 0)
	_expect(catalog.get_unlocked_tier("industry", state) == 2, "five completions should unlock tier 2", failures)
	_expect(catalog.is_tech_eligible("matter_synthesis", state), "tier 2 exclusive tech should be eligible", failures)

	state.record_completion("matter_synthesis", 1, 0)
	_expect(not catalog.is_tech_eligible("energy_synthesis", state), "completing one tech of an exclusive group should lock the other", failures)


func _test_drafts(catalog: ResearchCatalog, failures: Array[String]) -> void:
	var state := STATE_SCRIPT.new() as ResearchEmpireState
	state.empire_id = "empire_test"

	var draft_a := catalog.draw_draft_option_ids("industry", state, "1:empire_test:industry:1:draft")
	var draft_b := catalog.draw_draft_option_ids("industry", state, "1:empire_test:industry:1:draft")
	_expect(draft_a == draft_b, "same seed key should produce identical drafts", failures)
	_expect(draft_a.size() == 3, "draft should fill draft_size options (got %d)" % draft_a.size(), failures)

	var seen: Dictionary = {}
	for tech_id in draft_a:
		_expect(not seen.has(tech_id), "draft should not repeat options", failures)
		seen[tech_id] = true
		_expect(catalog.is_tech_eligible(tech_id, state), "draft options should be eligible", failures)

	# Momentum raises effective draft weight for matching tags.
	var domain := catalog.get_domain("voidcraft")
	var base_weight := catalog.get_effective_weight("focused_optics", state, domain)
	state.add_momentum_for_tags(PackedStringArray(["weapons"]))
	var boosted_weight := catalog.get_effective_weight("focused_optics", state, domain)
	_expect(boosted_weight > base_weight, "momentum should raise effective weight", failures)


func _test_cost_quotes(catalog: ResearchCatalog, failures: Array[String]) -> void:
	var state := STATE_SCRIPT.new() as ResearchEmpireState
	state.empire_id = "empire_test"

	var base_quote := catalog.compute_cost_quote("focused_optics", state)
	_expect(int(base_quote.get("effective_cost_milliunits", 0)) == 100000, "undiscounted quote should match base cost", failures)
	_expect(int(base_quote.get("discount_bp", -1)) == 0, "fresh empire should have no discount", failures)

	state.add_momentum_for_tags(PackedStringArray(["weapons", "voidcraft"]))
	var momentum_quote := catalog.compute_cost_quote("focused_optics", state)
	_expect(int(momentum_quote.get("momentum_levels", 0)) == 2, "momentum levels should sum matching tags", failures)
	_expect(int(momentum_quote.get("discount_bp", 0)) == 600, "momentum discount should apply per level", failures)

	state.add_inspiration(PackedStringArray(["weapons"]), 2000, 5000, "test", 0, 0)
	var inspired_quote := catalog.compute_cost_quote("focused_optics", state)
	_expect(int(inspired_quote.get("inspiration_discount_bp", 0)) == 2000, "matching inspiration should add its discount", failures)
	_expect(int(inspired_quote.get("discount_bp", 0)) == 2600, "discounts should stack", failures)
	_expect(int(inspired_quote.get("effective_cost_milliunits", 0)) == 74000, "effective cost should apply total discount", failures)
	_expect(not str(inspired_quote.get("inspiration_id", "")).is_empty(), "quote should expose the inspiration to consume", failures)


func _test_state_snapshot(failures: Array[String]) -> void:
	var state := STATE_SCRIPT.new() as ResearchEmpireState
	state.empire_id = "empire_snap"
	state.record_completion("efficient_extraction", 1, 12)
	state.add_momentum_for_tags(PackedStringArray(["industry", "matter"]))
	state.add_active_project("industry", {
		"tech_id": "grid_balancing",
		"level": 1,
		"total_cost_milliunits": 70000,
		"invested_milliunits": 1500,
		"daily_cap_milliunits": 2800,
		"started_day_serial": 14,
		"discount_bp": 0,
		"inspiration_id": "",
	})
	state.set_draft("industry", 3, ["alloy_recycling", "hydroponic_vats"] as Array[String])
	state.add_inspiration(PackedStringArray(["weapons"]), 1500, 2500, "anomaly:test", 10, 100)
	state.add_extra_slots("frontier", 1)
	state.add_modifier_bp("weapon_damage_bp", 1000)
	state.unlock_building("advanced_lab")

	var restored := STATE_SCRIPT.from_dict(state.to_dict()) as ResearchEmpireState
	_expect(restored != null, "state should restore from snapshot", failures)
	if restored == null:
		return
	_expect(restored.get_completed_level("efficient_extraction") == 1, "completion should survive snapshot", failures)
	_expect(restored.get_momentum("industry") == 1, "momentum should survive snapshot", failures)
	_expect(restored.get_active_projects("industry").size() == 1, "active projects should survive snapshot", failures)
	_expect(int(restored.get_active_projects("industry")[0].get("invested_milliunits", 0)) == 1500, "project progress should survive snapshot", failures)
	_expect(int(restored.get_draft("industry").get("serial", 0)) == 3, "draft serial should survive snapshot", failures)
	_expect(restored.get_matching_inspirations(PackedStringArray(["weapons"])).size() == 1, "inspirations should survive snapshot", failures)
	_expect(restored.get_extra_slots("frontier") == 1, "extra slots should survive snapshot", failures)
	_expect(restored.get_modifier_bp("weapon_damage_bp") == 1000, "modifiers should survive snapshot", failures)
	_expect(restored.is_building_unlocked("advanced_lab"), "building unlocks should survive snapshot", failures)
	_expect(restored.next_inspiration_serial == state.next_inspiration_serial, "inspiration serial should survive snapshot", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
