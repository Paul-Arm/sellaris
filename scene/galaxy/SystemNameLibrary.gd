extends RefCounted
class_name SystemNameLibrary

const NAMES_CONFIG_PATH := "res://scene/galaxy/system_names.cfg"
const DEFAULT_GROUP_ORDER := ["real", "homage", "original"]
const NAME_STARTS := [
	"Ach",
	"Ad",
	"Al",
	"An",
	"Ar",
	"Ash",
	"Ba",
	"Bel",
	"Bor",
	"Ca",
	"Cel",
	"Cor",
	"Da",
	"Dar",
	"Den",
	"Dur",
	"El",
	"Esh",
	"Fa",
	"Fer",
	"Gan",
	"Har",
	"Ir",
	"Jor",
	"Ka",
	"Kel",
	"Kir",
	"Lor",
	"Ma",
	"Mer",
	"Nal",
	"Nor",
	"Or",
	"Pel",
	"Qir",
	"Ra",
	"Ril",
	"Sa",
	"Sel",
	"Tar",
	"Tor",
	"Ul",
	"Va",
	"Vor",
	"Xan",
	"Yir",
	"Za",
	"Zel",
]
const NAME_MIDDLES := [
	"bar",
	"bel",
	"car",
	"cor",
	"dath",
	"del",
	"drin",
	"far",
	"gath",
	"gor",
	"hal",
	"ian",
	"ish",
	"kar",
	"kel",
	"len",
	"lor",
	"mar",
	"mir",
	"nar",
	"nel",
	"or",
	"ra",
	"ran",
	"ren",
	"shal",
	"tar",
	"thel",
	"tor",
	"val",
	"ven",
	"vor",
	"zar",
]
const NAME_ENDS := [
	"a",
	"ac",
	"ach",
	"ad",
	"ak",
	"al",
	"an",
	"ar",
	"as",
	"ath",
	"ea",
	"ek",
	"el",
	"em",
	"en",
	"er",
	"esh",
	"ia",
	"im",
	"in",
	"ion",
	"is",
	"ith",
	"on",
	"or",
	"os",
	"oth",
	"um",
	"us",
]
const NAME_COMPOUND_SUFFIXES := [
	"Anvil",
	"Arc",
	"Drift",
	"Gate",
	"Haven",
	"Nexus",
	"Reach",
	"Rift",
	"Run",
	"Shard",
	"Spire",
	"Vale",
	"Veil",
	"Ward",
]

var _cached_names: PackedStringArray = PackedStringArray()
var _did_load_names: bool = false


func get_system_name(galaxy_seed: int, system_index: int, used_names: Dictionary = {}) -> String:
	var names := _get_names()
	if names.is_empty():
		return _claim_fallback_name(system_index, used_names)

	var start_index := _positive_hash("%s:%s:name" % [galaxy_seed, system_index]) % names.size()
	var stride := _build_stride(galaxy_seed, system_index, names.size())
	for offset in range(names.size()):
		var candidate := names[(start_index + offset * stride) % names.size()]
		if _try_claim_name(candidate, used_names):
			return candidate

	for attempt in range(0, 5000):
		var candidate := _build_generated_name(galaxy_seed, system_index, attempt)
		if _try_claim_name(candidate, used_names):
			return candidate

	var base_name := names[start_index]
	for suffix_index in range(2, 10000):
		var candidate := "%s %s" % [base_name, _to_roman(suffix_index)]
		if _try_claim_name(candidate, used_names):
			return candidate

	return _claim_fallback_name(system_index, used_names)


func _get_names() -> PackedStringArray:
	if _did_load_names:
		return _cached_names

	_did_load_names = true
	var config := ConfigFile.new()
	var error := config.load(NAMES_CONFIG_PATH)
	if error != OK:
		_cached_names = _build_builtin_fallback_names()
		return _cached_names

	var seen_names: Dictionary = {}
	for group_name in _get_ordered_sections(config):
		var names_variant: Variant = config.get_value(group_name, "names", [])
		for name_variant in _variant_to_name_array(names_variant):
			var name := str(name_variant).strip_edges()
			var normalized_name := name.to_lower()
			if name.is_empty() or seen_names.has(normalized_name):
				continue
			seen_names[normalized_name] = true
			_cached_names.append(name)

	if _cached_names.is_empty():
		_cached_names = _build_builtin_fallback_names()
	return _cached_names


func _variant_to_name_array(names_variant: Variant) -> Array:
	if names_variant is PackedStringArray:
		var names: Array = []
		for name in names_variant:
			names.append(name)
		return names
	if names_variant is Array:
		return names_variant
	return []


func _get_ordered_sections(config: ConfigFile) -> PackedStringArray:
	var sections := PackedStringArray()
	for group_name in DEFAULT_GROUP_ORDER:
		if config.has_section(group_name):
			sections.append(group_name)

	for section_name in config.get_sections():
		if sections.has(section_name):
			continue
		sections.append(section_name)
	return sections


func _try_claim_name(candidate: String, used_names: Dictionary) -> bool:
	var normalized_candidate := candidate.strip_edges()
	if normalized_candidate.is_empty():
		return false
	var key := normalized_candidate.to_lower()
	if used_names.has(key):
		return false
	used_names[key] = true
	return true


func _build_generated_name(galaxy_seed: int, system_index: int, attempt: int) -> String:
	var name_seed := "%s:%s:%s:generated-name" % [galaxy_seed, system_index, attempt]
	var start: String = str(NAME_STARTS[_positive_hash("%s:start" % name_seed) % NAME_STARTS.size()])
	var middle: String = str(NAME_MIDDLES[_positive_hash("%s:middle" % name_seed) % NAME_MIDDLES.size()])
	var ending: String = str(NAME_ENDS[_positive_hash("%s:end" % name_seed) % NAME_ENDS.size()])
	var second_middle := ""
	if _positive_hash("%s:shape" % name_seed) % 100 < 34:
		second_middle = str(NAME_MIDDLES[_positive_hash("%s:second" % name_seed) % NAME_MIDDLES.size()])

	var base_name := "%s%s%s%s" % [start, middle, second_middle, ending]
	base_name = _clean_generated_name(base_name)

	if _positive_hash("%s:compound" % name_seed) % 100 < 12:
		var suffix: String = str(NAME_COMPOUND_SUFFIXES[_positive_hash("%s:suffix" % name_seed) % NAME_COMPOUND_SUFFIXES.size()])
		return "%s %s" % [base_name, suffix]

	return base_name


func _clean_generated_name(value: String) -> String:
	var result := value.strip_edges()
	while result.contains("aa"):
		result = result.replace("aa", "a")
	while result.contains("ee"):
		result = result.replace("ee", "e")
	while result.contains("ii"):
		result = result.replace("ii", "i")
	while result.contains("oo"):
		result = result.replace("oo", "o")
	while result.contains("uu"):
		result = result.replace("uu", "u")
	return result.capitalize().replace(" ", "")


func _claim_fallback_name(system_index: int, used_names: Dictionary) -> String:
	for suffix_index in range(system_index + 1, system_index + 10000):
		var candidate := "Aster %s" % _to_roman(suffix_index)
		if _try_claim_name(candidate, used_names):
			return candidate
	return "Aster %04d" % (system_index + 1)


func _build_stride(galaxy_seed: int, system_index: int, name_count: int) -> int:
	if name_count <= 1:
		return 1
	var stride := 1 + (_positive_hash("%s:%s:stride" % [galaxy_seed, system_index]) % maxi(name_count - 1, 1))
	while _greatest_common_divisor(stride, name_count) != 1:
		stride += 1
		if stride >= name_count:
			stride = 1
	return stride


func _greatest_common_divisor(a: int, b: int) -> int:
	a = absi(a)
	b = absi(b)
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return maxi(a, 1)


func _positive_hash(value: String) -> int:
	return absi(value.hash())


func _build_builtin_fallback_names() -> PackedStringArray:
	return PackedStringArray([
		"Aurelian",
		"Celestine",
		"Dawnmere",
		"Echovar",
		"Farspring",
		"Glasshaven",
		"Lumenfall",
		"Orison",
		"Praxis",
		"Vespera",
	])


func _to_roman(value: int) -> String:
	var remaining := maxi(value, 1)
	var numerals := [
		{"value": 1000, "symbol": "M"},
		{"value": 900, "symbol": "CM"},
		{"value": 500, "symbol": "D"},
		{"value": 400, "symbol": "CD"},
		{"value": 100, "symbol": "C"},
		{"value": 90, "symbol": "XC"},
		{"value": 50, "symbol": "L"},
		{"value": 40, "symbol": "XL"},
		{"value": 10, "symbol": "X"},
		{"value": 9, "symbol": "IX"},
		{"value": 5, "symbol": "V"},
		{"value": 4, "symbol": "IV"},
		{"value": 1, "symbol": "I"},
	]
	var result := ""
	for numeral_variant in numerals:
		var numeral: Dictionary = numeral_variant
		var numeral_value: int = numeral["value"]
		while remaining >= numeral_value:
			result += str(numeral["symbol"])
			remaining -= numeral_value
	return result
