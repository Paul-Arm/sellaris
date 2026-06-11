extends Node

## End-to-end research loop against the live autoloads: bootstrap, drafts,
## project start, daily progress draining the research stockpile, completion
## effects (component unlock, monthly source), inspirations, auto-pick, and
## snapshot roundtrip.

const EMPIRE_ID := "empire_research"


func _ready() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Research manager smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()
	EconomyManager.bootstrap([EMPIRE_ID], {})
	SpaceManager.bootstrap_empires([EMPIRE_ID])
	ResearchManager.reload_catalog()
	ResearchManager.bootstrap([EMPIRE_ID], 4242)

	_expect(ResearchManager.is_bootstrapped(), "research manager should bootstrap", failures)
	_expect(EconomyManager.has_resource("research"), "research resource should be registered", failures)

	var overview: Array = ResearchManager.get_domains_overview(EMPIRE_ID)
	_expect(overview.size() == 3, "overview should list the three core domains", failures)
	for domain_overview_variant in overview:
		var domain_overview: Dictionary = domain_overview_variant
		_expect((domain_overview.get("options", []) as Array).size() == 3, "each domain should draft three tier-0 options", failures)
		_expect(int(domain_overview.get("slots", 0)) == 1, "each domain should start with one slot", failures)

	# The voidcraft tier-0 pool has exactly three techs, so the draft holds all of them.
	var voidcraft_options := _option_tech_ids("voidcraft")
	_expect(voidcraft_options.has("focused_optics"), "voidcraft draft should include focused_optics", failures)

	# Top up the starting stockpile so two parallel projects can finish.
	EconomyManager.grant_resources(EMPIRE_ID, [{"resource_id": "research", "milliunits": 120000}])
	var starting_stockpile := EconomyManager.get_amount(EMPIRE_ID, "research")
	_expect(starting_stockpile == 210000, "stockpile should hold starting amount plus grant (got %d)" % starting_stockpile, failures)

	_expect(ResearchManager.start_project(EMPIRE_ID, "voidcraft", "focused_optics"), "starting a drafted project should work", failures)
	_expect(not ResearchManager.can_start_project(EMPIRE_ID, "voidcraft"), "occupied slot should block a second project", failures)
	_expect(not ResearchManager.start_project(EMPIRE_ID, "voidcraft", "harmonic_shields"), "second project in the same domain should be rejected", failures)
	_expect(ResearchManager.get_draft_serial(EMPIRE_ID, "voidcraft") == 2, "picking should advance the draft serial", failures)

	_expect(_option_tech_ids("frontier").has("survey_protocols"), "frontier draft should include survey_protocols", failures)
	_expect(ResearchManager.start_project(EMPIRE_ID, "frontier", "survey_protocols"), "second domain should research in parallel", failures)

	# survey_protocols: 60 units / 20 min days; focused_optics: 100 units / 30 min days.
	for _day in range(19):
		ResearchManager._on_day_tick({})
	_expect(not ResearchManager.is_tech_completed(EMPIRE_ID, "survey_protocols"), "project should respect its minimum duration", failures)
	ResearchManager._on_day_tick({})
	_expect(ResearchManager.is_tech_completed(EMPIRE_ID, "survey_protocols"), "project should complete after min_days with full funding", failures)
	_expect(EconomyManager.has_source("research_tech:survey_protocols:lvl1:%s" % EMPIRE_ID), "monthly effect should register an economy source", failures)
	_expect(EconomyManager.get_projected_monthly_net(EMPIRE_ID, "research") == 2000, "monthly source should project research income", failures)

	for _day in range(10):
		ResearchManager._on_day_tick({})
	_expect(ResearchManager.is_tech_completed(EMPIRE_ID, "focused_optics"), "voidcraft project should complete after 30 days", failures)
	_expect(SpaceManager.is_ship_component_unlocked(EMPIRE_ID, "pulse_laser_mk2"), "completion should unlock the ship component", failures)

	var stockpile_after := EconomyManager.get_amount(EMPIRE_ID, "research")
	_expect(stockpile_after == 50000, "projects should drain exactly their cost (got %d)" % stockpile_after, failures)

	var momentum: Dictionary = ResearchManager.get_momentum_map(EMPIRE_ID)
	_expect(int(momentum.get("weapons", 0)) == 1, "completion should add momentum on tech tags", failures)
	_expect(int(momentum.get("science", 0)) == 1, "completion should add momentum for every tag", failures)

	var refreshed_voidcraft := _option_tech_ids("voidcraft")
	_expect(ResearchManager.get_draft_serial(EMPIRE_ID, "voidcraft") == 3, "completion should refresh the domain draft", failures)
	_expect(not refreshed_voidcraft.has("focused_optics"), "completed tech should leave the draft", failures)

	# Inspirations: matching options get discounted; starting consumes the token.
	var inspiration: Dictionary = ResearchManager.add_inspiration(EMPIRE_ID, ["industry"], 2500, 5000, "test", 0)
	_expect(not inspiration.is_empty(), "inspiration should be added", failures)
	_expect(ResearchManager.get_inspirations(EMPIRE_ID).size() == 1, "inspiration should be listed", failures)
	var industry_options: Array = ResearchManager.get_draft_options(EMPIRE_ID, "industry")
	_expect(not industry_options.is_empty(), "industry draft should offer options", failures)
	if not industry_options.is_empty():
		var picked_option: Dictionary = industry_options[0]
		_expect(bool(picked_option.get("inspired", false)), "matching options should be marked inspired", failures)
		var expected_cost := int(picked_option.get("base_cost_milliunits", 0)) * (10000 - 2500) / 10000
		_expect(int(picked_option.get("effective_cost_milliunits", 0)) == expected_cost, "inspiration discount should apply to the quote", failures)
		_expect(ResearchManager.start_project(EMPIRE_ID, "industry", str(picked_option.get("tech_id", ""))), "inspired project should start", failures)
		_expect(ResearchManager.get_inspirations(EMPIRE_ID).is_empty(), "starting should consume the inspiration", failures)
		var active_industry: Array = ResearchManager.get_active_projects(EMPIRE_ID, "industry")
		_expect(active_industry.size() == 1 and int((active_industry[0] as Dictionary).get("total_cost_milliunits", 0)) == int(picked_option.get("effective_cost_milliunits", 0)), "project should lock in the discounted cost", failures)

	# Forced completion applies effects (used by debug tools and events).
	_expect(ResearchManager.force_complete_tech(EMPIRE_ID, "advanced_laboratories"), "force_complete_tech should work", failures)
	_expect(ResearchManager.is_building_unlocked(EMPIRE_ID, "advanced_lab"), "unlock_building effect should unlock the building", failures)

	# Advisor-driven auto pick fills the free voidcraft slot deterministically.
	var picked_tech := ResearchManager.auto_pick_project(EMPIRE_ID, "voidcraft")
	_expect(not picked_tech.is_empty(), "auto_pick_project should pick an option", failures)
	_expect(ResearchManager.get_active_projects(EMPIRE_ID, "voidcraft").size() == 1, "auto pick should start the project", failures)
	var repeat_pick := ResearchManager.auto_pick_project(EMPIRE_ID, "voidcraft")
	_expect(repeat_pick.is_empty(), "auto pick should respect occupied slots", failures)

	# Snapshot roundtrip.
	var snapshot: Dictionary = ResearchManager.build_snapshot()
	ResearchManager.load_snapshot(snapshot)
	_expect(ResearchManager.is_bootstrapped(), "snapshot restore should keep the manager bootstrapped", failures)
	_expect(ResearchManager.is_tech_completed(EMPIRE_ID, "focused_optics"), "completions should survive snapshots", failures)
	_expect(ResearchManager.get_draft_serial(EMPIRE_ID, "voidcraft") == 4, "draft serials should survive snapshots", failures)
	_expect(ResearchManager.get_active_projects(EMPIRE_ID, "voidcraft").size() == 1, "active projects should survive snapshots", failures)
	_expect(ResearchManager.is_building_unlocked(EMPIRE_ID, "advanced_lab"), "building unlocks should survive snapshots", failures)


func _option_tech_ids(domain_id: String) -> Array[String]:
	var result: Array[String] = []
	for option_variant in ResearchManager.get_draft_options(EMPIRE_ID, domain_id):
		if option_variant is Dictionary:
			result.append(str((option_variant as Dictionary).get("tech_id", "")))
	return result


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
