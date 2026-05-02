class_name SpeciesRuntime
extends RefCounted

var species_id: String = ""
var empire_id: String = ""
var archetype_id: String = "organic"
var species_type_id: String = "humanoid"
var species_visuals_id: String = "organic/humanoid"
var display_name: String = "Humanoid"
var species_name: String = "Humanoid"
var species_plural_name: String = "Humanoids"
var species_adjective: String = "Humanoid"
var trait_ids: PackedStringArray = PackedStringArray()


func ensure_defaults(index: int = 0) -> void:
	empire_id = empire_id.strip_edges()
	archetype_id = archetype_id.strip_edges()
	species_type_id = species_type_id.strip_edges()
	species_visuals_id = species_visuals_id.strip_edges()
	display_name = display_name.strip_edges()
	species_name = species_name.strip_edges()
	species_plural_name = species_plural_name.strip_edges()
	species_adjective = species_adjective.strip_edges()

	if archetype_id.is_empty():
		archetype_id = "organic"
	if species_type_id.is_empty():
		species_type_id = "machine" if archetype_id == "machine" else "humanoid"
	if species_visuals_id.is_empty():
		species_visuals_id = "%s/%s" % [archetype_id, species_type_id]
	if display_name.is_empty():
		display_name = _humanize_id(species_type_id)
	if species_name.is_empty():
		species_name = display_name
	if species_plural_name.is_empty():
		species_plural_name = "%ss" % species_name
	if species_adjective.is_empty():
		species_adjective = species_name

	species_id = species_id.strip_edges()
	if species_id.is_empty():
		var owner_prefix := empire_id if not empire_id.is_empty() else "unowned_%02d" % index
		species_id = "%s:%s:%s" % [owner_prefix, archetype_id, species_type_id]


func to_dict() -> Dictionary:
	ensure_defaults()
	return {
		"id": species_id,
		"empire_id": empire_id,
		"archetype_id": archetype_id,
		"species_type_id": species_type_id,
		"species_visuals_id": species_visuals_id,
		"display_name": display_name,
		"species_name": species_name,
		"species_plural_name": species_plural_name,
		"species_adjective": species_adjective,
		"trait_ids": _packed_string_array_to_array(trait_ids),
	}


static func from_dict(data: Dictionary, index: int = 0):
	var species = load("res://core/economy/SpeciesRuntime.gd").new()
	species.species_id = str(data.get("id", data.get("species_id", "")))
	species.empire_id = str(data.get("empire_id", ""))
	species.archetype_id = str(data.get("archetype_id", data.get("species_archetype_id", "organic")))
	species.species_type_id = str(data.get("species_type_id", "humanoid"))
	species.species_visuals_id = str(data.get("species_visuals_id", ""))
	species.display_name = str(data.get("display_name", data.get("species_name", "")))
	species.species_name = str(data.get("species_name", species.display_name))
	species.species_plural_name = str(data.get("species_plural_name", ""))
	species.species_adjective = str(data.get("species_adjective", ""))
	species.trait_ids = _variant_to_packed_string_array(data.get("trait_ids", []))
	species.ensure_defaults(index)
	return species


static func _variant_to_packed_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if values is PackedStringArray:
		for value in values:
			var normalized_value := str(value).strip_edges()
			if not normalized_value.is_empty() and not result.has(normalized_value):
				result.append(normalized_value)
		return result
	if values is String:
		for value in str(values).split(",", false):
			var normalized_value := str(value).strip_edges()
			if not normalized_value.is_empty() and not result.has(normalized_value):
				result.append(normalized_value)
		return result
	if values is not Array:
		return result
	for value_variant in values:
		var value := str(value_variant).strip_edges()
		if value.is_empty() or result.has(value):
			continue
		result.append(value)
	return result


static func _packed_string_array_to_array(values: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(value)
	return result


static func _humanize_id(value: String) -> String:
	var words := value.replace("_", " ").replace("-", " ").split(" ", false)
	var result := ""
	for word in words:
		if not result.is_empty():
			result += " "
		result += str(word).capitalize()
	return result
