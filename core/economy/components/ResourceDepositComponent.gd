extends RefCounted
class_name ResourceDepositComponent

const COMPONENT_KEY := "resource_deposit_component"
const MODE_GENERATED := "generated"
const MODE_FIXED := "fixed"
const MODE_ADDITIVE := "additive"
const MODE_NONE := "none"

const CONDITION_COLONIZABLE := "colonizable"
const CONDITION_BLACK_HOLE := "black_hole"
const CONDITION_SPECIAL_STAR := "special_star"

const DEPOSIT_RULES := {
	"star": [
		{"resource_id": "energy", "chance_bp": 10000, "base_milliunits": 28000, "richness_scale": 360},
		{"resource_id": "exotic_gases", "chance_bp": 1400, "base_milliunits": 2200, "richness_scale": 45, "condition": CONDITION_SPECIAL_STAR},
		{"resource_id": "dark_matter", "chance_bp": 5000, "base_milliunits": 1600, "richness_scale": 35, "condition": CONDITION_BLACK_HOLE},
	],
	"planet": [
		{"resource_id": "matter", "chance_bp": 10000, "base_milliunits": 20000, "richness_scale": 800},
		{"resource_id": "energy", "chance_bp": 8000, "base_milliunits": 5000, "richness_scale": 250},
		{"resource_id": "food", "chance_bp": 10000, "base_milliunits": 10000, "richness_scale": 180, "habitability_scale": 500, "condition": CONDITION_COLONIZABLE},
		{"resource_id": "exotic_gases", "chance_bp": 1000, "base_milliunits": 1500, "richness_scale": 80},
	],
	"asteroid_belt": [
		{"resource_id": "matter", "chance_bp": 10000, "base_milliunits": 40000, "richness_scale": 1200},
		{"resource_id": "alloys", "chance_bp": 8500, "base_milliunits": 5000, "richness_scale": 300},
		{"resource_id": "exotic_gases", "chance_bp": 1200, "base_milliunits": 1400, "richness_scale": 70},
		{"resource_id": "dark_matter", "chance_bp": 350, "base_milliunits": 600, "richness_scale": 25},
	],
	"structure": [
		{"resource_id": "energy", "chance_bp": 10000, "base_milliunits": 25000, "richness_scale": 600},
		{"resource_id": "alloys", "chance_bp": 7000, "base_milliunits": 2500, "richness_scale": 120},
		{"resource_id": "living_metal", "chance_bp": 500, "base_milliunits": 800, "richness_scale": 35},
		{"resource_id": "dark_matter", "chance_bp": 250, "base_milliunits": 600, "richness_scale": 25},
	],
	"ruin": [
		{"resource_id": "matter", "chance_bp": 8500, "base_milliunits": 10000, "richness_scale": 400},
		{"resource_id": "energy", "chance_bp": 8000, "base_milliunits": 5000, "richness_scale": 300},
		{"resource_id": "alloys", "chance_bp": 3000, "base_milliunits": 1800, "richness_scale": 100},
		{"resource_id": "exotic_gases", "chance_bp": 1000, "base_milliunits": 1200, "richness_scale": 60},
		{"resource_id": "living_metal", "chance_bp": 700, "base_milliunits": 700, "richness_scale": 30},
		{"resource_id": "dark_matter", "chance_bp": 500, "base_milliunits": 500, "richness_scale": 22},
	],
}


static func normalize_component(value: Variant) -> Dictionary:
	var source: Dictionary = value.duplicate(true) if value is Dictionary else {}
	var mode := str(source.get("mode", MODE_GENERATED)).strip_edges().to_lower()
	match mode:
		MODE_FIXED, MODE_ADDITIVE, MODE_NONE, MODE_GENERATED:
			pass
		_:
			mode = MODE_GENERATED

	return {
		"mode": mode,
		"deposits": normalize_deposit_amounts(source.get("deposits", [])),
	}


static func normalize_deposit_amounts(value: Variant, valid_resource_ids: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
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
		if not valid_resource_ids.is_empty() and not valid_resource_ids.has(resource_id):
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

	return _amount_map_to_sorted_array(merged_by_resource_id, valid_resource_ids)


static func resolve_deposit_amounts(
	galaxy_seed: int,
	system_id: String,
	body_record: Dictionary,
	valid_resource_ids: PackedStringArray = PackedStringArray()
) -> Array[Dictionary]:
	if body_record.is_empty():
		return []

	var component := normalize_component(body_record.get(COMPONENT_KEY, {}))
	var mode := str(component.get("mode", MODE_GENERATED))
	if mode == MODE_NONE:
		return []

	var merged_by_resource_id: Dictionary = {}
	if mode != MODE_FIXED:
		for generated_amount in _build_generated_deposit_amounts(galaxy_seed, system_id, body_record, valid_resource_ids):
			merged_by_resource_id[str(generated_amount.get("resource_id", ""))] = int(generated_amount.get("milliunits", 0))

	if mode == MODE_FIXED or mode == MODE_ADDITIVE:
		for fixed_amount in normalize_deposit_amounts(component.get("deposits", []), valid_resource_ids):
			var resource_id := str(fixed_amount.get("resource_id", ""))
			merged_by_resource_id[resource_id] = int(merged_by_resource_id.get(resource_id, 0)) + int(fixed_amount.get("milliunits", 0))

	return _amount_map_to_sorted_array(merged_by_resource_id, valid_resource_ids)


static func has_deposits(
	galaxy_seed: int,
	system_id: String,
	body_record: Dictionary,
	valid_resource_ids: PackedStringArray = PackedStringArray()
) -> bool:
	return not resolve_deposit_amounts(galaxy_seed, system_id, body_record, valid_resource_ids).is_empty()


static func _build_generated_deposit_amounts(
	galaxy_seed: int,
	system_id: String,
	body_record: Dictionary,
	valid_resource_ids: PackedStringArray
) -> Array[Dictionary]:
	var body_type := _resolve_body_type(body_record)
	if body_type.is_empty() or not DEPOSIT_RULES.has(body_type):
		return []

	var body_id := str(body_record.get("id", body_record.get("name", body_type))).strip_edges()
	if body_id.is_empty():
		return []

	var richness_points := _resolve_points(body_record, "resource_richness_points", "resource_richness", 50)
	var habitability_points := _resolve_points(body_record, "habitability_points", "habitability", 0)
	var result: Array[Dictionary] = []
	var rules: Array = DEPOSIT_RULES.get(body_type, [])
	for rule_variant in rules:
		var rule: Dictionary = rule_variant
		var resource_id := str(rule.get("resource_id", "")).strip_edges()
		if resource_id.is_empty():
			continue
		if not valid_resource_ids.is_empty() and not valid_resource_ids.has(resource_id):
			continue
		if not _rule_matches_body(rule, body_record, habitability_points):
			continue

		var chance_bp := clampi(int(rule.get("chance_bp", 10000)), 0, 10000)
		if chance_bp <= 0:
			continue
		if chance_bp < 10000:
			var roll := _stable_hash("%s:%s:%s:%s:%s" % [galaxy_seed, system_id, body_id, body_type, resource_id]) % 10000
			if roll >= chance_bp:
				continue

		var milliunits := int(rule.get("base_milliunits", 0))
		milliunits += richness_points * int(rule.get("richness_scale", 0))
		milliunits += habitability_points * int(rule.get("habitability_scale", 0))
		if milliunits <= 0:
			continue
		result.append({
			"resource_id": resource_id,
			"milliunits": milliunits,
		})

	return normalize_deposit_amounts(result, valid_resource_ids)


static func _rule_matches_body(rule: Dictionary, body_record: Dictionary, habitability_points: int) -> bool:
	var condition := str(rule.get("condition", "")).strip_edges()
	if condition.is_empty():
		return true
	match condition:
		CONDITION_COLONIZABLE:
			return bool(body_record.get("is_colonizable", false)) or habitability_points >= 45
		CONDITION_BLACK_HOLE:
			return _is_black_hole(body_record)
		CONDITION_SPECIAL_STAR:
			return _is_black_hole(body_record) or str(body_record.get("special_type", "none")) != "none"
		_:
			return true


static func _resolve_body_type(body_record: Dictionary) -> String:
	var body_type := str(body_record.get("type", "")).strip_edges()
	if body_type.is_empty():
		var kind := str(body_record.get("kind", "")).strip_edges()
		if kind == "star" or kind == "black_hole":
			body_type = "star"
		else:
			body_type = kind
	return body_type


static func _is_black_hole(body_record: Dictionary) -> bool:
	return str(body_record.get("kind", "")) == "black_hole" or str(body_record.get("special_type", "")) == "Black hole"


static func _resolve_points(record: Dictionary, points_key: String, fraction_key: String, default_points: int) -> int:
	if record.has(points_key):
		return clampi(int(record.get(points_key, default_points)), 0, 100)
	if record.has(fraction_key):
		return clampi(int(round(clampf(float(record.get(fraction_key, float(default_points) / 100.0)), 0.0, 1.0) * 100.0)), 0, 100)
	return clampi(default_points, 0, 100)


static func _amount_map_to_sorted_array(amount_map: Dictionary, valid_resource_ids: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var resource_ids: Array[String] = []
	for resource_id_variant in amount_map.keys():
		var resource_id := str(resource_id_variant).strip_edges()
		if resource_id.is_empty():
			continue
		if not valid_resource_ids.is_empty() and not valid_resource_ids.has(resource_id):
			continue
		if int(amount_map.get(resource_id_variant, 0)) == 0:
			continue
		resource_ids.append(resource_id)
	resource_ids.sort()

	var result: Array[Dictionary] = []
	for resource_id in resource_ids:
		result.append({
			"resource_id": resource_id,
			"milliunits": int(amount_map.get(resource_id, 0)),
		})
	return result


static func _stable_hash(value: String) -> int:
	var hash_value: int = 2166136261
	var bytes := value.to_utf8_buffer()
	for byte in bytes:
		hash_value = int(((hash_value ^ int(byte)) * 16777619) & 0x7fffffff)
	return hash_value
