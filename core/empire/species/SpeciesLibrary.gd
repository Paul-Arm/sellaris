class_name SpeciesLibrary
extends RefCounted

const SPECIES_ROOT := "res://core/empire/species"
const SPECIES_CONFIG_FILE := "species.cfg"
const MENU_PORTRAIT_FILE_NAMES := ["menu_portrait", "portrait", "menu"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg"]


static func load_catalog() -> Dictionary:
	var catalog: Dictionary = {}
	for archetype_id in _list_directories(SPECIES_ROOT):
		var archetype_path := SPECIES_ROOT.path_join(archetype_id)
		var species_entries: Array[Dictionary] = []
		for species_type_id in _list_directories(archetype_path):
			species_entries.append(_load_species_entry(archetype_id, species_type_id))

		if species_entries.is_empty():
			continue
		species_entries.sort_custom(_sort_species_entries)
		catalog[archetype_id] = {
			"id": archetype_id,
			"display_name": _humanize_id(archetype_id),
			"species": species_entries,
		}

	return catalog


static func get_archetype_entries(catalog: Dictionary) -> Array[Dictionary]:
	var archetypes: Array[Dictionary] = []
	for archetype_id in catalog.keys():
		var entry: Variant = catalog[archetype_id]
		if entry is Dictionary:
			archetypes.append(entry)
	archetypes.sort_custom(_sort_species_entries)
	return archetypes


static func get_species_entries(catalog: Dictionary, archetype_id: String) -> Array[Dictionary]:
	var archetype_entry: Variant = catalog.get(archetype_id, {})
	if archetype_entry is not Dictionary:
		return []

	var results: Array[Dictionary] = []
	var species_values: Variant = archetype_entry.get("species", [])
	if species_values is Array:
		for species_value in species_values:
			if species_value is Dictionary:
				results.append(species_value)
	return results


static func get_species_entry(catalog: Dictionary, archetype_id: String, species_type_id: String) -> Dictionary:
	for species_entry in get_species_entries(catalog, archetype_id):
		if str(species_entry.get("species_type_id", "")) == species_type_id:
			return species_entry
	return {}


static func _load_species_entry(archetype_id: String, species_type_id: String) -> Dictionary:
	var species_path := SPECIES_ROOT.path_join(archetype_id).path_join(species_type_id)
	var config := ConfigFile.new()
	config.load(species_path.path_join(SPECIES_CONFIG_FILE))

	var display_name := str(config.get_value("species", "display_name", _humanize_id(species_type_id))).strip_edges()
	var species_name := str(config.get_value("species", "species_name", display_name)).strip_edges()
	var species_plural_name := str(config.get_value("species", "species_plural_name", "%ss" % species_name)).strip_edges()
	var species_adjective := str(config.get_value("species", "species_adjective", species_name)).strip_edges()
	var species_visuals_id := str(config.get_value("species", "species_visuals_id", "%s/%s" % [archetype_id, species_type_id])).strip_edges()
	var name_set_id := str(config.get_value("species", "name_set_id", "")).strip_edges()
	var trait_ids := _normalize_string_values(config.get_value("traits", "ids", []))

	var menu_portrait_path := _resolve_relative_file_path(species_path, str(config.get_value("species", "menu_portrait", "")).strip_edges())
	if menu_portrait_path.is_empty():
		menu_portrait_path = _find_menu_portrait(species_path)

	var leader_portrait_paths := _list_image_paths(species_path.path_join("leaders"))
	if leader_portrait_paths.is_empty() and not menu_portrait_path.is_empty():
		leader_portrait_paths.append(menu_portrait_path)

	return {
		"archetype_id": archetype_id,
		"species_type_id": species_type_id,
		"display_name": display_name,
		"species_name": species_name,
		"species_plural_name": species_plural_name,
		"species_adjective": species_adjective,
		"species_visuals_id": species_visuals_id,
		"name_set_id": name_set_id,
		"trait_ids": trait_ids,
		"folder_path": species_path,
		"menu_portrait_path": menu_portrait_path,
		"leader_portrait_paths": leader_portrait_paths,
	}


static func _resolve_relative_file_path(base_path: String, relative_path: String) -> String:
	if relative_path.is_empty():
		return ""
	if relative_path.begins_with("res://") or relative_path.begins_with("user://"):
		return relative_path
	return base_path.path_join(relative_path)


static func _find_menu_portrait(species_path: String) -> String:
	var menu_subfolder := species_path.path_join("menu")
	var menu_images: Array[String] = _list_image_paths(menu_subfolder)
	if not menu_images.is_empty():
		return menu_images[0]

	var files: Array[String] = _list_files(species_path)
	for file_name in files:
		var lowercase_name := file_name.to_lower()
		for candidate in MENU_PORTRAIT_FILE_NAMES:
			if lowercase_name.begins_with(candidate + "."):
				return species_path.path_join(file_name)
	return ""


static func _list_directories(path: String) -> Array[String]:
	var results: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return results

	directory.list_dir_begin()
	while true:
		var entry_name := directory.get_next()
		if entry_name.is_empty():
			break
		if entry_name.begins_with("."):
			continue
		if not directory.current_is_dir():
			continue
		results.append(entry_name)
	directory.list_dir_end()
	results.sort()
	return results


static func _list_files(path: String) -> Array[String]:
	var results: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return results

	directory.list_dir_begin()
	while true:
		var entry_name := directory.get_next()
		if entry_name.is_empty():
			break
		if entry_name.begins_with(".") or directory.current_is_dir():
			continue
		results.append(entry_name)
	directory.list_dir_end()
	results.sort()
	return results


static func _list_image_paths(path: String) -> Array[String]:
	var results: Array[String] = []
	for file_name in _list_files(path):
		var extension := file_name.get_extension().to_lower()
		if not IMAGE_EXTENSIONS.has(extension):
			continue
		results.append(path.path_join(file_name))
	return results


static func _normalize_string_values(values: Variant) -> PackedStringArray:
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


static func _humanize_id(value: String) -> String:
	var words := value.replace("_", " ").replace("-", " ").split(" ", false)
	var result := ""
	for word in words:
		if not result.is_empty():
			result += " "
		result += str(word).capitalize()
	return result


static func _sort_species_entries(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("display_name", "")).naturalnocasecmp_to(str(b.get("display_name", ""))) < 0
