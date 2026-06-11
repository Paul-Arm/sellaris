extends Node

## Empire research: deterministic draft-based technology selection.
##
## Each domain (discipline) offers a deterministic weighted draft of options.
## Picking one starts a project that drains the shared "research" resource
## stockpile day by day (capped at cost/min_days, so banking research helps
## but cannot rush below the minimum duration). Completing techs builds
## momentum on their tags, which boosts draft weights and discounts related
## techs - empires drift into specializations. External events (anomalies)
## add inspirations: one-shot discounts and draft boosts for matching tags.
##
## Definitions are data-driven (core/research/domains.cfg and every *.cfg in
## core/research/techs/) and can be extended at runtime through
## register_tech_dict / register_domain_dict for mod support.

const RESEARCH_CATALOG_SCRIPT := preload("res://core/research/ResearchCatalog.gd")
const RESEARCH_EMPIRE_STATE_SCRIPT := preload("res://core/research/ResearchEmpireState.gd")
const RESEARCH_ADVISOR_SCRIPT := preload("res://core/research/ResearchAdvisor.gd")

const RESEARCH_RESOURCE_ID := "research"

signal research_bootstrapped(empire_ids: PackedStringArray)
signal draft_refreshed(empire_id: String, domain_id: String, serial: int)
signal project_started(empire_id: String, domain_id: String, tech_id: String, level: int)
signal project_progressed(empire_id: String, domain_id: String, tech_id: String, invested_milliunits: int, total_milliunits: int)
signal tech_completed(empire_id: String, tech_id: String, level: int, summary: String)
signal inspiration_added(empire_id: String, inspiration: Dictionary)
signal tech_effect_applied(empire_id: String, tech_id: String, effect: Dictionary)
## Emitted for effects of type "custom"; game systems and mods react to these.
signal tech_effect_requested(empire_id: String, tech_id: String, effect: Dictionary)
signal research_state_changed(empire_id: String)

var _catalog: ResearchCatalog = RESEARCH_CATALOG_SCRIPT.new()
var _catalog_loaded: bool = false
var _states_by_empire: Dictionary = {}
var _empire_ids: PackedStringArray = PackedStringArray()
var _bootstrapped: bool = false
var _galaxy_seed: int = 0


func _ready() -> void:
	ensure_catalog_loaded()
	if SimClock != null and not SimClock.day_tick.is_connected(_on_day_tick):
		SimClock.day_tick.connect(_on_day_tick)


func ensure_catalog_loaded() -> void:
	if _catalog_loaded:
		return
	_catalog.load_definitions()
	_catalog_loaded = true


func get_catalog() -> ResearchCatalog:
	ensure_catalog_loaded()
	return _catalog


func reload_catalog() -> void:
	_catalog.load_definitions()
	_catalog_loaded = true


# --- Mod support ---

func register_tech_dict(tech_id: String, data: Dictionary, source: String = "runtime") -> bool:
	ensure_catalog_loaded()
	return _catalog.register_tech_dict(tech_id, data, source)


func register_domain_dict(domain_id: String, data: Dictionary) -> bool:
	ensure_catalog_loaded()
	return _catalog.register_domain_dict(domain_id, data)


# --- Lifecycle ---

func bootstrap(empire_ids_variant: Variant, galaxy_seed: int = 0) -> void:
	ensure_catalog_loaded()
	clear_runtime_state()
	_galaxy_seed = galaxy_seed

	for empire_id_variant in empire_ids_variant:
		var empire_id := str(empire_id_variant).strip_edges()
		if empire_id.is_empty() or _states_by_empire.has(empire_id):
			continue
		var state := RESEARCH_EMPIRE_STATE_SCRIPT.new() as ResearchEmpireState
		state.empire_id = empire_id
		_states_by_empire[empire_id] = state
		_empire_ids.append(empire_id)

	_bootstrapped = true
	for empire_id in _empire_ids:
		for domain_id in _catalog.get_domain_ids():
			_refresh_draft(empire_id, domain_id, 1)
	research_bootstrapped.emit(_empire_ids.duplicate())


func clear_runtime_state() -> void:
	_bootstrapped = false
	_galaxy_seed = 0
	_states_by_empire.clear()
	_empire_ids = PackedStringArray()


func is_bootstrapped() -> bool:
	return _bootstrapped


func get_empire_ids() -> PackedStringArray:
	return _empire_ids.duplicate()


func has_empire(empire_id: String) -> bool:
	return _states_by_empire.has(empire_id)


# --- Queries ---

func get_domain_ids() -> Array[String]:
	ensure_catalog_loaded()
	return _catalog.get_domain_ids()


func get_completed_levels(empire_id: String) -> Dictionary:
	var state := _get_state(empire_id)
	if state == null:
		return {}
	return state.completed_levels.duplicate(true)


func get_completed_level(empire_id: String, tech_id: String) -> int:
	var state := _get_state(empire_id)
	if state == null:
		return 0
	return state.get_completed_level(tech_id)


func is_tech_completed(empire_id: String, tech_id: String) -> bool:
	return get_completed_level(empire_id, tech_id) > 0


func get_momentum_map(empire_id: String) -> Dictionary:
	var state := _get_state(empire_id)
	if state == null:
		return {}
	return state.momentum_by_tag.duplicate(true)


func get_modifier_bp(empire_id: String, key: String, default_bp: int = 0) -> int:
	var state := _get_state(empire_id)
	if state == null:
		return default_bp
	return state.get_modifier_bp(key, default_bp)


func is_building_unlocked(empire_id: String, building_id: String) -> bool:
	var state := _get_state(empire_id)
	if state == null:
		return false
	return state.is_building_unlocked(building_id)


func get_unlocked_building_ids(empire_id: String) -> Array[String]:
	var state := _get_state(empire_id)
	if state == null:
		return []
	return state.get_unlocked_building_ids()


func get_slot_count(empire_id: String, domain_id: String) -> int:
	var state := _get_state(empire_id)
	var domain := _catalog.get_domain(domain_id)
	if state == null or domain == null:
		return 0
	return domain.base_slots + state.get_extra_slots(domain_id)


func get_active_projects(empire_id: String, domain_id: String) -> Array[Dictionary]:
	var state := _get_state(empire_id)
	if state == null:
		return []
	var result: Array[Dictionary] = []
	for project in state.get_active_projects(domain_id):
		result.append(project.duplicate(true))
	return result


## Draft options decorated with cost quote, weights, and inspiration markers.
## This is the dictionary shape ResearchAdvisor scores.
func get_draft_options(empire_id: String, domain_id: String) -> Array[Dictionary]:
	var state := _get_state(empire_id)
	var domain := _catalog.get_domain(domain_id)
	if state == null or domain == null:
		return []
	var draft := state.get_draft(domain_id)
	var result: Array[Dictionary] = []
	for option_id_variant in draft.get("option_ids", []):
		var tech_id := str(option_id_variant)
		if not _catalog.is_tech_eligible(tech_id, state):
			continue
		result.append(_build_option_entry(tech_id, state, domain))
	return result


func get_draft_serial(empire_id: String, domain_id: String) -> int:
	var state := _get_state(empire_id)
	if state == null:
		return 0
	return int(state.get_draft(domain_id).get("serial", 0))


## Full per-empire overview used by the research UI.
func get_domains_overview(empire_id: String) -> Array[Dictionary]:
	var state := _get_state(empire_id)
	if state == null:
		return []
	var result: Array[Dictionary] = []
	for domain_id in _catalog.get_domain_ids():
		var domain := _catalog.get_domain(domain_id)
		if domain == null:
			continue
		var projects: Array[Dictionary] = []
		for project in state.get_active_projects(domain_id):
			var decorated: Dictionary = project.duplicate(true)
			var definition := _catalog.get_tech(str(project.get("tech_id", "")))
			decorated["display_name"] = definition.display_name if definition != null else str(project.get("tech_id", ""))
			decorated["tags"] = Array(definition.tags) if definition != null else []
			projects.append(decorated)
		result.append({
			"domain_id": domain_id,
			"display_name": domain.display_name,
			"description": domain.description,
			"color": domain.color,
			"slots": get_slot_count(empire_id, domain_id),
			"active_projects": projects,
			"draft_serial": get_draft_serial(empire_id, domain_id),
			"options": get_draft_options(empire_id, domain_id),
			"unlocked_tier": _catalog.get_unlocked_tier(domain_id, state),
			"completed_count": _catalog.count_completed_in_domain(domain_id, state),
			"next_tier_requirement": domain.get_required_completions_for_tier(_catalog.get_unlocked_tier(domain_id, state) + 1),
		})
	return result


func get_inspirations(empire_id: String) -> Array[Dictionary]:
	var state := _get_state(empire_id)
	if state == null:
		return []
	var result: Array[Dictionary] = []
	for inspiration in state.inspirations:
		if str(inspiration.get("consumed_by", "")).is_empty():
			result.append(inspiration.duplicate(true))
	return result


func get_completed_log(empire_id: String) -> Array[Dictionary]:
	var state := _get_state(empire_id)
	if state == null:
		return []
	return state.completed_log.duplicate(true)


# --- Picking & projects ---

func can_start_project(empire_id: String, domain_id: String) -> bool:
	var state := _get_state(empire_id)
	if state == null:
		return false
	return state.get_active_projects(domain_id).size() < get_slot_count(empire_id, domain_id)


func start_project(empire_id: String, domain_id: String, tech_id: String) -> bool:
	var state := _get_state(empire_id)
	var domain := _catalog.get_domain(domain_id)
	if state == null or domain == null:
		return false
	if not can_start_project(empire_id, domain_id):
		return false

	var draft := state.get_draft(domain_id)
	if not (draft.get("option_ids", []) as Array).has(tech_id):
		return false
	if not _catalog.is_tech_eligible(tech_id, state):
		return false
	var definition := _catalog.get_tech(tech_id)
	if definition == null or definition.domain_id != domain_id:
		return false

	var quote := _catalog.compute_cost_quote(tech_id, state)
	if quote.is_empty():
		return false
	var total_cost := int(quote.get("effective_cost_milliunits", 0))
	var inspiration_id := str(quote.get("inspiration_id", ""))
	if not inspiration_id.is_empty():
		state.consume_inspiration(inspiration_id, tech_id)

	state.add_active_project(domain_id, {
		"tech_id": tech_id,
		"level": int(quote.get("level", 1)),
		"total_cost_milliunits": total_cost,
		"invested_milliunits": 0,
		"daily_cap_milliunits": maxi(int(ceili(float(total_cost) / float(definition.min_days))), 1),
		"started_day_serial": _get_current_day_serial(),
		"discount_bp": int(quote.get("discount_bp", 0)),
		"inspiration_id": inspiration_id,
	})
	_refresh_draft(empire_id, domain_id, int(draft.get("serial", 0)) + 1)
	project_started.emit(empire_id, domain_id, tech_id, int(quote.get("level", 1)))
	research_state_changed.emit(empire_id)
	return true


func cancel_project(empire_id: String, domain_id: String, tech_id: String) -> bool:
	var state := _get_state(empire_id)
	if state == null:
		return false
	var project := state.remove_active_project(domain_id, tech_id)
	if project.is_empty():
		return false
	# Invested research is lost; the consumed inspiration stays consumed.
	research_state_changed.emit(empire_id)
	return true


## Grants the next level of a tech without cost or draft validation.
## Intended for debug tools, scripted events, and tests.
func force_complete_tech(empire_id: String, tech_id: String) -> bool:
	var state := _get_state(empire_id)
	var definition := _catalog.get_tech(tech_id)
	if state == null or definition == null:
		return false
	if definition.max_level != 0 and state.get_completed_level(tech_id) >= definition.max_level:
		return false
	state.remove_active_project(definition.domain_id, tech_id)
	state.add_active_project(definition.domain_id, {
		"tech_id": tech_id,
		"level": state.get_completed_level(tech_id) + 1,
		"total_cost_milliunits": 0,
		"invested_milliunits": 0,
		"daily_cap_milliunits": 1,
		"started_day_serial": _get_current_day_serial(),
		"discount_bp": 10000,
		"inspiration_id": "",
	})
	_complete_project(empire_id, state, definition.domain_id, tech_id, _get_current_day_serial())
	return true


# --- Inspirations (breakthrough hooks for anomalies/events) ---

func add_inspiration(empire_id: String, tags_variant: Variant, discount_bp: int, weight_bonus_bp: int, source: String, expires_in_days: int = 0) -> Dictionary:
	var state := _get_state(empire_id)
	if state == null:
		return {}
	var tags := PackedStringArray()
	if tags_variant is PackedStringArray:
		tags = tags_variant
	elif tags_variant is Array:
		for tag_variant in tags_variant:
			var tag := str(tag_variant).strip_edges()
			if not tag.is_empty() and not tags.has(tag):
				tags.append(tag)
	if tags.is_empty():
		return {}

	var day_serial := _get_current_day_serial()
	var expires_day_serial := 0
	if expires_in_days > 0:
		expires_day_serial = day_serial + expires_in_days
	var inspiration := state.add_inspiration(tags, discount_bp, weight_bonus_bp, source, day_serial, expires_day_serial)
	inspiration_added.emit(empire_id, inspiration.duplicate(true))
	research_state_changed.emit(empire_id)
	return inspiration


# --- AI support ---

func build_advisor_context(empire_id: String) -> Dictionary:
	var context := {
		"empire_id": empire_id,
	}
	if EconomyManager != null and EconomyManager.is_bootstrapped():
		context["bottleneck_resource_id"] = EconomyManager.get_bottleneck_resource(empire_id)
	return context


func rank_draft_options(empire_id: String, domain_id: String, persona: Dictionary = {}) -> Array[Dictionary]:
	return RESEARCH_ADVISOR_SCRIPT.rank_options(
		get_draft_options(empire_id, domain_id),
		build_advisor_context(empire_id),
		persona
	)


## Starts the best-scored option of the domain if a slot is free.
## Returns the picked tech id or "".
func auto_pick_project(empire_id: String, domain_id: String, persona: Dictionary = {}) -> String:
	if not can_start_project(empire_id, domain_id):
		return ""
	for ranked in rank_draft_options(empire_id, domain_id, persona):
		var tech_id := str(ranked.get("tech_id", ""))
		if tech_id.is_empty():
			continue
		if start_project(empire_id, domain_id, tech_id):
			return tech_id
	return ""


## Fills every free slot of the empire; used by AI empires and tests.
func auto_pick_all(empire_id: String, persona: Dictionary = {}) -> Array[String]:
	var picked: Array[String] = []
	for domain_id in _catalog.get_domain_ids():
		while can_start_project(empire_id, domain_id):
			var tech_id := auto_pick_project(empire_id, domain_id, persona)
			if tech_id.is_empty():
				break
			picked.append(tech_id)
	return picked


# --- Simulation tick ---

func _on_day_tick(_date: Dictionary) -> void:
	if not _bootstrapped:
		return
	var day_serial := _get_current_day_serial()
	for empire_id in _empire_ids:
		var state := _get_state(empire_id)
		if state == null:
			continue
		if state.prune_expired_inspirations(day_serial) > 0:
			research_state_changed.emit(empire_id)
		_progress_empire_projects(empire_id, state, day_serial)


func _progress_empire_projects(empire_id: String, state: ResearchEmpireState, day_serial: int) -> void:
	var domain_ids: Array = state.active_projects_by_domain.keys()
	domain_ids.sort()
	for domain_id_variant in domain_ids:
		var domain_id := str(domain_id_variant)
		var completed_tech_ids: Array[String] = []
		for project_variant in state.active_projects_by_domain.get(domain_id, []):
			var project: Dictionary = project_variant
			var total := int(project.get("total_cost_milliunits", 0))
			var invested := int(project.get("invested_milliunits", 0))
			var remaining := total - invested
			if remaining > 0:
				var drain := mini(remaining, int(project.get("daily_cap_milliunits", 1)))
				drain = mini(drain, _get_available_research(empire_id))
				if drain > 0 and _commit_research(empire_id, drain):
					invested += drain
					project["invested_milliunits"] = invested
					project_progressed.emit(empire_id, domain_id, str(project.get("tech_id", "")), invested, total)
			if invested >= total:
				completed_tech_ids.append(str(project.get("tech_id", "")))
		for tech_id in completed_tech_ids:
			_complete_project(empire_id, state, domain_id, tech_id, day_serial)


func _complete_project(empire_id: String, state: ResearchEmpireState, domain_id: String, tech_id: String, day_serial: int) -> void:
	var project := state.remove_active_project(domain_id, tech_id)
	if project.is_empty():
		return
	var definition := _catalog.get_tech(tech_id)
	var level := int(project.get("level", 1))
	state.record_completion(tech_id, level, day_serial)
	if definition != null:
		state.add_momentum_for_tags(definition.tags)

	var summary_parts: Array[String] = []
	if definition != null:
		for effect in definition.effects:
			var effect_summary := _apply_effect(empire_id, state, definition, level, effect)
			if not effect_summary.is_empty():
				summary_parts.append(effect_summary)

	_refresh_draft(empire_id, domain_id, get_draft_serial(empire_id, domain_id) + 1)
	tech_completed.emit(empire_id, tech_id, level, "; ".join(summary_parts))
	research_state_changed.emit(empire_id)


# --- Effects ---

func _apply_effect(empire_id: String, state: ResearchEmpireState, definition: ResearchTechDefinition, level: int, effect: Dictionary) -> String:
	var effect_type := str(effect.get("type", ""))
	var summary := ""
	match effect_type:
		ResearchTechDefinition.EFFECT_UNLOCK_COMPONENT:
			var component_id := str(effect.get("component_id", ""))
			if SpaceManager != null and SpaceManager.has_method("unlock_ship_component"):
				SpaceManager.unlock_ship_component(empire_id, component_id)
			summary = "Komponente freigeschaltet: %s" % component_id
		ResearchTechDefinition.EFFECT_UNLOCK_BUILDING:
			var building_id := str(effect.get("building_id", ""))
			state.unlock_building(building_id)
			summary = "Gebaeude freigeschaltet: %s" % building_id
		ResearchTechDefinition.EFFECT_GRANT_RESOURCES:
			if EconomyManager != null and EconomyManager.is_bootstrapped():
				EconomyManager.grant_resources(empire_id, effect.get("resources", []))
			summary = "Einmalige Ressourcen erhalten"
		ResearchTechDefinition.EFFECT_MONTHLY_RESOURCES:
			if EconomyManager != null and EconomyManager.is_bootstrapped():
				var source_id := "research_tech:%s:lvl%d:%s" % [definition.tech_id, level, empire_id]
				if not EconomyManager.has_source(source_id):
					EconomyManager.register_source(
						source_id,
						empire_id,
						effect.get("resources", []),
						[],
						[],
						"research_tech",
						PackedStringArray([definition.tech_id])
					)
			summary = "Monatliche Produktion erweitert"
		ResearchTechDefinition.EFFECT_MODIFIER:
			state.add_modifier_bp(str(effect.get("key", "")), int(effect.get("value_bp", 0)))
			summary = "Modifikator: %s %+d bp" % [str(effect.get("key", "")), int(effect.get("value_bp", 0))]
		ResearchTechDefinition.EFFECT_RESEARCH_SLOT:
			state.add_extra_slots(str(effect.get("domain", "")), int(effect.get("amount", 1)))
			summary = "Zusaetzlicher Forschungs-Slot"
		ResearchTechDefinition.EFFECT_CUSTOM:
			tech_effect_requested.emit(empire_id, definition.tech_id, effect.duplicate(true))
			summary = ""
		_:
			return ""
	tech_effect_applied.emit(empire_id, definition.tech_id, effect.duplicate(true))
	return summary


# --- Snapshots ---

func build_snapshot() -> Dictionary:
	var empire_states: Dictionary = {}
	for empire_id in _empire_ids:
		var state := _get_state(empire_id)
		if state != null:
			empire_states[empire_id] = state.to_dict()
	return {
		"galaxy_seed": _galaxy_seed,
		"empire_ids": Array(_empire_ids),
		"empire_states": empire_states,
	}


func load_snapshot(snapshot: Dictionary) -> void:
	ensure_catalog_loaded()
	clear_runtime_state()
	if snapshot.is_empty():
		return
	_galaxy_seed = int(snapshot.get("galaxy_seed", 0))
	var empire_states_variant: Variant = snapshot.get("empire_states", {})
	if empire_states_variant is not Dictionary:
		return
	var ordered_ids: Array = snapshot.get("empire_ids", (empire_states_variant as Dictionary).keys())
	for empire_id_variant in ordered_ids:
		var empire_id := str(empire_id_variant).strip_edges()
		if empire_id.is_empty() or _states_by_empire.has(empire_id):
			continue
		var state_variant: Variant = (empire_states_variant as Dictionary).get(empire_id, {})
		if state_variant is not Dictionary:
			continue
		var state := RESEARCH_EMPIRE_STATE_SCRIPT.from_dict(state_variant) as ResearchEmpireState
		if state == null:
			continue
		_states_by_empire[empire_id] = state
		_empire_ids.append(empire_id)
	_bootstrapped = not _empire_ids.is_empty()


# --- Internals ---

func _get_state(empire_id: String) -> ResearchEmpireState:
	return _states_by_empire.get(empire_id, null)


func _refresh_draft(empire_id: String, domain_id: String, serial: int) -> void:
	var state := _get_state(empire_id)
	if state == null:
		return
	var seed_key := "%d:%s:%s:%d:draft" % [_galaxy_seed, empire_id, domain_id, serial]
	var option_ids := _catalog.draw_draft_option_ids(domain_id, state, seed_key)
	state.set_draft(domain_id, serial, option_ids)
	draft_refreshed.emit(empire_id, domain_id, serial)


func _build_option_entry(tech_id: String, state: ResearchEmpireState, domain: ResearchDomainDefinition) -> Dictionary:
	var definition := _catalog.get_tech(tech_id)
	var entry := definition.to_dict()
	var quote := _catalog.compute_cost_quote(tech_id, state)
	for key_variant in quote.keys():
		entry[key_variant] = quote[key_variant]
	entry["effective_weight"] = _catalog.get_effective_weight(tech_id, state, domain)
	entry["inspired"] = not str(quote.get("inspiration_id", "")).is_empty()
	return entry


func _get_available_research(empire_id: String) -> int:
	if EconomyManager == null or not EconomyManager.is_bootstrapped():
		return 0
	return EconomyManager.get_amount(empire_id, RESEARCH_RESOURCE_ID)


func _commit_research(empire_id: String, milliunits: int) -> bool:
	if EconomyManager == null or not EconomyManager.is_bootstrapped():
		return false
	return EconomyManager.commit_cost(empire_id, [{"resource_id": RESEARCH_RESOURCE_ID, "milliunits": milliunits}])


func _get_current_day_serial() -> int:
	if SimClock != null and SimClock.has_method("get_current_day_serial"):
		return SimClock.get_current_day_serial()
	return 0
