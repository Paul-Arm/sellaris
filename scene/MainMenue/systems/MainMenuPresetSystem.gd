extends RefCounted

const DEFAULT_EDITOR_COLOR := Color(0.36, 0.72, 1.0, 1.0)

var _host: Control = null


func bind(host: Control) -> void:
	_host = host


func unbind() -> void:
	_host = null


func open_delete_overlay() -> void:
	if _host._selected_preset_name.is_empty():
		return
	_host.delete_confirm_label.text = "Delete '%s' permanently from disk?" % _host._selected_preset_name
	_host.delete_overlay.visible = true


func close_delete_overlay() -> void:
	_host.delete_overlay.visible = false


func refresh_preset_list(selected_name: String = "") -> void:
	EmpirePresetManager.load_presets()
	_host.preset_list.clear()

	var presets: Array[EmpirePreset] = EmpirePresetManager.get_presets()
	for preset in presets:
		_host.preset_list.add_item("%s  |  %s" % [preset.preset_name, preset.empire_name])
		var item_index: int = _host.preset_list.get_item_count() - 1
		_host.preset_list.set_item_metadata(item_index, preset.preset_name)
		_host.preset_list.set_item_custom_fg_color(item_index, preset.color)
		var portrait_texture: Texture2D = _host._load_texture_from_path(preset.menu_portrait_path)
		if portrait_texture != null:
			_host.preset_list.set_item_icon(item_index, portrait_texture)
		if not selected_name.is_empty() and preset.preset_name == selected_name:
			_host.preset_list.select(item_index)

	_host.preset_count_label.text = "Saved Empires: %d" % presets.size()
	_host.delete_preset_button.disabled = get_selected_preset_name().is_empty()


func clear_form() -> void:
	_host._selected_preset_name = ""
	_host.preset_name_edit.text = ""
	_host.empire_name_edit.text = ""
	_host._reload_species_catalog()
	_host._apply_selected_species_profile(true)
	_host.government_type_id_edit.text = ""
	_host.authority_type_id_edit.text = ""
	_host.civic_ids_edit.text = ""
	_host.flag_path_edit.text = ""
	_host.origin_id_edit.text = ""
	_host.starting_system_type_edit.text = ""
	_host.starting_planet_type_edit.text = ""
	_host.ship_set_spin_box.value = 0
	_host.color_picker_button.color = DEFAULT_EDITOR_COLOR
	_host.biography_edit.text = ""
	_host.preset_list.deselect_all()
	_host.delete_preset_button.disabled = true
	_host.status_label.text = "Create a new empire preset or select one to edit."
	close_delete_overlay()


func load_preset_into_form(preset_name: String) -> void:
	var preset: EmpirePreset = EmpirePresetManager.get_preset_by_name(preset_name)
	if preset == null:
		_host.status_label.text = "Preset '%s' could not be loaded." % preset_name
		return

	_host._selected_preset_name = preset.preset_name
	_host.preset_name_edit.text = preset.preset_name
	_host.empire_name_edit.text = preset.empire_name
	_host._reload_species_catalog(str(preset.species_archetype_id), str(preset.species_type_id))
	_host.species_name_edit.text = preset.species_name
	_host.species_plural_name_edit.text = preset.species_plural_name
	_host.species_adjective_edit.text = preset.species_adjective
	var selected_species_profile: Dictionary = _host._get_selected_species_profile()
	if selected_species_profile.is_empty():
		_host.species_visuals_id_edit.text = str(preset.species_visuals_id)
		_host.menu_portrait_path_edit.text = preset.menu_portrait_path
		_host.leader_portraits_edit.text = "\n".join(preset.leader_portrait_paths)
	else:
		_host._apply_selected_species_profile(false)
	_host.name_set_id_edit.text = str(preset.name_set_id)
	_host.government_type_id_edit.text = str(preset.government_type_id)
	_host.authority_type_id_edit.text = str(preset.authority_type_id)
	_host.civic_ids_edit.text = ", ".join(_stringify_string_name_array(preset.civic_ids))
	_host.flag_path_edit.text = preset.flag_path
	_host.origin_id_edit.text = str(preset.origin_id)
	_host.starting_system_type_edit.text = str(preset.starting_system_type)
	_host.starting_planet_type_edit.text = str(preset.starting_planet_type)
	_host.ship_set_spin_box.value = preset.ship_set_id
	_host.color_picker_button.color = preset.color
	_host.biography_edit.text = preset.biography
	_host._refresh_menu_portrait_preview()
	_host.delete_preset_button.disabled = false
	_host.status_label.text = "Editing preset '%s'." % preset.preset_name
	close_delete_overlay()


func build_preset_from_form() -> EmpirePreset:
	var preset := EmpirePreset.new()
	var species_profile: Dictionary = _host._get_selected_species_profile()
	var resolved_leader_portraits: Array[String] = _host._extract_string_array(species_profile.get("leader_portrait_paths", []))
	if resolved_leader_portraits.is_empty():
		resolved_leader_portraits = _host._parse_multiline_values(_host.leader_portraits_edit.text)
	preset.preset_name = _host.preset_name_edit.text
	preset.empire_name = _host.empire_name_edit.text
	preset.species_archetype_id = StringName(_host._get_selected_option_metadata_as_string(_host.species_archetype_option_button))
	preset.species_type_id = StringName(_host._get_selected_option_metadata_as_string(_host.species_type_option_button))
	preset.species_visuals_id = StringName(str(species_profile.get("species_visuals_id", _host.species_visuals_id_edit.text.strip_edges())))
	preset.species_name = _host.species_name_edit.text
	preset.species_plural_name = _host.species_plural_name_edit.text
	preset.species_adjective = _host.species_adjective_edit.text
	preset.name_set_id = StringName(_host.name_set_id_edit.text.strip_edges())
	preset.government_type_id = StringName(_host.government_type_id_edit.text.strip_edges())
	preset.authority_type_id = StringName(_host.authority_type_id_edit.text.strip_edges())
	preset.civic_ids = _parse_civic_ids(_host.civic_ids_edit.text)
	preset.flag_path = _host.flag_path_edit.text
	preset.biography = _host.biography_edit.text
	preset.color = _host.color_picker_button.color
	preset.ship_set_id = int(_host.ship_set_spin_box.value)
	preset.menu_portrait_path = str(species_profile.get("menu_portrait_path", _host.menu_portrait_path_edit.text))
	preset.leader_portrait_paths = resolved_leader_portraits
	preset.origin_id = StringName(_host.origin_id_edit.text.strip_edges())
	preset.starting_system_type = StringName(_host.starting_system_type_edit.text.strip_edges())
	preset.starting_planet_type = StringName(_host.starting_planet_type_edit.text.strip_edges())
	preset.ensure_defaults()
	return preset


func get_selected_preset_name() -> String:
	var selected_items: PackedInt32Array = _host.preset_list.get_selected_items()
	if selected_items.size() == 0:
		return ""
	return str(_host.preset_list.get_item_metadata(int(selected_items[0])))


func on_preset_selected() -> void:
	var preset_name: String = get_selected_preset_name()
	_host.delete_preset_button.disabled = preset_name.is_empty()
	if preset_name.is_empty():
		return
	load_preset_into_form(preset_name)


func on_new_preset_pressed() -> void:
	clear_form()


func on_save_preset_pressed() -> void:
	var preset: EmpirePreset = build_preset_from_form()
	var save_error: Error = EmpirePresetManager.save_preset(preset, _host._selected_preset_name)
	if save_error != OK:
		_host.status_label.text = "Saving failed with error code %d." % save_error
		return

	_host._selected_preset_name = preset.preset_name
	refresh_preset_list(_host._selected_preset_name)
	load_preset_into_form(_host._selected_preset_name)
	_host.status_label.text = "Saved preset '%s'." % _host._selected_preset_name


func on_request_delete_preset_pressed() -> void:
	if _host._selected_preset_name.is_empty():
		_host.status_label.text = "Select a preset before deleting it."
		return
	open_delete_overlay()


func on_confirm_delete_preset_pressed() -> void:
	if _host._selected_preset_name.is_empty():
		close_delete_overlay()
		return

	var deleted_name: String = _host._selected_preset_name
	var delete_error: Error = EmpirePresetManager.delete_preset(_host._selected_preset_name)
	if delete_error != OK:
		_host.status_label.text = "Delete failed with error code %d." % delete_error
		close_delete_overlay()
		return

	clear_form()
	refresh_preset_list()
	_host.status_label.text = "Deleted preset '%s'." % deleted_name


func _parse_civic_ids(value: String) -> Array[StringName]:
	var result: Array[StringName] = []
	for civic_id in value.split(",", false):
		var trimmed := civic_id.strip_edges()
		if trimmed.is_empty():
			continue
		result.append(StringName(trimmed))
	return result


func _stringify_string_name_array(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result
