extends RefCounted
class_name AnomalyPool

const ANOMALY_COMPONENT_SCRIPT: Script = preload("res://core/anomaly/AnomalyComponent.gd")

const FREQUENCY_ONCE_PER_GAME := "once_per_game"
const FREQUENCY_ONCE_PER_PLAYER := "once_per_player"
const FREQUENCY_REPEATABLE := "repeatable"

const STATUS_HIDDEN := "hidden"
const STATUS_DISCOVERED := "discovered"
const STATUS_RESEARCHED := "researched"

const OUTCOME_GRANT_RESOURCES := "grant_resources"
const OUTCOME_MONTHLY_RESOURCES := "monthly_resources"
const OUTCOME_SPAWN_UNIT := "spawn_unit"
const OUTCOME_RUNTIME_METHOD := "runtime_method"
const OUTCOME_RESEARCH_INSPIRATION := "research_inspiration"

const BODY_TYPE_STAR := "star"
const BODY_TYPE_PLANET := "planet"
const BODY_TYPE_ASTEROID_BELT := "asteroid_belt"
const BODY_TYPE_STRUCTURE := "structure"
const BODY_TYPE_RUIN := "ruin"

const DEFINITIONS := [
	{
		"id": "quiet_vault",
		"title": "Stiller Tresor",
		"description": "Ein versiegeltes Depot wartet auf eine kurze Untersuchung.",
		"frequency": FREQUENCY_ONCE_PER_GAME,
		"research_days": 45,
		"spawn": {
			"body_types": [BODY_TYPE_PLANET, BODY_TYPE_STRUCTURE, BODY_TYPE_RUIN],
			"chance_bp": 420,
			"weight": 1000,
		},
		"discovery_lore": [
			"Scanner finden eine perfekt kreisrunde Naht unter der Oberflaeche.",
			"Ein altes Speicherfeld antwortet mit einem einzelnen, wiederholten Puls.",
			"Die Crew entdeckt einen stillen Tresor, dessen Energiezellen noch warm sind.",
		],
		"outcomes": [
			{
				"type": OUTCOME_GRANT_RESOURCES,
				"weight": 1000,
				"summary": "Einmaliger Ressourcenfund",
				"resource_table": [
					{"weight": 45, "resources": [{"resource_id": "matter", "milliunits": 42000}]},
					{"weight": 35, "resources": [{"resource_id": "energy", "milliunits": 36000}]},
					{"weight": 20, "resources": [{"resource_id": "alloys", "milliunits": 16000}]},
				],
			},
		],
	},
	{
		"id": "singing_vein",
		"title": "Singende Ader",
		"description": "Eine resonante Mineralader koennte dauerhaft ausgebeutet werden.",
		"frequency": FREQUENCY_REPEATABLE,
		"research_days": 60,
		"spawn": {
			"body_types": [BODY_TYPE_ASTEROID_BELT, BODY_TYPE_PLANET],
			"chance_bp": 760,
			"weight": 1000,
		},
		"discovery_lore": [
			"Die Spektrometer zeichnen rhythmische Schwingungen im Erz auf.",
			"Unter der Kruste liegt eine Ader, die wie ein ferner Chor vibriert.",
			"Jede Prospektionssonde meldet dieselbe harmonische Signatur.",
		],
		"outcomes": [
			{
				"type": OUTCOME_MONTHLY_RESOURCES,
				"weight": 1000,
				"summary": "Monatlicher Ressourcenfluss",
				"resource_table": [
					{"weight": 50, "resources": [{"resource_id": "matter", "milliunits": 2400}]},
					{"weight": 30, "resources": [{"resource_id": "energy", "milliunits": 1800}]},
					{"weight": 20, "resources": [{"resource_id": "exotic_gases", "milliunits": 700}]},
				],
			},
		],
	},
	{
		"id": "drifting_probe",
		"title": "Treibende Sonde",
		"description": "Eine alte Sonde kann reaktiviert und als Schiff uebernommen werden.",
		"frequency": FREQUENCY_ONCE_PER_PLAYER,
		"research_days": 50,
		"spawn": {
			"body_types": [BODY_TYPE_STAR, BODY_TYPE_STRUCTURE, BODY_TYPE_RUIN],
			"chance_bp": 520,
			"weight": 1000,
		},
		"discovery_lore": [
			"Ein bewegungsloser Kontakt haelt exakten Abstand zum lokalen Schwerpunkt.",
			"Die Sonde funkt mit einem Protokoll, das aelter ist als jede lokale Karte.",
			"Im Schatten des Himmelskoerpers treibt ein fast intaktes Forschungsmodul.",
		],
		"outcomes": [
			{
				"type": OUTCOME_SPAWN_UNIT,
				"weight": 1000,
				"summary": "Ein Wissenschaftsschiff wird geborgen",
				"class_id": "science_ship",
				"display_name": "Reaktivierte Sonde",
			},
		],
	},
	{
		"id": "fractured_archive",
		"title": "Zersplittertes Archiv",
		"description": "Bruchstuecke einer fremden Datenbank koennten die eigene Forschung befluegeln.",
		"frequency": FREQUENCY_REPEATABLE,
		"research_days": 55,
		"spawn": {
			"body_types": [BODY_TYPE_RUIN, BODY_TYPE_STRUCTURE, BODY_TYPE_PLANET],
			"chance_bp": 540,
			"weight": 1000,
		},
		"discovery_lore": [
			"Zwischen den Truemmern rotieren Speicherkerne in perfekter Formation.",
			"Ein beschaedigter Index verweist auf Wissen, das niemand mehr besitzt.",
			"Die Fragmente antworten auf Abfragen - in einer Sprache aus reiner Mathematik.",
		],
		"outcomes": [
			{
				"type": OUTCOME_RESEARCH_INSPIRATION,
				"weight": 600,
				"summary": "Inspiration fuer die Waffenforschung",
				"inspiration": {"tags": ["weapons", "voidcraft"], "discount_bp": 2500, "weight_bonus_bp": 6000, "expires_in_days": 720},
			},
			{
				"type": OUTCOME_RESEARCH_INSPIRATION,
				"weight": 600,
				"summary": "Inspiration fuer die Industrieforschung",
				"inspiration": {"tags": ["industry", "matter"], "discount_bp": 2500, "weight_bonus_bp": 6000, "expires_in_days": 720},
			},
			{
				"type": OUTCOME_RESEARCH_INSPIRATION,
				"weight": 500,
				"summary": "Inspiration fuer die Grundlagenforschung",
				"inspiration": {"tags": ["science", "frontier"], "discount_bp": 2500, "weight_bonus_bp": 6000, "expires_in_days": 720},
			},
			{
				"type": OUTCOME_GRANT_RESOURCES,
				"weight": 300,
				"summary": "Geborgene Rohdaten",
				"resource_table": [
					{"weight": 100, "resources": [{"resource_id": "research", "milliunits": 45000}]},
				],
			},
		],
	},
]


static func get_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition_variant in DEFINITIONS:
		result.append((definition_variant as Dictionary).duplicate(true))
	return result


static func get_definition(definition_id: String) -> Dictionary:
	var normalized_id := definition_id.strip_edges()
	if normalized_id.is_empty():
		return {}
	for definition_variant in DEFINITIONS:
		var definition: Dictionary = definition_variant
		if str(definition.get("id", "")) == normalized_id:
			return definition.duplicate(true)
	return {}


static func get_definition_frequency(definition_id: String) -> String:
	var definition := get_definition(definition_id)
	if definition.is_empty():
		return FREQUENCY_REPEATABLE
	return str(definition.get("frequency", FREQUENCY_REPEATABLE))


static func build_spawn_records(galaxy_seed: int, system_details_list: Array) -> Array[Dictionary]:
	var candidates_by_body: Dictionary = {}
	var once_per_game_by_definition: Dictionary = {}
	var seen_candidate_keys: Dictionary = {}

	for system_details_variant in system_details_list:
		if system_details_variant is not Dictionary:
			continue
		var system_details: Dictionary = system_details_variant
		var system_id := str(system_details.get("id", "")).strip_edges()
		if system_id.is_empty():
			continue

		for body_record in collect_anomaly_bodies(system_details):
			var component: Dictionary = ANOMALY_COMPONENT_SCRIPT.normalize_component(body_record.get(ANOMALY_COMPONENT_SCRIPT.COMPONENT_KEY, {}))
			if int(component.get("max_instances", 0)) <= 0:
				continue

			var fixed_anomaly_ids: PackedStringArray = component.get("fixed_anomaly_ids", PackedStringArray())
			if str(component.get("mode", ANOMALY_COMPONENT_SCRIPT.MODE_GENERATED)) in [ANOMALY_COMPONENT_SCRIPT.MODE_FIXED, ANOMALY_COMPONENT_SCRIPT.MODE_ADDITIVE]:
				for fixed_definition_id in fixed_anomaly_ids:
					var fixed_definition: Dictionary = get_definition(fixed_definition_id)
					if fixed_definition.is_empty() or not definition_matches_body(fixed_definition, body_record, component):
						continue
					var fixed_candidate: Dictionary = _build_candidate(galaxy_seed, system_details, body_record, fixed_definition, component, "fixed")
					_queue_candidate(fixed_candidate, candidates_by_body, once_per_game_by_definition, seen_candidate_keys)

			if str(component.get("mode", ANOMALY_COMPONENT_SCRIPT.MODE_GENERATED)) == ANOMALY_COMPONENT_SCRIPT.MODE_FIXED:
				continue

			for definition_variant in DEFINITIONS:
				var definition: Dictionary = definition_variant
				var definition_id := str(definition.get("id", ""))
				if fixed_anomaly_ids.has(definition_id):
					continue
				if not definition_matches_body(definition, body_record, component):
					continue
				var chance_bp := _resolve_spawn_chance_bp(definition, body_record, component)
				if chance_bp <= 0:
					continue
				var roll := _stable_hash("%s:%s:%s:%s:spawn_roll" % [
					galaxy_seed,
					system_id,
					str(body_record.get("id", body_record.get("name", ""))),
					definition_id,
				]) % 10000
				if roll >= chance_bp:
					continue
				var candidate: Dictionary = _build_candidate(galaxy_seed, system_details, body_record, definition, component, "generated")
				_queue_candidate(candidate, candidates_by_body, once_per_game_by_definition, seen_candidate_keys)

	for once_candidate_variant in once_per_game_by_definition.values():
		var once_candidate: Dictionary = once_candidate_variant
		_add_candidate_to_body(once_candidate, candidates_by_body)

	var records: Array[Dictionary] = []
	for body_key_variant in candidates_by_body.keys():
		var candidates: Array = candidates_by_body[body_key_variant]
		candidates.sort_custom(_sort_candidates_by_score)
		var body_max_instances := maxi(int((candidates[0] as Dictionary).get("body_max_instances", 1)), 0)
		for candidate_index in range(mini(body_max_instances, candidates.size())):
			var candidate_record: Dictionary = candidates[candidate_index]
			records.append(normalize_anomaly_record(candidate_record.get("record", {})))

	records.sort_custom(_sort_anomaly_records)
	return records


static func collect_anomaly_bodies(system_details: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for star_variant in system_details.get("stars", []):
		if star_variant is not Dictionary:
			continue
		var star: Dictionary = (star_variant as Dictionary).duplicate(true)
		star["type"] = BODY_TYPE_STAR
		result.append(star)
	for orbital_variant in system_details.get("orbitals", []):
		if orbital_variant is not Dictionary:
			continue
		result.append((orbital_variant as Dictionary).duplicate(true))
	return result


static func definition_matches_body(definition: Dictionary, body_record: Dictionary, component: Dictionary = {}) -> bool:
	var spawn: Dictionary = definition.get("spawn", {}) if definition.get("spawn", {}) is Dictionary else {}
	var body_type := resolve_body_type(body_record)
	if body_type.is_empty():
		return false

	var allowed_body_types := _variant_to_packed_string_array(spawn.get("body_types", []))
	if not allowed_body_types.is_empty() and not allowed_body_types.has(body_type):
		return false

	var required_tags := _variant_to_packed_string_array(spawn.get("required_spawn_tags", []))
	if not required_tags.is_empty():
		var component_tags: PackedStringArray = component.get("spawn_tags", PackedStringArray())
		for required_tag in required_tags:
			if not component_tags.has(required_tag):
				return false

	return true


static func normalize_anomaly_record(value: Variant) -> Dictionary:
	var source: Dictionary = value.duplicate(true) if value is Dictionary else {}
	var anomaly_id := str(source.get("anomaly_id", source.get("id", ""))).strip_edges()
	var definition_id := str(source.get("definition_id", "")).strip_edges()
	var system_id := str(source.get("system_id", "")).strip_edges()
	var body_id := str(source.get("body_id", "")).strip_edges()
	if anomaly_id.is_empty():
		anomaly_id = build_anomaly_id(system_id, body_id, definition_id)

	return {
		"anomaly_id": anomaly_id,
		"definition_id": definition_id,
		"system_id": system_id,
		"system_name": str(source.get("system_name", system_id)),
		"body_id": body_id,
		"body_type": str(source.get("body_type", "")),
		"body_name": str(source.get("body_name", body_id)),
		"spawn_seed": int(source.get("spawn_seed", _stable_hash("%s:%s:%s" % [system_id, body_id, definition_id]))),
		"spawn_source": str(source.get("spawn_source", "generated")),
		"created_day_serial": maxi(int(source.get("created_day_serial", 0)), 0),
		"state_by_empire_id": _normalize_state_map(source.get("state_by_empire_id", {})),
		"metadata": source.get("metadata", {}).duplicate(true) if source.get("metadata", {}) is Dictionary else {},
	}


static func build_manual_anomaly_record(
	galaxy_seed: int,
	definition_id: String,
	system_details: Dictionary,
	body_record: Dictionary,
	spawn_source: String = "event",
	created_day_serial: int = 0
) -> Dictionary:
	var definition: Dictionary = get_definition(definition_id)
	if definition.is_empty():
		return {}
	var component: Dictionary = ANOMALY_COMPONENT_SCRIPT.normalize_component(body_record.get(ANOMALY_COMPONENT_SCRIPT.COMPONENT_KEY, {}))
	var candidate: Dictionary = _build_candidate(galaxy_seed, system_details, body_record, definition, component, spawn_source)
	var record: Dictionary = candidate.get("record", {})
	record["created_day_serial"] = maxi(created_day_serial, 0)
	return normalize_anomaly_record(record)


static func build_anomaly_id(system_id: String, body_id: String, definition_id: String) -> String:
	return "anom_%s_%s_%s" % [_slugify(system_id), _slugify(body_id), _slugify(definition_id)]


static func build_body_key(system_id: String, body_id: String) -> String:
	return "%s:%s" % [system_id.strip_edges(), body_id.strip_edges()]


static func get_visible_anomaly_record(anomaly_record: Dictionary, empire_id: String) -> Dictionary:
	var state := get_empire_state(anomaly_record, empire_id)
	var status := str(state.get("status", STATUS_HIDDEN))
	if status == STATUS_HIDDEN:
		return {}

	var definition := get_definition(str(anomaly_record.get("definition_id", "")))
	var result := anomaly_record.duplicate(true)
	result["status"] = status
	result["title"] = str(definition.get("title", anomaly_record.get("definition_id", "Anomaly")))
	result["description"] = str(definition.get("description", ""))
	result["research_days"] = int(definition.get("research_days", 0))
	result["lore"] = str(state.get("lore", ""))
	result["outcome_summary"] = str(state.get("outcome_summary", ""))
	result["discovered_day_serial"] = int(state.get("discovered_day_serial", 0))
	result["researched_day_serial"] = int(state.get("researched_day_serial", 0))
	result["outcome"] = state.get("outcome", {}).duplicate(true) if state.get("outcome", {}) is Dictionary else {}
	return result


static func get_empire_state(anomaly_record: Dictionary, empire_id: String) -> Dictionary:
	if empire_id.strip_edges().is_empty():
		return {"status": STATUS_HIDDEN}
	var state_map: Dictionary = anomaly_record.get("state_by_empire_id", {}) if anomaly_record.get("state_by_empire_id", {}) is Dictionary else {}
	return _normalize_empire_state(state_map.get(empire_id, {}))


static func build_discovery_state(anomaly_record: Dictionary, empire_id: String, day_serial: int, source: String = "survey", discoverer_unit_id: String = "") -> Dictionary:
	var definition_id := str(anomaly_record.get("definition_id", ""))
	var lore := pick_lore(definition_id, str(anomaly_record.get("anomaly_id", "")), empire_id, int(anomaly_record.get("spawn_seed", 0)))
	return {
		"status": STATUS_DISCOVERED,
		"lore": lore,
		"discovery_source": source,
		"discoverer_unit_id": discoverer_unit_id,
		"discovered_day_serial": maxi(day_serial, 0),
		"researched_day_serial": 0,
		"outcome_summary": "",
		"outcome": {},
	}


static func build_researched_state(previous_state: Dictionary, outcome: Dictionary, outcome_summary: String, day_serial: int) -> Dictionary:
	var state := _normalize_empire_state(previous_state)
	state["status"] = STATUS_RESEARCHED
	state["researched_day_serial"] = maxi(day_serial, 0)
	state["outcome"] = outcome.duplicate(true)
	state["outcome_summary"] = outcome_summary
	return state


static func pick_lore(definition_id: String, anomaly_id: String, empire_id: String, spawn_seed: int) -> String:
	var definition := get_definition(definition_id)
	var lore_entries: Array = definition.get("discovery_lore", [])
	if lore_entries.is_empty():
		return str(definition.get("description", "Eine unbekannte Anomalie wurde entdeckt."))
	var index := _stable_hash("%s:%s:%s:%s:lore" % [spawn_seed, anomaly_id, definition_id, empire_id]) % lore_entries.size()
	return str(lore_entries[index])


static func pick_outcome(definition_id: String, anomaly_id: String, empire_id: String, spawn_seed: int) -> Dictionary:
	var definition := get_definition(definition_id)
	var outcomes: Array = definition.get("outcomes", [])
	if outcomes.is_empty():
		return {}
	return pick_weighted_entry(outcomes, "%s:%s:%s:%s:outcome" % [spawn_seed, anomaly_id, definition_id, empire_id])


static func resolve_outcome_resources(outcome: Dictionary, anomaly_record: Dictionary, empire_id: String) -> Array[Dictionary]:
	var resource_table_variant: Variant = outcome.get("resource_table", [])
	if resource_table_variant is Array and not (resource_table_variant as Array).is_empty():
		var picked := pick_weighted_entry(resource_table_variant, "%s:%s:%s:resources" % [
			int(anomaly_record.get("spawn_seed", 0)),
			str(anomaly_record.get("anomaly_id", "")),
			empire_id,
		])
		return _normalize_resource_amounts(picked.get("resources", []))
	return _normalize_resource_amounts(outcome.get("resources", []))


static func pick_weighted_entry(entries_variant: Variant, seed_key: String) -> Dictionary:
	if entries_variant is not Array:
		return {}
	var entries: Array = entries_variant
	var total_weight := 0
	for entry_variant in entries:
		if entry_variant is not Dictionary:
			continue
		total_weight += maxi(int((entry_variant as Dictionary).get("weight", 1000)), 0)
	if total_weight <= 0:
		return {}

	var roll := _stable_hash(seed_key) % total_weight
	var cursor := 0
	for entry_variant in entries:
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var weight := maxi(int(entry.get("weight", 1000)), 0)
		if weight <= 0:
			continue
		cursor += weight
		if roll < cursor:
			return entry.duplicate(true)
	return {}


static func resolve_body_type(body_record: Dictionary) -> String:
	var body_type := str(body_record.get("type", "")).strip_edges()
	if body_type.is_empty():
		var kind := str(body_record.get("kind", "")).strip_edges()
		if kind == "star" or kind == "black_hole":
			body_type = BODY_TYPE_STAR
		else:
			body_type = kind
	if body_type.is_empty() and (body_record.has("star_class") or body_record.has("color_name")):
		body_type = BODY_TYPE_STAR
	return body_type


static func _queue_candidate(candidate: Dictionary, candidates_by_body: Dictionary, once_per_game_by_definition: Dictionary, seen_candidate_keys: Dictionary) -> void:
	if candidate.is_empty():
		return
	var candidate_key := str(candidate.get("candidate_key", ""))
	if candidate_key.is_empty() or seen_candidate_keys.has(candidate_key):
		return
	seen_candidate_keys[candidate_key] = true

	var definition_id := str(candidate.get("definition_id", ""))
	var frequency := str(candidate.get("frequency", FREQUENCY_REPEATABLE))
	if frequency == FREQUENCY_ONCE_PER_GAME:
		var existing: Dictionary = once_per_game_by_definition.get(definition_id, {})
		if existing.is_empty() or int(candidate.get("score", 0)) < int(existing.get("score", 0)):
			once_per_game_by_definition[definition_id] = candidate
		return

	_add_candidate_to_body(candidate, candidates_by_body)


static func _add_candidate_to_body(candidate: Dictionary, candidates_by_body: Dictionary) -> void:
	var body_key := str(candidate.get("body_key", ""))
	if body_key.is_empty():
		return
	var body_candidates: Array = candidates_by_body.get(body_key, [])
	body_candidates.append(candidate)
	candidates_by_body[body_key] = body_candidates


static func _build_candidate(
	galaxy_seed: int,
	system_details: Dictionary,
	body_record: Dictionary,
	definition: Dictionary,
	component: Dictionary,
	spawn_source: String
) -> Dictionary:
	var system_id := str(system_details.get("id", "")).strip_edges()
	var body_type := resolve_body_type(body_record)
	var body_id := str(body_record.get("id", body_record.get("name", body_type))).strip_edges()
	var definition_id := str(definition.get("id", "")).strip_edges()
	if system_id.is_empty() or body_id.is_empty() or definition_id.is_empty():
		return {}

	var candidate_key := "%s:%s:%s" % [system_id, body_id, definition_id]
	var spawn_seed := _stable_hash("%s:%s:spawn_seed" % [galaxy_seed, candidate_key])
	var frequency := str(definition.get("frequency", FREQUENCY_REPEATABLE))
	return {
		"candidate_key": candidate_key,
		"body_key": build_body_key(system_id, body_id),
		"definition_id": definition_id,
		"frequency": frequency,
		"body_max_instances": int(component.get("max_instances", 1)),
		"score": _stable_hash("%s:%s:score" % [galaxy_seed, candidate_key]),
		"record": {
			"anomaly_id": build_anomaly_id(system_id, body_id, definition_id),
			"definition_id": definition_id,
			"system_id": system_id,
			"system_name": str(system_details.get("name", system_id)),
			"body_id": body_id,
			"body_type": body_type,
			"body_name": str(body_record.get("name", body_id)),
			"spawn_seed": spawn_seed,
			"spawn_source": spawn_source,
			"created_day_serial": 0,
			"state_by_empire_id": {},
			"metadata": {},
		},
	}


static func _resolve_spawn_chance_bp(definition: Dictionary, body_record: Dictionary, component: Dictionary) -> int:
	var spawn: Dictionary = definition.get("spawn", {}) if definition.get("spawn", {}) is Dictionary else {}
	var body_type := resolve_body_type(body_record)
	var chance_bp := int(spawn.get("chance_bp", 0))
	var chance_by_body_type: Dictionary = spawn.get("chance_by_body_type", {}) if spawn.get("chance_by_body_type", {}) is Dictionary else {}
	if chance_by_body_type.has(body_type):
		chance_bp = int(chance_by_body_type.get(body_type, chance_bp))
	var multiplier_bp := maxi(int(component.get("spawn_chance_multiplier_bp", 10000)), 0)
	return clampi(int(round(float(chance_bp) * float(multiplier_bp) / 10000.0)), 0, 10000)


static func _normalize_state_map(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if value is not Dictionary:
		return result
	var state_map: Dictionary = value
	for empire_id_variant in state_map.keys():
		var empire_id := str(empire_id_variant).strip_edges()
		if empire_id.is_empty():
			continue
		result[empire_id] = _normalize_empire_state(state_map.get(empire_id_variant, {}))
	return result


static func _normalize_empire_state(value: Variant) -> Dictionary:
	var source: Dictionary = value.duplicate(true) if value is Dictionary else {}
	var status := str(source.get("status", STATUS_HIDDEN)).strip_edges()
	match status:
		STATUS_DISCOVERED, STATUS_RESEARCHED, STATUS_HIDDEN:
			pass
		_:
			status = STATUS_HIDDEN
	return {
		"status": status,
		"lore": str(source.get("lore", "")),
		"discovery_source": str(source.get("discovery_source", "")),
		"discoverer_unit_id": str(source.get("discoverer_unit_id", "")),
		"discovered_day_serial": maxi(int(source.get("discovered_day_serial", 0)), 0),
		"researched_day_serial": maxi(int(source.get("researched_day_serial", 0)), 0),
		"outcome_summary": str(source.get("outcome_summary", "")),
		"outcome": source.get("outcome", {}).duplicate(true) if source.get("outcome", {}) is Dictionary else {},
	}


static func _normalize_resource_amounts(value: Variant) -> Array[Dictionary]:
	var raw_amounts: Array = []
	if value is Array:
		raw_amounts = value
	elif value is Dictionary:
		for resource_id_variant in (value as Dictionary).keys():
			raw_amounts.append({
				"resource_id": str(resource_id_variant),
				"milliunits": int((value as Dictionary).get(resource_id_variant, 0)),
			})
	else:
		return []

	var merged_by_resource_id: Dictionary = {}
	for amount_variant in raw_amounts:
		if amount_variant is not Dictionary:
			continue
		var amount_data: Dictionary = amount_variant
		var resource_id := str(amount_data.get("resource_id", amount_data.get("id", ""))).strip_edges()
		if resource_id.is_empty():
			continue
		var milliunits := 0
		if amount_data.has("milliunits"):
			milliunits = int(amount_data.get("milliunits", 0))
		elif amount_data.has("amount"):
			milliunits = int(round(float(amount_data.get("amount", 0.0)) * 1000.0))
		elif amount_data.has("value"):
			milliunits = int(amount_data.get("value", 0))
		if milliunits == 0:
			continue
		merged_by_resource_id[resource_id] = int(merged_by_resource_id.get(resource_id, 0)) + milliunits

	var resource_ids: Array[String] = []
	for resource_id_variant in merged_by_resource_id.keys():
		resource_ids.append(str(resource_id_variant))
	resource_ids.sort()

	var result: Array[Dictionary] = []
	for resource_id in resource_ids:
		result.append({
			"resource_id": resource_id,
			"milliunits": int(merged_by_resource_id.get(resource_id, 0)),
		})
	return result


static func _variant_to_packed_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if values is PackedStringArray:
		return values
	if values is String:
		values = [values]
	if values is not Array:
		return result
	for value_variant in values:
		var value := str(value_variant).strip_edges()
		if value.is_empty() or result.has(value):
			continue
		result.append(value)
	return result


static func _sort_candidates_by_score(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("score", 0)) == int(b.get("score", 0)):
		return str(a.get("candidate_key", "")) < str(b.get("candidate_key", ""))
	return int(a.get("score", 0)) < int(b.get("score", 0))


static func _sort_anomaly_records(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("anomaly_id", "")).nocasecmp_to(str(b.get("anomaly_id", ""))) < 0


static func _stable_hash(value: String) -> int:
	var hash_value: int = 2166136261
	var bytes := value.to_utf8_buffer()
	for byte in bytes:
		hash_value = int(((hash_value ^ int(byte)) * 16777619) & 0x7fffffff)
	return hash_value


static func _slugify(value: String) -> String:
	var source := value.to_lower().strip_edges()
	if source.is_empty():
		return "unknown"

	var result := ""
	for index in range(source.length()):
		var character := source.substr(index, 1)
		var is_letter := character >= "a" and character <= "z"
		var is_number := character >= "0" and character <= "9"
		if is_letter or is_number:
			result += character
			continue
		if result.is_empty() or result.ends_with("_"):
			continue
		result += "_"

	if result.is_empty():
		return "unknown"
	return result
