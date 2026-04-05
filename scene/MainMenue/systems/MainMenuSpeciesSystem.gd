extends RefCounted

const SPECIES_LIBRARY := preload("res://core/empire/species/SpeciesLibrary.gd")

var _host: Control = null


func bind(host: Control) -> void:
	_host = host


func unbind() -> void:
	_host = null


func reload_species_catalog(preferred_archetype: String = "", preferred_type: String = "") -> void:
	_host._species_catalog = SPECIES_LIBRARY.load_catalog()
	var archetype_entries: Array[Dictionary] = SPECIES_LIBRARY.get_archetype_entries(_host._species_catalog)
	rebuild_species_gallery()
	_host.select_species_button.disabled = archetype_entries.is_empty()

	_host._is_syncing_species_ui = true
	_host.species_archetype_option_button.clear()
	for archetype_entry in archetype_entries:
		var archetype_id := str(archetype_entry.get("id", "")).strip_edges()
		var display_name := str(archetype_entry.get("display_name", archetype_id))
		if archetype_id.is_empty():
			continue
		_add_option_with_metadata(_host.species_archetype_option_button, display_name, archetype_id)
	_host._is_syncing_species_ui = false

	var resolved_archetype := preferred_archetype.strip_edges().to_lower()
	if resolved_archetype.is_empty() and not archetype_entries.is_empty():
		resolved_archetype = str(archetype_entries[0].get("id", ""))
	if not resolved_archetype.is_empty():
		var resolved_entry: Dictionary = get_matching_entry(archetype_entries, "id", resolved_archetype)
		if resolved_entry.is_empty() and not archetype_entries.is_empty():
			resolved_archetype = str(archetype_entries[0].get("id", ""))
	refresh_species_type_options(resolved_archetype, preferred_type)
	if _host.status_label == null:
		return
	if archetype_entries.is_empty():
		_host.status_label.text = "No species folders found in res://core/empire/species."


func refresh_species_type_options(selected_archetype: String, selected_type: String = "", overwrite_names: bool = false) -> void:
	var normalized_archetype := selected_archetype.strip_edges().to_lower()
	var species_entries: Array[Dictionary] = SPECIES_LIBRARY.get_species_entries(_host._species_catalog, normalized_archetype)

	_host._is_syncing_species_ui = true
	if not normalized_archetype.is_empty():
		_select_option_by_metadata(_host.species_archetype_option_button, normalized_archetype)
	_host.species_type_option_button.clear()
	for species_entry in species_entries:
		_add_option_with_metadata(
			_host.species_type_option_button,
			str(species_entry.get("display_name", species_entry.get("species_type_id", ""))),
			str(species_entry.get("species_type_id", ""))
		)

	var normalized_type := selected_type.strip_edges().to_lower()
	if normalized_type.is_empty() and not species_entries.is_empty():
		normalized_type = str(species_entries[0].get("species_type_id", ""))
	if not normalized_type.is_empty():
		_select_option_by_metadata(_host.species_type_option_button, normalized_type)
	if _host.species_type_option_button.get_selected_id() < 0 and _host.species_type_option_button.get_item_count() > 0:
		_host.species_type_option_button.select(0)
	_host._is_syncing_species_ui = false

	apply_selected_species_profile(overwrite_names)
	sync_species_gallery_selection()


func rebuild_species_gallery() -> void:
	clear_container_children(_host.species_gallery_tabs)

	var archetype_entries: Array[Dictionary] = SPECIES_LIBRARY.get_archetype_entries(_host._species_catalog)
	if archetype_entries.is_empty():
		var empty_page := MarginContainer.new()
		empty_page.name = "Unavailable"

		var empty_label := Label.new()
		empty_label.text = "No species folders were found in res://core/empire/species."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_page.add_child(empty_label)

		_host.species_gallery_tabs.add_child(empty_page)
		return

	for archetype_entry in archetype_entries:
		var archetype_id := str(archetype_entry.get("id", "")).strip_edges()
		var archetype_display_name := str(archetype_entry.get("display_name", archetype_id)).strip_edges()
		if archetype_id.is_empty():
			continue

		var archetype_page := MarginContainer.new()
		archetype_page.name = archetype_display_name
		archetype_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		archetype_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		archetype_page.set_meta("archetype_id", archetype_id)

		var species_list := ItemList.new()
		species_list.name = "SpeciesList"
		species_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		species_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		species_list.icon_mode = ItemList.ICON_MODE_TOP
		species_list.fixed_icon_size = Vector2i(144, 144)
		species_list.max_columns = 4
		species_list.allow_reselect = true
		species_list.item_selected.connect(on_species_gallery_item_selected.bind(species_list))
		species_list.item_activated.connect(on_species_gallery_item_selected.bind(species_list))

		for species_entry in SPECIES_LIBRARY.get_species_entries(_host._species_catalog, archetype_id):
			var display_name := str(species_entry.get("display_name", species_entry.get("species_type_id", ""))).strip_edges()
			var species_type_id := str(species_entry.get("species_type_id", "")).strip_edges()
			if species_type_id.is_empty():
				continue

			var portrait_texture := load_texture_from_path(str(species_entry.get("menu_portrait_path", "")))
			species_list.add_item(display_name, portrait_texture, true)
			var item_index: int = species_list.get_item_count() - 1
			species_list.set_item_metadata(item_index, {
				"archetype_id": archetype_id,
				"species_type_id": species_type_id,
			})

		archetype_page.add_child(species_list)
		_host.species_gallery_tabs.add_child(archetype_page)


func get_selected_option_metadata_as_string(option_button: OptionButton) -> String:
	var selected_index: int = option_button.get_selected_id()
	if selected_index < 0:
		return ""
	return str(option_button.get_item_metadata(selected_index)).strip_edges()


func parse_multiline_values(value: String) -> Array[String]:
	var result: Array[String] = []
	for line in value.split("\n", false):
		var trimmed := line.strip_edges()
		if trimmed.is_empty() or result.has(trimmed):
			continue
		result.append(trimmed)
	return result


func extract_string_array(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is not Array:
		return result
	for value in values:
		var text := str(value).strip_edges()
		if text.is_empty():
			continue
		result.append(text)
	return result


func get_matching_entry(entries: Array[Dictionary], field_name: String, expected_value: String) -> Dictionary:
	for entry in entries:
		if str(entry.get(field_name, "")).to_lower() == expected_value.to_lower():
			return entry
	return {}


func get_selected_species_profile() -> Dictionary:
	var archetype_id := get_selected_option_metadata_as_string(_host.species_archetype_option_button)
	var species_type_id := get_selected_option_metadata_as_string(_host.species_type_option_button)
	return SPECIES_LIBRARY.get_species_entry(_host._species_catalog, archetype_id, species_type_id)


func get_archetype_display_name(archetype_id: String) -> String:
	var archetype_entry: Variant = _host._species_catalog.get(archetype_id, {})
	if archetype_entry is Dictionary:
		var display_name := str(archetype_entry.get("display_name", "")).strip_edges()
		if not display_name.is_empty():
			return display_name
	return archetype_id.capitalize()


func update_selected_species_summary() -> void:
	var species_profile: Dictionary = get_selected_species_profile()
	if species_profile.is_empty():
		_host.selected_species_name_label.text = "No Species Selected"
		_host.selected_species_category_label.text = "Choose a species from the discovered gallery."
		_host.select_species_button.text = "Select Species"
		return

	var species_display_name := str(species_profile.get("display_name", species_profile.get("species_name", "Unknown Species"))).strip_edges()
	if species_display_name.is_empty():
		species_display_name = "Unknown Species"

	var leader_count := extract_string_array(species_profile.get("leader_portrait_paths", [])).size()
	_host.selected_species_name_label.text = species_display_name
	_host.selected_species_category_label.text = "%s category | %d leader portraits" % [
		get_archetype_display_name(str(species_profile.get("archetype_id", ""))),
		leader_count,
	]
	_host.select_species_button.text = "Change Species"


func sync_species_gallery_selection() -> void:
	var selected_archetype := get_selected_option_metadata_as_string(_host.species_archetype_option_button)
	var selected_species_type := get_selected_option_metadata_as_string(_host.species_type_option_button)

	for tab_index in range(_host.species_gallery_tabs.get_child_count()):
		var tab_page: Node = _host.species_gallery_tabs.get_child(tab_index)
		var species_list := tab_page.get_node_or_null("SpeciesList") as ItemList
		if species_list == null:
			continue

		species_list.deselect_all()
		for item_index in range(species_list.get_item_count()):
			var metadata: Variant = species_list.get_item_metadata(item_index)
			if metadata is not Dictionary:
				continue
			if str(metadata.get("archetype_id", "")) != selected_archetype:
				continue
			if str(metadata.get("species_type_id", "")) != selected_species_type:
				continue
			species_list.select(item_index)
			_host.species_gallery_tabs.current_tab = tab_index
			break


func set_species_selection(archetype_id: String, species_type_id: String, overwrite_names: bool) -> void:
	refresh_species_type_options(archetype_id, species_type_id, overwrite_names)


func apply_selected_species_profile(overwrite_names: bool) -> void:
	var species_profile: Dictionary = get_selected_species_profile()
	if species_profile.is_empty():
		_host.species_visuals_id_edit.text = ""
		_host.menu_portrait_path_edit.text = ""
		_host.leader_portraits_edit.text = ""
		update_selected_species_summary()
		refresh_menu_portrait_preview()
		return

	_host.species_visuals_id_edit.text = str(species_profile.get("species_visuals_id", ""))
	_host.menu_portrait_path_edit.text = str(species_profile.get("menu_portrait_path", ""))

	var leader_portrait_lines: Array[String] = []
	var leader_portrait_values: Variant = species_profile.get("leader_portrait_paths", [])
	if leader_portrait_values is Array:
		for leader_portrait_value in leader_portrait_values:
			leader_portrait_lines.append(str(leader_portrait_value))
	_host.leader_portraits_edit.text = "\n".join(leader_portrait_lines)

	if overwrite_names or _host.species_name_edit.text.strip_edges().is_empty():
		_host.species_name_edit.text = str(species_profile.get("species_name", ""))
	if overwrite_names or _host.species_plural_name_edit.text.strip_edges().is_empty():
		_host.species_plural_name_edit.text = str(species_profile.get("species_plural_name", ""))
	if overwrite_names or _host.species_adjective_edit.text.strip_edges().is_empty():
		_host.species_adjective_edit.text = str(species_profile.get("species_adjective", ""))
	if overwrite_names or _host.name_set_id_edit.text.strip_edges().is_empty():
		_host.name_set_id_edit.text = str(species_profile.get("name_set_id", ""))

	update_selected_species_summary()
	refresh_menu_portrait_preview()


func refresh_menu_portrait_preview() -> void:
	_host.portrait_preview.texture = load_texture_from_path(_host.menu_portrait_path_edit.text)
	refresh_leader_portrait_previews()


func refresh_leader_portrait_previews() -> void:
	clear_container_children(_host.leader_portrait_preview_flow)

	var portrait_paths: Array[String] = parse_multiline_values(_host.leader_portraits_edit.text)
	if portrait_paths.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No leader portraits discovered for this species."
		_host.leader_portrait_preview_flow.add_child(empty_label)
		return

	for portrait_path in portrait_paths:
		var portrait_card := PanelContainer.new()
		portrait_card.custom_minimum_size = Vector2(92, 92)
		portrait_card.tooltip_text = portrait_path

		var portrait_margin := MarginContainer.new()
		portrait_margin.add_theme_constant_override("margin_left", 4)
		portrait_margin.add_theme_constant_override("margin_top", 4)
		portrait_margin.add_theme_constant_override("margin_right", 4)
		portrait_margin.add_theme_constant_override("margin_bottom", 4)
		portrait_card.add_child(portrait_margin)

		var portrait_texture_rect := TextureRect.new()
		portrait_texture_rect.custom_minimum_size = Vector2(84, 84)
		portrait_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait_texture_rect.texture = load_texture_from_path(portrait_path)
		portrait_margin.add_child(portrait_texture_rect)

		_host.leader_portrait_preview_flow.add_child(portrait_card)


func clear_container_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func load_texture_from_path(path: String) -> Texture2D:
	var trimmed_path := path.strip_edges()
	if trimmed_path.is_empty():
		return null
	if ResourceLoader.exists(trimmed_path):
		return load(trimmed_path) as Texture2D

	var absolute_path: String = ProjectSettings.globalize_path(trimmed_path)
	if not FileAccess.file_exists(absolute_path):
		return null

	var image := Image.new()
	var load_error: Error = image.load(absolute_path)
	if load_error != OK:
		return null
	return ImageTexture.create_from_image(image)


func open_species_gallery() -> void:
	sync_species_gallery_selection()
	_host.species_gallery_overlay.visible = true

	var selected_archetype := get_selected_option_metadata_as_string(_host.species_archetype_option_button)
	for tab_index in range(_host.species_gallery_tabs.get_child_count()):
		var tab_page: Node = _host.species_gallery_tabs.get_child(tab_index)
		if str(tab_page.get_meta("archetype_id", "")) != selected_archetype:
			continue
		_host.species_gallery_tabs.current_tab = tab_index
		break


func close_species_gallery() -> void:
	_host.species_gallery_overlay.visible = false


func on_species_gallery_item_selected(index: int, species_list: ItemList) -> void:
	var metadata: Variant = species_list.get_item_metadata(index)
	if metadata is not Dictionary:
		return

	var archetype_id := str(metadata.get("archetype_id", "")).strip_edges()
	var species_type_id := str(metadata.get("species_type_id", "")).strip_edges()
	if archetype_id.is_empty() or species_type_id.is_empty():
		return

	set_species_selection(archetype_id, species_type_id, true)
	_host.status_label.text = "Selected species '%s'." % species_list.get_item_text(index)
	close_species_gallery()


func on_species_archetype_selected(index: int) -> void:
	if _host._is_syncing_species_ui:
		return
	var selected_archetype := str(_host.species_archetype_option_button.get_item_metadata(index))
	refresh_species_type_options(selected_archetype)


func on_species_type_selected() -> void:
	if _host._is_syncing_species_ui:
		return
	apply_selected_species_profile(false)


func _add_option_with_metadata(option_button: OptionButton, label: String, metadata: Variant) -> void:
	option_button.add_item(label)
	option_button.set_item_metadata(option_button.get_item_count() - 1, metadata)


func _select_option_by_metadata(option_button: OptionButton, expected_metadata: Variant) -> void:
	for option_index in range(option_button.get_item_count()):
		if option_button.get_item_metadata(option_index) == expected_metadata:
			option_button.select(option_index)
			return
