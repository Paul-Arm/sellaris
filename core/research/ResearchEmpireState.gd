extends RefCounted
class_name ResearchEmpireState

## Per-empire research runtime state: completed techs, active projects,
## current drafts, momentum, inspirations, and tech-granted unlocks.

var empire_id: String = ""
## tech_id -> completed level (>= 1)
var completed_levels: Dictionary = {}
## Chronological completion log: {tech_id, level, day_serial}
var completed_log: Array[Dictionary] = []
## domain_id -> Array of active projects:
## {tech_id, level, total_cost_milliunits, invested_milliunits,
##  daily_cap_milliunits, started_day_serial, discount_bp, inspiration_id}
var active_projects_by_domain: Dictionary = {}
## domain_id -> {serial: int, option_ids: Array[String]}
var drafts_by_domain: Dictionary = {}
## tag -> momentum level (completed techs carrying the tag)
var momentum_by_tag: Dictionary = {}
## Breakthrough tokens: {id, tags, discount_bp, weight_bonus_bp, source,
##  created_day_serial, expires_day_serial, consumed_by}
var inspirations: Array[Dictionary] = []
## domain_id ("" = all domains) -> additional research slots
var extra_slots_by_domain: Dictionary = {}
## modifier key -> accumulated value in basis points
var modifiers_bp: Dictionary = {}
## building_id -> true
var unlocked_building_ids: Dictionary = {}
var next_inspiration_serial: int = 1


# --- Completion ---

func get_completed_level(tech_id: String) -> int:
	return int(completed_levels.get(tech_id, 0))


func get_completed_tech_ids() -> Array[String]:
	var result: Array[String] = []
	for tech_id_variant in completed_levels.keys():
		result.append(str(tech_id_variant))
	result.sort()
	return result


func record_completion(tech_id: String, level: int, day_serial: int) -> void:
	completed_levels[tech_id] = maxi(level, get_completed_level(tech_id))
	completed_log.append({
		"tech_id": tech_id,
		"level": level,
		"day_serial": maxi(day_serial, 0),
	})


# --- Active projects ---

func get_active_projects(domain_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for project_variant in active_projects_by_domain.get(domain_id, []):
		if project_variant is Dictionary:
			result.append(project_variant)
	return result


func get_active_tech_ids() -> Array[String]:
	var result: Array[String] = []
	var domain_ids: Array = active_projects_by_domain.keys()
	domain_ids.sort()
	for domain_id in domain_ids:
		for project_variant in active_projects_by_domain.get(domain_id, []):
			if project_variant is Dictionary:
				result.append(str((project_variant as Dictionary).get("tech_id", "")))
	return result


func is_tech_active(tech_id: String) -> bool:
	return get_active_tech_ids().has(tech_id)


func add_active_project(domain_id: String, project: Dictionary) -> void:
	var projects: Array = active_projects_by_domain.get(domain_id, [])
	projects.append(project)
	active_projects_by_domain[domain_id] = projects


func remove_active_project(domain_id: String, tech_id: String) -> Dictionary:
	var projects: Array = active_projects_by_domain.get(domain_id, [])
	for project_index in range(projects.size()):
		var project: Dictionary = projects[project_index]
		if str(project.get("tech_id", "")) == tech_id:
			projects.remove_at(project_index)
			if projects.is_empty():
				active_projects_by_domain.erase(domain_id)
			else:
				active_projects_by_domain[domain_id] = projects
			return project
	return {}


# --- Drafts ---

func get_draft(domain_id: String) -> Dictionary:
	var draft_variant: Variant = drafts_by_domain.get(domain_id, {})
	if draft_variant is not Dictionary:
		return {}
	return draft_variant


func set_draft(domain_id: String, serial: int, option_ids: Array[String]) -> void:
	drafts_by_domain[domain_id] = {
		"serial": maxi(serial, 0),
		"option_ids": Array(option_ids),
	}


# --- Momentum ---

func add_momentum_for_tags(tags: PackedStringArray, amount: int = 1) -> void:
	for tag in tags:
		momentum_by_tag[tag] = int(momentum_by_tag.get(tag, 0)) + amount


func get_momentum(tag: String) -> int:
	return int(momentum_by_tag.get(tag, 0))


func get_momentum_for_tags(tags: PackedStringArray) -> int:
	var total := 0
	for tag in tags:
		total += get_momentum(tag)
	return total


# --- Inspirations ---

func add_inspiration(tags: PackedStringArray, discount_bp: int, weight_bonus_bp: int, source: String, created_day_serial: int, expires_day_serial: int = 0) -> Dictionary:
	var inspiration := {
		"id": "insight_%s_%04d" % [empire_id, next_inspiration_serial],
		"tags": Array(tags),
		"discount_bp": clampi(discount_bp, 0, 10000),
		"weight_bonus_bp": maxi(weight_bonus_bp, 0),
		"source": source,
		"created_day_serial": maxi(created_day_serial, 0),
		"expires_day_serial": maxi(expires_day_serial, 0),
		"consumed_by": "",
	}
	next_inspiration_serial += 1
	inspirations.append(inspiration)
	return inspiration.duplicate(true)


## Unconsumed inspirations sharing at least one tag with the given list.
## Expired entries are pruned by the manager's day tick.
func get_matching_inspirations(tags: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for inspiration_variant in inspirations:
		if inspiration_variant is not Dictionary:
			continue
		var inspiration: Dictionary = inspiration_variant
		if not str(inspiration.get("consumed_by", "")).is_empty():
			continue
		for tag_variant in inspiration.get("tags", []):
			if tags.has(str(tag_variant)):
				result.append(inspiration)
				break
	return result


func consume_inspiration(inspiration_id: String, consumed_by_tech_id: String) -> bool:
	for inspiration_variant in inspirations:
		if inspiration_variant is not Dictionary:
			continue
		var inspiration: Dictionary = inspiration_variant
		if str(inspiration.get("id", "")) != inspiration_id:
			continue
		if not str(inspiration.get("consumed_by", "")).is_empty():
			return false
		inspiration["consumed_by"] = consumed_by_tech_id
		return true
	return false


func prune_expired_inspirations(day_serial: int) -> int:
	var removed := 0
	for inspiration_index in range(inspirations.size() - 1, -1, -1):
		var inspiration: Dictionary = inspirations[inspiration_index]
		var expires := int(inspiration.get("expires_day_serial", 0))
		if expires > 0 and day_serial >= expires and str(inspiration.get("consumed_by", "")).is_empty():
			inspirations.remove_at(inspiration_index)
			removed += 1
	return removed


# --- Slots, modifiers, building unlocks ---

func add_extra_slots(domain_id: String, amount: int) -> void:
	extra_slots_by_domain[domain_id] = int(extra_slots_by_domain.get(domain_id, 0)) + amount


func get_extra_slots(domain_id: String) -> int:
	return int(extra_slots_by_domain.get(domain_id, 0)) + int(extra_slots_by_domain.get("", 0))


func add_modifier_bp(key: String, value_bp: int) -> void:
	modifiers_bp[key] = int(modifiers_bp.get(key, 0)) + value_bp


func get_modifier_bp(key: String, default_bp: int = 0) -> int:
	return int(modifiers_bp.get(key, default_bp))


func unlock_building(building_id: String) -> bool:
	if unlocked_building_ids.has(building_id):
		return false
	unlocked_building_ids[building_id] = true
	return true


func is_building_unlocked(building_id: String) -> bool:
	return unlocked_building_ids.has(building_id)


# --- Snapshots ---

func to_dict() -> Dictionary:
	return {
		"empire_id": empire_id,
		"completed_levels": completed_levels.duplicate(true),
		"completed_log": completed_log.duplicate(true),
		"active_projects_by_domain": active_projects_by_domain.duplicate(true),
		"drafts_by_domain": drafts_by_domain.duplicate(true),
		"momentum_by_tag": momentum_by_tag.duplicate(true),
		"inspirations": inspirations.duplicate(true),
		"extra_slots_by_domain": extra_slots_by_domain.duplicate(true),
		"modifiers_bp": modifiers_bp.duplicate(true),
		"unlocked_building_ids": get_unlocked_building_ids(),
		"next_inspiration_serial": next_inspiration_serial,
	}


func get_unlocked_building_ids() -> Array[String]:
	var result: Array[String] = []
	for building_id_variant in unlocked_building_ids.keys():
		result.append(str(building_id_variant))
	result.sort()
	return result


static func from_dict(data: Dictionary) -> ResearchEmpireState:
	var state := ResearchEmpireState.new()
	state.empire_id = str(data.get("empire_id", "")).strip_edges()
	if state.empire_id.is_empty():
		return null

	var completed_variant: Variant = data.get("completed_levels", {})
	if completed_variant is Dictionary:
		for tech_id_variant in completed_variant.keys():
			var tech_id := str(tech_id_variant).strip_edges()
			var level := int(completed_variant.get(tech_id_variant, 0))
			if tech_id.is_empty() or level <= 0:
				continue
			state.completed_levels[tech_id] = level

	for log_variant in data.get("completed_log", []):
		if log_variant is Dictionary:
			state.completed_log.append((log_variant as Dictionary).duplicate(true))

	var projects_variant: Variant = data.get("active_projects_by_domain", {})
	if projects_variant is Dictionary:
		for domain_id_variant in projects_variant.keys():
			var projects: Array = []
			for project_variant in projects_variant.get(domain_id_variant, []):
				if project_variant is Dictionary:
					projects.append((project_variant as Dictionary).duplicate(true))
			if not projects.is_empty():
				state.active_projects_by_domain[str(domain_id_variant)] = projects

	var drafts_variant: Variant = data.get("drafts_by_domain", {})
	if drafts_variant is Dictionary:
		for domain_id_variant in drafts_variant.keys():
			var draft_variant: Variant = drafts_variant.get(domain_id_variant, {})
			if draft_variant is not Dictionary:
				continue
			var option_ids: Array[String] = []
			for option_id_variant in (draft_variant as Dictionary).get("option_ids", []):
				option_ids.append(str(option_id_variant))
			state.set_draft(str(domain_id_variant), int((draft_variant as Dictionary).get("serial", 0)), option_ids)

	var momentum_variant: Variant = data.get("momentum_by_tag", {})
	if momentum_variant is Dictionary:
		for tag_variant in momentum_variant.keys():
			state.momentum_by_tag[str(tag_variant)] = int(momentum_variant.get(tag_variant, 0))

	for inspiration_variant in data.get("inspirations", []):
		if inspiration_variant is Dictionary:
			state.inspirations.append((inspiration_variant as Dictionary).duplicate(true))

	var slots_variant: Variant = data.get("extra_slots_by_domain", {})
	if slots_variant is Dictionary:
		for domain_id_variant in slots_variant.keys():
			state.extra_slots_by_domain[str(domain_id_variant)] = int(slots_variant.get(domain_id_variant, 0))

	var modifiers_variant: Variant = data.get("modifiers_bp", {})
	if modifiers_variant is Dictionary:
		for key_variant in modifiers_variant.keys():
			state.modifiers_bp[str(key_variant)] = int(modifiers_variant.get(key_variant, 0))

	for building_id_variant in data.get("unlocked_building_ids", []):
		var building_id := str(building_id_variant).strip_edges()
		if not building_id.is_empty():
			state.unlocked_building_ids[building_id] = true

	state.next_inspiration_serial = maxi(int(data.get("next_inspiration_serial", 1)), 1)
	return state
