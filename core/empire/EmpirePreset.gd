class_name EmpirePreset
extends RefCounted

const DEFAULT_COLOR := Color(0.36, 0.72, 1.0, 1.0)

var preset_name: String = ""
var empire_name: String = ""

# species
var species_archetype_id: StringName = &"organic"
var species_type_id: StringName = &""
var species_visuals_id: StringName = &""

# names
var species_name: String = ""
var species_plural_name: String = ""
var species_adjective: String = ""
var name_set_id: StringName = &""

# governance
var government_type_id: StringName = &""
var authority_type_id: StringName = &""
var civic_ids: Array[StringName] = []

# customization
var flag_path: String = ""
var biography: String = ""
var color: Color = DEFAULT_COLOR
var ship_set_id: int = 0
var menu_portrait_path: String = ""
var leader_portrait_paths: Array[String] = []

# origin
var origin_id: StringName = &""
var starting_system_type: StringName = &""
var starting_planet_type: StringName = &""


func ensure_defaults() -> void:
	preset_name = preset_name.strip_edges()
	empire_name = empire_name.strip_edges()
	species_name = species_name.strip_edges()
	species_plural_name = species_plural_name.strip_edges()
	species_adjective = species_adjective.strip_edges()
	flag_path = flag_path.strip_edges()
	biography = biography.strip_edges()
	menu_portrait_path = menu_portrait_path.strip_edges()
	leader_portrait_paths = _normalize_string_array(leader_portrait_paths)

	if preset_name.is_empty():
		preset_name = empire_name
	if empire_name.is_empty():
		empire_name = preset_name
	if preset_name.is_empty():
		preset_name = "Empire Preset"
	if empire_name.is_empty():
		empire_name = "Unnamed Empire"
	if species_name.is_empty():
		species_name = empire_name
	if species_plural_name.is_empty():
		species_plural_name = "%ss" % species_name
	if species_adjective.is_empty():
		species_adjective = species_name
	if str(species_archetype_id).strip_edges().is_empty():
		species_archetype_id = &"organic"
	if str(species_type_id).strip_edges().is_empty():
		species_type_id = &"machine" if species_archetype_id == &"machine" else &"humanoid"
	if str(species_visuals_id).strip_edges().is_empty():
		species_visuals_id = StringName("%s/%s" % [str(species_archetype_id), str(species_type_id)])
	if menu_portrait_path.is_empty() and not leader_portrait_paths.is_empty():
		menu_portrait_path = leader_portrait_paths[0]
	if leader_portrait_paths.is_empty() and not menu_portrait_path.is_empty():
		leader_portrait_paths.append(menu_portrait_path)


func to_dict() -> Dictionary:
	ensure_defaults()
	return {
		"preset_name": preset_name,
		"empire_name": empire_name,
		"species_archetype_id": str(species_archetype_id),
		"species_type_id": str(species_type_id),
		"species_visuals_id": str(species_visuals_id),
		"species_name": species_name,
		"species_plural_name": species_plural_name,
		"species_adjective": species_adjective,
		"name_set_id": str(name_set_id),
		"government_type_id": str(government_type_id),
		"authority_type_id": str(authority_type_id),
		"civic_ids": _stringify_string_name_array(civic_ids),
		"flag_path": flag_path,
		"biography": biography,
		"color": _color_to_dict(color),
		"ship_set_id": ship_set_id,
		"menu_portrait_path": menu_portrait_path,
		"leader_portrait_paths": leader_portrait_paths.duplicate(),
		"origin_id": str(origin_id),
		"starting_system_type": str(starting_system_type),
		"starting_planet_type": str(starting_planet_type),
	}


static func from_dict(data: Dictionary) -> EmpirePreset:
	var preset := EmpirePreset.new()

	preset.preset_name = str(data.get("preset_name", ""))
	preset.empire_name = str(data.get("empire_name", ""))
	preset.species_archetype_id = StringName(str(data.get("species_archetype_id", "organic")))
	preset.species_type_id = StringName(str(data.get("species_type_id", "")))
	preset.species_visuals_id = StringName(str(data.get("species_visuals_id", "")))
	preset.species_name = str(data.get("species_name", ""))
	preset.species_plural_name = str(data.get("species_plural_name", ""))
	preset.species_adjective = str(data.get("species_adjective", ""))
	preset.name_set_id = StringName(str(data.get("name_set_id", "")))
	preset.government_type_id = StringName(str(data.get("government_type_id", "")))
	preset.authority_type_id = StringName(str(data.get("authority_type_id", "")))
	preset.civic_ids = _parse_string_name_array(data.get("civic_ids", []))
	preset.flag_path = str(data.get("flag_path", ""))
	preset.biography = str(data.get("biography", ""))
	preset.color = _parse_color(data.get("color", {}))
	preset.ship_set_id = int(data.get("ship_set_id", 0))
	preset.menu_portrait_path = str(data.get("menu_portrait_path", ""))
	preset.leader_portrait_paths = _parse_string_array(data.get("leader_portrait_paths", []))
	preset.origin_id = StringName(str(data.get("origin_id", "")))
	preset.starting_system_type = StringName(str(data.get("starting_system_type", "")))
	preset.starting_planet_type = StringName(str(data.get("starting_planet_type", "")))
	preset.ensure_defaults()

	return preset


static func _parse_color(color_data: Variant) -> Color:
	if color_data is Color:
		return color_data
	if color_data is Dictionary:
		return Color(
			float(color_data.get("r", DEFAULT_COLOR.r)),
			float(color_data.get("g", DEFAULT_COLOR.g)),
			float(color_data.get("b", DEFAULT_COLOR.b)),
			float(color_data.get("a", DEFAULT_COLOR.a))
		)
	if color_data is String and not String(color_data).is_empty():
		return Color.from_string(String(color_data), DEFAULT_COLOR)
	return DEFAULT_COLOR


static func _parse_string_name_array(values: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if values is not Array:
		return result

	for value in values:
		var text := str(value).strip_edges()
		if text.is_empty():
			continue
		result.append(StringName(text))
	return result


static func _parse_string_array(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is not Array:
		return result

	for value in values:
		var text := str(value).strip_edges()
		if text.is_empty():
			continue
		result.append(text)
	return result


static func _color_to_dict(value: Color) -> Dictionary:
	return {
		"r": value.r,
		"g": value.g,
		"b": value.b,
		"a": value.a,
	}


func _stringify_string_name_array(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := str(value).strip_edges()
		if text.is_empty():
			continue
		result.append(text)
	return result


func _normalize_string_array(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := value.strip_edges()
		if text.is_empty():
			continue
		if result.has(text):
			continue
		result.append(text)
	return result
