extends RefCounted
class_name ResearchCatalog

## Loads research domains and technologies from config files and runtime
## registrations. Every *.cfg file in the tech directories is merged, so mods
## add content by dropping files next to the core set (or by calling
## register_tech_dict / register_domain_dict at runtime).

const DOMAIN_DEFINITION_PATH := "res://core/research/domains.cfg"
const TECH_DIRECTORIES: Array[String] = ["res://core/research/techs"]
const MAX_TOTAL_DISCOUNT_BP := 7500

var _domains_by_id: Dictionary = {}
var _domain_ids: Array[String] = []
var _techs_by_id: Dictionary = {}
var _tech_ids: Array[String] = []
var _tech_ids_by_domain: Dictionary = {}
var _catalog_version: int = 0


func load_definitions(domain_path: String = DOMAIN_DEFINITION_PATH, tech_directories: Array[String] = TECH_DIRECTORIES) -> void:
	_domains_by_id.clear()
	_domain_ids.clear()
	_techs_by_id.clear()
	_tech_ids.clear()
	_tech_ids_by_domain.clear()
	_catalog_version += 1

	_load_domain_file(domain_path)
	if _domains_by_id.is_empty():
		_install_fallback_domains()

	for tech_directory in tech_directories:
		for file_path in _list_config_paths(tech_directory):
			_load_tech_file(file_path)
	_sort_indices()


func get_catalog_version() -> int:
	return _catalog_version


# --- Runtime registration (mod support) ---

func register_domain_dict(domain_id: String, data: Dictionary) -> bool:
	var definition := ResearchDomainDefinition.from_dict(domain_id, data)
	if definition == null:
		push_warning("ResearchCatalog: rejected invalid runtime domain '%s'" % domain_id)
		return false
	if not _domains_by_id.has(definition.domain_id):
		_domain_ids.append(definition.domain_id)
	_domains_by_id[definition.domain_id] = definition
	_catalog_version += 1
	_sort_indices()
	return true


func register_tech_dict(tech_id: String, data: Dictionary, source: String = "runtime") -> bool:
	var definition := ResearchTechDefinition.from_dict(tech_id, data, source)
	if definition == null:
		push_warning("ResearchCatalog: rejected invalid runtime tech '%s'" % tech_id)
		return false
	if not _domains_by_id.has(definition.domain_id):
		push_warning("ResearchCatalog: tech '%s' references unknown domain '%s'" % [tech_id, definition.domain_id])
		return false
	_remove_tech_from_indices(definition.tech_id)
	_techs_by_id[definition.tech_id] = definition
	_tech_ids.append(definition.tech_id)
	var domain_tech_ids: Array = _tech_ids_by_domain.get(definition.domain_id, [])
	domain_tech_ids.append(definition.tech_id)
	_tech_ids_by_domain[definition.domain_id] = domain_tech_ids
	_catalog_version += 1
	_sort_indices()
	return true


# --- Queries ---

func has_domain(domain_id: String) -> bool:
	return _domains_by_id.has(domain_id)


func get_domain(domain_id: String) -> ResearchDomainDefinition:
	return _domains_by_id.get(domain_id, null)


func get_domain_ids() -> Array[String]:
	return _domain_ids.duplicate()


func has_tech(tech_id: String) -> bool:
	return _techs_by_id.has(tech_id)


func get_tech(tech_id: String) -> ResearchTechDefinition:
	return _techs_by_id.get(tech_id, null)


func get_tech_ids() -> Array[String]:
	return _tech_ids.duplicate()


func get_tech_ids_for_domain(domain_id: String) -> Array[String]:
	var result: Array[String] = []
	for tech_id_variant in _tech_ids_by_domain.get(domain_id, []):
		result.append(str(tech_id_variant))
	return result


func size() -> int:
	return _tech_ids.size()


# --- Eligibility & deterministic drafts ---

## Highest tier the empire may research in this domain, derived from the
## number of distinct completed techs of the domain.
func get_unlocked_tier(domain_id: String, state: ResearchEmpireState) -> int:
	var domain := get_domain(domain_id)
	if domain == null or state == null:
		return 0
	var completed_in_domain := count_completed_in_domain(domain_id, state)
	var tier := 0
	while completed_in_domain >= domain.get_required_completions_for_tier(tier + 1):
		tier += 1
		if tier > 64:
			break
	return tier


func count_completed_in_domain(domain_id: String, state: ResearchEmpireState) -> int:
	var count := 0
	for tech_id in state.get_completed_tech_ids():
		var definition := get_tech(tech_id)
		if definition != null and definition.domain_id == domain_id:
			count += 1
	return count


func is_tech_eligible(tech_id: String, state: ResearchEmpireState) -> bool:
	var definition := get_tech(tech_id)
	if definition == null or state == null or definition.weight <= 0:
		return false
	if state.is_tech_active(definition.tech_id):
		return false
	if definition.max_level != 0 and state.get_completed_level(definition.tech_id) >= definition.max_level:
		return false
	for required_tech_id in definition.requires:
		if state.get_completed_level(required_tech_id) <= 0:
			return false
	if definition.tier > get_unlocked_tier(definition.domain_id, state):
		return false
	if not definition.exclusive_group.is_empty() and _is_exclusive_group_taken(definition, state):
		return false
	return true


func collect_eligible_tech_ids(domain_id: String, state: ResearchEmpireState) -> Array[String]:
	var result: Array[String] = []
	for tech_id in get_tech_ids_for_domain(domain_id):
		if is_tech_eligible(tech_id, state):
			result.append(tech_id)
	return result


## Deterministic weighted draw without replacement. The same seed key always
## produces the same draft for the same eligible pool.
func draw_draft_option_ids(domain_id: String, state: ResearchEmpireState, draft_seed_key: String) -> Array[String]:
	var domain := get_domain(domain_id)
	if domain == null:
		return []
	var pool := collect_eligible_tech_ids(domain_id, state)
	var result: Array[String] = []
	for slot_index in range(domain.draft_size):
		if pool.is_empty():
			break
		var picked := _pick_weighted_tech_id(pool, state, domain, "%s:%d" % [draft_seed_key, slot_index])
		if picked.is_empty():
			break
		result.append(picked)
		pool.erase(picked)
	return result


## Draft weight after momentum and inspiration bonuses, in deterministic ints.
func get_effective_weight(tech_id: String, state: ResearchEmpireState, domain: ResearchDomainDefinition) -> int:
	var definition := get_tech(tech_id)
	if definition == null or definition.weight <= 0:
		return 0
	var weight_mult_bp := 10000
	if domain != null:
		weight_mult_bp += domain.momentum_weight_bonus_bp * state.get_momentum_for_tags(definition.tags)
	for inspiration in state.get_matching_inspirations(definition.tags):
		weight_mult_bp += int(inspiration.get("weight_bonus_bp", 0))
	return maxi(int(definition.weight * weight_mult_bp / 10000.0), 1)


## Cost quote for starting the next level of a tech: base cost, momentum and
## inspiration discounts, and which inspiration would be consumed.
func compute_cost_quote(tech_id: String, state: ResearchEmpireState) -> Dictionary:
	var definition := get_tech(tech_id)
	if definition == null or state == null:
		return {}
	var domain := get_domain(definition.domain_id)
	var next_level := state.get_completed_level(definition.tech_id) + 1
	var base_cost := definition.get_cost_for_level(next_level)

	var momentum_levels := state.get_momentum_for_tags(definition.tags)
	var momentum_discount_bp := 0
	if domain != null:
		momentum_discount_bp = mini(domain.momentum_discount_bp * momentum_levels, domain.momentum_discount_cap_bp)

	var inspiration_id := ""
	var inspiration_discount_bp := 0
	for inspiration in state.get_matching_inspirations(definition.tags):
		var discount_bp := int(inspiration.get("discount_bp", 0))
		if discount_bp > inspiration_discount_bp:
			inspiration_discount_bp = discount_bp
			inspiration_id = str(inspiration.get("id", ""))

	var total_discount_bp := clampi(momentum_discount_bp + inspiration_discount_bp, 0, MAX_TOTAL_DISCOUNT_BP)
	var effective_cost := maxi(int(base_cost * (10000 - total_discount_bp) / 10000.0), 1)
	return {
		"tech_id": definition.tech_id,
		"level": next_level,
		"base_cost_milliunits": base_cost,
		"momentum_levels": momentum_levels,
		"momentum_discount_bp": momentum_discount_bp,
		"inspiration_id": inspiration_id,
		"inspiration_discount_bp": inspiration_discount_bp,
		"discount_bp": total_discount_bp,
		"effective_cost_milliunits": effective_cost,
		"min_days": definition.min_days,
	}


func _is_exclusive_group_taken(definition: ResearchTechDefinition, state: ResearchEmpireState) -> bool:
	for tech_id in state.get_completed_tech_ids():
		if tech_id == definition.tech_id:
			continue
		var other := get_tech(tech_id)
		if other != null and other.exclusive_group == definition.exclusive_group:
			return true
	for tech_id in state.get_active_tech_ids():
		if tech_id == definition.tech_id:
			continue
		var other := get_tech(tech_id)
		if other != null and other.exclusive_group == definition.exclusive_group:
			return true
	return false


func _pick_weighted_tech_id(pool: Array[String], state: ResearchEmpireState, domain: ResearchDomainDefinition, seed_key: String) -> String:
	var total_weight := 0
	var weights: Array[int] = []
	for tech_id in pool:
		var effective_weight := get_effective_weight(tech_id, state, domain)
		weights.append(effective_weight)
		total_weight += effective_weight
	if total_weight <= 0:
		return ""

	var roll := stable_hash(seed_key) % total_weight
	var cursor := 0
	for pool_index in range(pool.size()):
		cursor += weights[pool_index]
		if roll < cursor:
			return pool[pool_index]
	return pool[pool.size() - 1]


# --- Loading ---

func _load_domain_file(domain_path: String) -> void:
	var config := ConfigFile.new()
	if config.load(domain_path) != OK:
		return
	for section in config.get_sections():
		var data: Dictionary = {}
		for key in config.get_section_keys(section):
			data[key] = config.get_value(section, key)
		var definition := ResearchDomainDefinition.from_dict(str(section), data)
		if definition == null:
			push_warning("ResearchCatalog: skipped invalid domain definition '%s'" % str(section))
			continue
		if not _domains_by_id.has(definition.domain_id):
			_domain_ids.append(definition.domain_id)
		_domains_by_id[definition.domain_id] = definition


func _load_tech_file(file_path: String) -> void:
	var config := ConfigFile.new()
	if config.load(file_path) != OK:
		push_warning("ResearchCatalog: failed to load tech config '%s'" % file_path)
		return
	for section in config.get_sections():
		var data: Dictionary = {}
		for key in config.get_section_keys(section):
			data[key] = config.get_value(section, key)
		var definition := ResearchTechDefinition.from_dict(str(section), data, file_path)
		if definition == null:
			push_warning("ResearchCatalog: skipped invalid tech definition '%s' in %s" % [str(section), file_path])
			continue
		if not _domains_by_id.has(definition.domain_id):
			push_warning("ResearchCatalog: tech '%s' references unknown domain '%s' (%s)" % [definition.tech_id, definition.domain_id, file_path])
			continue
		if _techs_by_id.has(definition.tech_id):
			push_warning("ResearchCatalog: tech '%s' from %s overrides %s" % [definition.tech_id, file_path, (_techs_by_id[definition.tech_id] as ResearchTechDefinition).source])
			_remove_tech_from_indices(definition.tech_id)
		_techs_by_id[definition.tech_id] = definition
		_tech_ids.append(definition.tech_id)
		var domain_tech_ids: Array = _tech_ids_by_domain.get(definition.domain_id, [])
		domain_tech_ids.append(definition.tech_id)
		_tech_ids_by_domain[definition.domain_id] = domain_tech_ids


func _remove_tech_from_indices(tech_id: String) -> void:
	var existing: ResearchTechDefinition = _techs_by_id.get(tech_id, null)
	if existing == null:
		return
	_techs_by_id.erase(tech_id)
	_tech_ids.erase(tech_id)
	var domain_tech_ids: Array = _tech_ids_by_domain.get(existing.domain_id, [])
	domain_tech_ids.erase(tech_id)
	_tech_ids_by_domain[existing.domain_id] = domain_tech_ids


func _sort_indices() -> void:
	_domain_ids.sort_custom(func(a: String, b: String) -> bool:
		var domain_a: ResearchDomainDefinition = _domains_by_id[a]
		var domain_b: ResearchDomainDefinition = _domains_by_id[b]
		if domain_a.sort_key == domain_b.sort_key:
			return a < b
		return domain_a.sort_key < domain_b.sort_key
	)
	_tech_ids.sort_custom(_sort_tech_ids)
	for domain_id_variant in _tech_ids_by_domain.keys():
		var domain_tech_ids: Array = _tech_ids_by_domain[domain_id_variant]
		domain_tech_ids.sort_custom(_sort_tech_ids)
		_tech_ids_by_domain[domain_id_variant] = domain_tech_ids


func _sort_tech_ids(a: String, b: String) -> bool:
	var tech_a: ResearchTechDefinition = _techs_by_id[a]
	var tech_b: ResearchTechDefinition = _techs_by_id[b]
	if tech_a.tier != tech_b.tier:
		return tech_a.tier < tech_b.tier
	if tech_a.sort_key != tech_b.sort_key:
		return tech_a.sort_key < tech_b.sort_key
	return a < b


func _list_config_paths(directory_path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return result
	directory.list_dir_begin()
	while true:
		var file_name := directory.get_next()
		if file_name.is_empty():
			break
		if directory.current_is_dir() or not file_name.ends_with(".cfg"):
			continue
		result.append("%s/%s" % [directory_path, file_name])
	directory.list_dir_end()
	result.sort()
	return result


func _install_fallback_domains() -> void:
	push_warning("ResearchCatalog: domain config missing, installing fallback domains")
	var fallback := {
		"industry": {"display_name": "Industrie & Materie", "sort_key": 10},
		"voidcraft": {"display_name": "Raumfahrt & Waffen", "sort_key": 20},
		"frontier": {"display_name": "Grenzland & Erkenntnis", "sort_key": 30},
	}
	for domain_id_variant in fallback.keys():
		var domain_id := str(domain_id_variant)
		var definition := ResearchDomainDefinition.from_dict(domain_id, fallback[domain_id_variant])
		if definition == null:
			continue
		_domains_by_id[domain_id] = definition
		_domain_ids.append(domain_id)


static func stable_hash(value: String) -> int:
	var hash_value: int = 2166136261
	var bytes := value.to_utf8_buffer()
	for byte in bytes:
		hash_value = int(((hash_value ^ int(byte)) * 16777619) & 0x7fffffff)
	return hash_value
