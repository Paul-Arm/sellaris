extends Node

const EMPIRE_PRESET_SCRIPT := preload("res://core/empire/EmpirePreset.gd")
const PRESET_DIRECTORY := "user://empire_presets"
const PRESET_EXTENSION := ".json"

var _presets: Array[EmpirePreset] = []


func _ready() -> void:
	load_presets()


func load_presets() -> Array[EmpirePreset]:
	_presets.clear()
	_ensure_preset_directory()

	var directory := DirAccess.open(PRESET_DIRECTORY)
	if directory == null:
		return get_presets()

	directory.list_dir_begin()
	while true:
		var file_name := directory.get_next()
		if file_name.is_empty():
			break
		if directory.current_is_dir() or not file_name.ends_with(PRESET_EXTENSION):
			continue

		var preset_path := PRESET_DIRECTORY.path_join(file_name)
		var parsed_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(preset_path))
		if parsed_value is not Dictionary:
			push_warning("Skipping invalid empire preset file: %s" % preset_path)
			continue

		var preset := EMPIRE_PRESET_SCRIPT.from_dict(parsed_value)
		if preset.preset_name.is_empty():
			preset.preset_name = file_name.trim_suffix(PRESET_EXTENSION)
			preset.ensure_defaults()
		_presets.append(preset)

	directory.list_dir_end()
	_sort_presets()
	return get_presets()


func get_presets() -> Array[EmpirePreset]:
	var result: Array[EmpirePreset] = []
	result.append_array(_presets)
	return result


func get_preset_count() -> int:
	return _presets.size()


func get_preset_by_name(preset_name: String) -> EmpirePreset:
	for preset in _presets:
		if preset.preset_name == preset_name:
			return _clone_preset(preset)
	return null


func save_preset(preset: EmpirePreset, previous_preset_name: String = "") -> Error:
	if preset == null:
		return ERR_INVALID_PARAMETER

	var normalized_preset := _clone_preset(preset)
	normalized_preset.ensure_defaults()
	normalized_preset.preset_name = _make_unique_preset_name(normalized_preset.preset_name, previous_preset_name)
	normalized_preset.ensure_defaults()

	_ensure_preset_directory()
	var previous_path := _get_preset_path(previous_preset_name)
	var next_path := _get_preset_path(normalized_preset.preset_name)
	var file := FileAccess.open(next_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(normalized_preset.to_dict(), "\t"))
	file.close()

	if not previous_preset_name.is_empty() and previous_preset_name != normalized_preset.preset_name and FileAccess.file_exists(previous_path):
		DirAccess.remove_absolute(previous_path)

	_upsert_cached_preset(normalized_preset, previous_preset_name)
	preset.preset_name = normalized_preset.preset_name
	preset.empire_name = normalized_preset.empire_name
	return OK


func delete_preset(preset_name: String) -> Error:
	if preset_name.is_empty():
		return ERR_INVALID_PARAMETER

	var preset_path := _get_preset_path(preset_name)
	if FileAccess.file_exists(preset_path):
		var remove_error := DirAccess.remove_absolute(preset_path)
		if remove_error != OK:
			return remove_error

	for preset_index in range(_presets.size()):
		if _presets[preset_index].preset_name != preset_name:
			continue
		_presets.remove_at(preset_index)
		break

	return OK


func build_galaxy_empire_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for preset_index in range(_presets.size()):
		var preset := _presets[preset_index]
		preset.ensure_defaults()
		records.append({
			"id": _build_runtime_empire_id(preset, preset_index),
			"name": preset.empire_name,
			"color": preset.color,
			"controller_kind": "unassigned",
			"controller_peer_id": 0,
			"is_local_player": false,
			"ai_profile": "",
			"player_slot": preset_index,
			"home_system_id": "",
			"preset_name": preset.preset_name,
			"flag_path": preset.flag_path,
			"biography": preset.biography,
			"species_name": preset.species_name,
			"species_plural_name": preset.species_plural_name,
			"species_adjective": preset.species_adjective,
			"preset_data": preset.to_dict(),
		})
	return records


func _ensure_preset_directory() -> void:
	DirAccess.make_dir_recursive_absolute(PRESET_DIRECTORY)


func _sort_presets() -> void:
	_presets.sort_custom(_sort_preset_names)


func _upsert_cached_preset(preset: EmpirePreset, previous_preset_name: String) -> void:
	for preset_index in range(_presets.size()):
		var existing_preset := _presets[preset_index]
		if existing_preset.preset_name != previous_preset_name and existing_preset.preset_name != preset.preset_name:
			continue
		_presets[preset_index] = preset
		_sort_presets()
		return

	_presets.append(preset)
	_sort_presets()


func _make_unique_preset_name(requested_name: String, previous_preset_name: String = "") -> String:
	var base_name := requested_name.strip_edges()
	if base_name.is_empty():
		base_name = "Empire Preset"

	var taken_names: Dictionary = {}
	for preset in _presets:
		if not previous_preset_name.is_empty() and preset.preset_name == previous_preset_name:
			continue
		taken_names[preset.preset_name.to_lower()] = true

	if not taken_names.has(base_name.to_lower()):
		return base_name

	var suffix := 2
	while true:
		var candidate := "%s %d" % [base_name, suffix]
		if not taken_names.has(candidate.to_lower()):
			return candidate
		suffix += 1
	return base_name


func _get_preset_path(preset_name: String) -> String:
	return PRESET_DIRECTORY.path_join("%s%s" % [_sanitize_file_name(preset_name), PRESET_EXTENSION])


func _sanitize_file_name(value: String) -> String:
	var source := value.to_lower().strip_edges()
	if source.is_empty():
		return "empire_preset"

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
		return "empire_preset"
	return result


func _build_runtime_empire_id(preset: EmpirePreset, preset_index: int) -> String:
	return "preset_%s_%02d" % [_sanitize_file_name(preset.preset_name), preset_index]


func _clone_preset(preset: EmpirePreset) -> EmpirePreset:
	return EMPIRE_PRESET_SCRIPT.from_dict(preset.to_dict())


func _sort_preset_names(a: EmpirePreset, b: EmpirePreset) -> bool:
	return a.preset_name.naturalnocasecmp_to(b.preset_name) < 0
