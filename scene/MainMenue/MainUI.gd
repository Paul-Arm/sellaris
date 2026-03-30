extends Control

const GENERATE_MENU_SCENE_PATH := "res://scene/GennerateMenue/GennerateMenue.tscn"
const SPECIES_LIBRARY := preload("res://core/empire/species/SpeciesLibrary.gd")
const DEFAULT_EDITOR_COLOR := Color(0.36, 0.72, 1.0, 1.0)
const PAGE_LANDING := 0
const PAGE_PRESETS := 1
const PAGE_SETTINGS := 2
const PAGE_MULTIPLAYER := 3
const RESOLUTION_OPTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

var content_tabs: TabContainer
var landing_button: Button
var singleplayer_button: Button
var presets_button: Button
var settings_button: Button
var multiplayer_button: Button
var quit_button: Button
var landing_singleplayer_button: Button
var landing_presets_button: Button
var landing_settings_button: Button
var landing_multiplayer_button: Button
var new_preset_button: Button
var preset_count_label: Label
var preset_list: ItemList
var delete_preset_button: Button
var status_label: Label
var preset_name_edit: LineEdit
var empire_name_edit: LineEdit
var selected_species_name_label: Label
var selected_species_category_label: Label
var select_species_button: Button
var species_archetype_option_button: OptionButton
var species_type_option_button: OptionButton
var species_visuals_id_edit: LineEdit
var species_name_edit: LineEdit
var species_plural_name_edit: LineEdit
var species_adjective_edit: LineEdit
var name_set_id_edit: LineEdit
var government_type_id_edit: LineEdit
var authority_type_id_edit: LineEdit
var civic_ids_edit: LineEdit
var flag_path_edit: LineEdit
var origin_id_edit: LineEdit
var starting_system_type_edit: LineEdit
var starting_planet_type_edit: LineEdit
var ship_set_spin_box: SpinBox
var color_picker_button: ColorPickerButton
var biography_edit: TextEdit
var menu_portrait_path_edit: LineEdit
var leader_portraits_edit: TextEdit
var portrait_preview: TextureRect
var leader_portrait_preview_flow: HFlowContainer
var save_preset_button: Button
var clear_form_button: Button
var settings_track_label: Label
var settings_volume_slider: HSlider
var settings_volume_value_label: Label
var settings_window_mode_option: OptionButton
var settings_resolution_option: OptionButton
var settings_aa_option: OptionButton
var settings_status_label: Label
var settings_previous_button: Button
var settings_pause_button: Button
var settings_next_button: Button
var species_gallery_overlay: Control
var species_gallery_tabs: TabContainer
var species_gallery_close_button: Button
var delete_overlay: Control
var delete_confirm_label: Label
var delete_cancel_button: Button
var delete_confirm_button: Button

var _selected_preset_name: String = ""
var _is_syncing_settings_ui: bool = false
var _is_syncing_species_ui: bool = false
var _species_catalog: Dictionary = {}


func _ready() -> void:
	_cache_ui_refs()
	_configure_widgets()
	_populate_settings_options()
	_reload_species_catalog()
	MusicManager.play_menu_loops()
	_bind_actions()
	_refresh_preset_list()
	_refresh_music_settings()
	_refresh_display_settings()
	_clear_form()
	_show_page(PAGE_LANDING)


func _cache_ui_refs() -> void:
	var shell_row := $UiRoot/RootVBox/MainShell/MarginContainer/ShellRow
	var nav_column := shell_row.get_node("NavColumn")
	content_tabs = shell_row.get_node("ContentTabs") as TabContainer
	landing_button = nav_column.get_node("LandingButton") as Button
	singleplayer_button = nav_column.get_node("SingleplayerButton") as Button
	presets_button = nav_column.get_node("PresetsButton") as Button
	settings_button = nav_column.get_node("SettingsButton") as Button
	multiplayer_button = nav_column.get_node("MultiplayerButton") as Button
	quit_button = nav_column.get_node("QuitButton") as Button

	var landing_hero := content_tabs.get_node("LandingPage/LandingVBox/HeroPanel/MarginContainer/HeroVBox")
	landing_singleplayer_button = landing_hero.get_node("LandingActionRow/StartSingleplayerButton") as Button
	landing_presets_button = landing_hero.get_node("LandingActionRow/OpenEmpirePresetsButton") as Button
	var landing_info_row := content_tabs.get_node("LandingPage/LandingVBox/LandingInfoRow")
	landing_settings_button = landing_info_row.get_node("SettingsCard/MarginContainer/SettingsCardVBox/SettingsCardButton") as Button
	landing_multiplayer_button = landing_info_row.get_node("MultiplayerCard/MarginContainer/MultiplayerCardVBox/MultiplayerCardButton") as Button

	var preset_browser := content_tabs.get_node("PresetsPage/ContentRow/PresetBrowser/MarginContainer/BrowserVBox")
	new_preset_button = preset_browser.get_node("BrowserActionRow/NewPresetButton") as Button
	preset_count_label = preset_browser.get_node("PresetCountLabel") as Label
	preset_list = preset_browser.get_node("PresetList") as ItemList
	delete_preset_button = preset_browser.get_node("BrowserActionRow/DeletePresetButton") as Button
	status_label = preset_browser.get_node("StatusLabel") as Label

	var settings_grid := content_tabs.get_node("PresetsPage/ContentRow/PresetEditor/MarginContainer/EditorVBox/ScrollContainer/FormVBox/SettingsGrid")
	preset_name_edit = settings_grid.get_node("PresetNameEdit") as LineEdit
	empire_name_edit = settings_grid.get_node("EmpireNameEdit") as LineEdit
	selected_species_name_label = settings_grid.get_node("SpeciesPickerRow/SelectedSpeciesInfo/SelectedSpeciesNameLabel") as Label
	selected_species_category_label = settings_grid.get_node("SpeciesPickerRow/SelectedSpeciesInfo/SelectedSpeciesCategoryLabel") as Label
	select_species_button = settings_grid.get_node("SpeciesPickerRow/SelectSpeciesButton") as Button
	species_archetype_option_button = settings_grid.get_node("SpeciesArchetypeOptionButton") as OptionButton
	species_type_option_button = settings_grid.get_node("SpeciesTypeOptionButton") as OptionButton
	species_visuals_id_edit = settings_grid.get_node("SpeciesVisualsIdEdit") as LineEdit
	species_name_edit = settings_grid.get_node("SpeciesNameEdit") as LineEdit
	species_plural_name_edit = settings_grid.get_node("SpeciesPluralEdit") as LineEdit
	species_adjective_edit = settings_grid.get_node("SpeciesAdjectiveEdit") as LineEdit
	name_set_id_edit = settings_grid.get_node("NameSetIdEdit") as LineEdit
	government_type_id_edit = settings_grid.get_node("GovernmentTypeIdEdit") as LineEdit
	authority_type_id_edit = settings_grid.get_node("AuthorityTypeIdEdit") as LineEdit
	civic_ids_edit = settings_grid.get_node("CivicIdsEdit") as LineEdit
	flag_path_edit = settings_grid.get_node("FlagPathEdit") as LineEdit
	origin_id_edit = settings_grid.get_node("OriginIdEdit") as LineEdit
	starting_system_type_edit = settings_grid.get_node("StartingSystemTypeEdit") as LineEdit
	starting_planet_type_edit = settings_grid.get_node("StartingPlanetTypeEdit") as LineEdit
	ship_set_spin_box = settings_grid.get_node("ShipSetSpinBox") as SpinBox
	color_picker_button = settings_grid.get_node("ColorPickerButton") as ColorPickerButton
	menu_portrait_path_edit = settings_grid.get_node("MenuPortraitPathEdit") as LineEdit

	var editor_vbox := content_tabs.get_node("PresetsPage/ContentRow/PresetEditor/MarginContainer/EditorVBox")
	biography_edit = editor_vbox.get_node("ScrollContainer/FormVBox/BiographyEdit") as TextEdit
	portrait_preview = editor_vbox.get_node("ScrollContainer/FormVBox/PortraitPreview") as TextureRect
	leader_portrait_preview_flow = editor_vbox.get_node("ScrollContainer/FormVBox/LeaderPortraitPreviewFlow") as HFlowContainer
	leader_portraits_edit = editor_vbox.get_node("ScrollContainer/FormVBox/LeaderPortraitsEdit") as TextEdit
	save_preset_button = editor_vbox.get_node("EditorActionRow/SavePresetButton") as Button
	clear_form_button = editor_vbox.get_node("EditorActionRow/ClearFormButton") as Button

	var settings_vbox := content_tabs.get_node("SettingsPage/SettingsVBox")
	settings_window_mode_option = settings_vbox.get_node("DisplayPanel/MarginContainer/DisplayVBox/DisplayGrid/WindowModeOptionButton") as OptionButton
	settings_resolution_option = settings_vbox.get_node("DisplayPanel/MarginContainer/DisplayVBox/DisplayGrid/ResolutionOptionButton") as OptionButton
	settings_aa_option = settings_vbox.get_node("DisplayPanel/MarginContainer/DisplayVBox/DisplayGrid/AntiAliasingOptionButton") as OptionButton
	settings_status_label = settings_vbox.get_node("DisplayPanel/MarginContainer/DisplayVBox/SettingsStatusLabel") as Label
	settings_track_label = settings_vbox.get_node("SettingsTrackLabel") as Label
	settings_volume_slider = settings_vbox.get_node("SettingsVolumeSlider") as HSlider
	settings_volume_value_label = settings_vbox.get_node("SettingsVolumeValueLabel") as Label
	settings_previous_button = settings_vbox.get_node("SettingsButtonRow/SettingsPreviousButton") as Button
	settings_pause_button = settings_vbox.get_node("SettingsButtonRow/SettingsPauseButton") as Button
	settings_next_button = settings_vbox.get_node("SettingsButtonRow/SettingsNextButton") as Button

	species_gallery_overlay = $SpeciesGalleryOverlay
	species_gallery_tabs = $SpeciesGalleryOverlay/SpeciesGalleryCenter/SpeciesGalleryDialog/MarginContainer/SpeciesGalleryVBox/SpeciesGalleryTabs as TabContainer
	species_gallery_close_button = $SpeciesGalleryOverlay/SpeciesGalleryCenter/SpeciesGalleryDialog/MarginContainer/SpeciesGalleryVBox/SpeciesGalleryHeaderRow/SpeciesGalleryCloseButton as Button

	delete_overlay = $DeleteOverlay
	var delete_vbox := $DeleteOverlay/DeleteCenter/DeleteDialog/MarginContainer/DeleteVBox
	delete_confirm_label = delete_vbox.get_node("DeleteConfirmLabel") as Label
	delete_cancel_button = delete_vbox.get_node("DeleteButtonRow/DeleteCancelButton") as Button
	delete_confirm_button = delete_vbox.get_node("DeleteButtonRow/DeleteConfirmButton") as Button


func _configure_widgets() -> void:
	species_gallery_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	delete_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_volume_slider.min_value = 0.0
	settings_volume_slider.max_value = 1.0
	settings_volume_slider.step = 0.01
	settings_volume_slider.value = SettingsManager.get_music_volume()
	ship_set_spin_box.min_value = 0.0
	ship_set_spin_box.max_value = 999.0
	ship_set_spin_box.step = 1.0
	preset_list.fixed_icon_size = Vector2i(72, 72)
	species_visuals_id_edit.editable = false
	menu_portrait_path_edit.editable = false
	leader_portraits_edit.editable = false
	portrait_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	selected_species_category_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	biography_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leader_portrait_preview_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_preset_button.custom_minimum_size = Vector2(220, 44)
	clear_form_button.custom_minimum_size = Vector2(220, 44)

	var wide_controls: Array[Control] = [
		preset_name_edit,
		empire_name_edit,
		species_name_edit,
		species_plural_name_edit,
		species_adjective_edit,
		name_set_id_edit,
		government_type_id_edit,
		authority_type_id_edit,
		civic_ids_edit,
		flag_path_edit,
		origin_id_edit,
		starting_system_type_edit,
		starting_planet_type_edit,
		ship_set_spin_box,
		color_picker_button,
	]
	for wide_control in wide_controls:
		wide_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _bind_actions() -> void:
	landing_button.pressed.connect(_on_open_landing_pressed)
	singleplayer_button.pressed.connect(_on_open_galaxy_setup_pressed)
	presets_button.pressed.connect(_on_open_presets_pressed)
	settings_button.pressed.connect(_on_open_settings_pressed)
	multiplayer_button.pressed.connect(_on_open_multiplayer_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	landing_singleplayer_button.pressed.connect(_on_open_galaxy_setup_pressed)
	landing_presets_button.pressed.connect(_on_open_presets_pressed)
	landing_settings_button.pressed.connect(_on_open_settings_pressed)
	landing_multiplayer_button.pressed.connect(_on_open_multiplayer_pressed)

	new_preset_button.pressed.connect(_on_new_preset_pressed)
	delete_preset_button.pressed.connect(_on_request_delete_preset_pressed)
	save_preset_button.pressed.connect(_on_save_preset_pressed)
	clear_form_button.pressed.connect(_on_clear_form_pressed)
	select_species_button.pressed.connect(_on_open_species_gallery_pressed)
	species_archetype_option_button.item_selected.connect(_on_species_archetype_selected)
	species_type_option_button.item_selected.connect(_on_species_type_selected)
	preset_list.item_selected.connect(_on_preset_selected)
	preset_list.item_activated.connect(_on_preset_activated)

	settings_volume_slider.value_changed.connect(_on_settings_volume_changed)
	settings_window_mode_option.item_selected.connect(_on_window_mode_selected)
	settings_resolution_option.item_selected.connect(_on_resolution_selected)
	settings_aa_option.item_selected.connect(_on_aa_selected)
	settings_previous_button.pressed.connect(func() -> void: MusicManager.previous_track())
	settings_pause_button.pressed.connect(func() -> void: MusicManager.toggle_pause())
	settings_next_button.pressed.connect(func() -> void: MusicManager.next_track())

	species_gallery_close_button.pressed.connect(_close_species_gallery)
	delete_cancel_button.pressed.connect(_close_delete_overlay)
	delete_confirm_button.pressed.connect(_on_confirm_delete_preset_pressed)
	MusicManager.playback_changed.connect(_on_music_playback_changed)


func _populate_settings_options() -> void:
	settings_window_mode_option.clear()
	_add_option_with_metadata(settings_window_mode_option, "Windowed", DisplayServer.WINDOW_MODE_WINDOWED)
	_add_option_with_metadata(settings_window_mode_option, "Maximized", DisplayServer.WINDOW_MODE_MAXIMIZED)
	_add_option_with_metadata(settings_window_mode_option, "Fullscreen", DisplayServer.WINDOW_MODE_FULLSCREEN)
	_add_option_with_metadata(settings_window_mode_option, "Exclusive Fullscreen", DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	settings_resolution_option.clear()
	for resolution in RESOLUTION_OPTIONS:
		_add_option_with_metadata(settings_resolution_option, "%dx%d" % [resolution.x, resolution.y], resolution)

	settings_aa_option.clear()
	_add_option_with_metadata(settings_aa_option, "Off", Viewport.MSAA_DISABLED)
	_add_option_with_metadata(settings_aa_option, "2x MSAA", Viewport.MSAA_2X)
	_add_option_with_metadata(settings_aa_option, "4x MSAA", Viewport.MSAA_4X)
	_add_option_with_metadata(settings_aa_option, "8x MSAA", Viewport.MSAA_8X)


func _reload_species_catalog(preferred_archetype: String = "", preferred_type: String = "") -> void:
	_species_catalog = SPECIES_LIBRARY.load_catalog()
	var archetype_entries: Array[Dictionary] = SPECIES_LIBRARY.get_archetype_entries(_species_catalog)
	_rebuild_species_gallery()
	select_species_button.disabled = archetype_entries.is_empty()

	_is_syncing_species_ui = true
	species_archetype_option_button.clear()
	for archetype_entry in archetype_entries:
		var archetype_id := str(archetype_entry.get("id", "")).strip_edges()
		var display_name := str(archetype_entry.get("display_name", archetype_id))
		if archetype_id.is_empty():
			continue
		_add_option_with_metadata(species_archetype_option_button, display_name, archetype_id)
	_is_syncing_species_ui = false

	var resolved_archetype := preferred_archetype.strip_edges().to_lower()
	if resolved_archetype.is_empty() and not archetype_entries.is_empty():
		resolved_archetype = str(archetype_entries[0].get("id", ""))
	if not resolved_archetype.is_empty():
		var resolved_entry: Dictionary = _get_matching_entry(archetype_entries, "id", resolved_archetype)
		if resolved_entry.is_empty() and not archetype_entries.is_empty():
			resolved_archetype = str(archetype_entries[0].get("id", ""))
	_refresh_species_type_options(resolved_archetype, preferred_type)
	if status_label == null:
		return
	if archetype_entries.is_empty():
		status_label.text = "No species folders found in res://core/empire/species."


func _refresh_species_type_options(selected_archetype: String, selected_type: String = "", overwrite_names: bool = false) -> void:
	var normalized_archetype := selected_archetype.strip_edges().to_lower()
	var species_entries: Array[Dictionary] = SPECIES_LIBRARY.get_species_entries(_species_catalog, normalized_archetype)

	_is_syncing_species_ui = true
	if not normalized_archetype.is_empty():
		_select_option_by_metadata(species_archetype_option_button, normalized_archetype)
	species_type_option_button.clear()
	for species_entry in species_entries:
		_add_option_with_metadata(
			species_type_option_button,
			str(species_entry.get("display_name", species_entry.get("species_type_id", ""))),
			str(species_entry.get("species_type_id", ""))
		)

	var normalized_type := selected_type.strip_edges().to_lower()
	if normalized_type.is_empty() and not species_entries.is_empty():
		normalized_type = str(species_entries[0].get("species_type_id", ""))
	if not normalized_type.is_empty():
		_select_option_by_metadata(species_type_option_button, normalized_type)
	if species_type_option_button.get_selected_id() < 0 and species_type_option_button.get_item_count() > 0:
		species_type_option_button.select(0)
	_is_syncing_species_ui = false

	_apply_selected_species_profile(overwrite_names)
	_sync_species_gallery_selection()


func _add_option_with_metadata(option_button: OptionButton, label: String, metadata: Variant) -> void:
	option_button.add_item(label)
	option_button.set_item_metadata(option_button.get_item_count() - 1, metadata)


func _rebuild_species_gallery() -> void:
	_clear_container_children(species_gallery_tabs)

	var archetype_entries: Array[Dictionary] = SPECIES_LIBRARY.get_archetype_entries(_species_catalog)
	if archetype_entries.is_empty():
		var empty_page := MarginContainer.new()
		empty_page.name = "Unavailable"

		var empty_label := Label.new()
		empty_label.text = "No species folders were found in res://core/empire/species."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_page.add_child(empty_label)

		species_gallery_tabs.add_child(empty_page)
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
		species_list.item_selected.connect(_on_species_gallery_item_selected.bind(species_list))
		species_list.item_activated.connect(_on_species_gallery_item_selected.bind(species_list))

		for species_entry in SPECIES_LIBRARY.get_species_entries(_species_catalog, archetype_id):
			var display_name := str(species_entry.get("display_name", species_entry.get("species_type_id", ""))).strip_edges()
			var species_type_id := str(species_entry.get("species_type_id", "")).strip_edges()
			if species_type_id.is_empty():
				continue

			var portrait_texture := _load_texture_from_path(str(species_entry.get("menu_portrait_path", "")))
			species_list.add_item(display_name, portrait_texture, true)
			var item_index: int = species_list.get_item_count() - 1
			species_list.set_item_metadata(item_index, {
				"archetype_id": archetype_id,
				"species_type_id": species_type_id,
			})

		archetype_page.add_child(species_list)
		species_gallery_tabs.add_child(archetype_page)


func _refresh_display_settings() -> void:
	_is_syncing_settings_ui = true
	_select_option_by_metadata(settings_window_mode_option, SettingsManager.get_window_mode())
	_select_option_by_resolution(SettingsManager.get_resolution())
	_select_option_by_metadata(settings_aa_option, SettingsManager.get_msaa())
	_is_syncing_settings_ui = false


func _select_option_by_metadata(option_button: OptionButton, expected_metadata: Variant) -> void:
	for option_index in range(option_button.get_item_count()):
		if option_button.get_item_metadata(option_index) == expected_metadata:
			option_button.select(option_index)
			return


func _select_option_by_resolution(expected_resolution: Vector2i) -> void:
	for option_index in range(settings_resolution_option.get_item_count()):
		var metadata: Variant = settings_resolution_option.get_item_metadata(option_index)
		if metadata is Vector2i and metadata == expected_resolution:
			settings_resolution_option.select(option_index)
			return

	_add_option_with_metadata(
		settings_resolution_option,
		"%dx%d" % [expected_resolution.x, expected_resolution.y],
		expected_resolution
	)
	settings_resolution_option.select(settings_resolution_option.get_item_count() - 1)


func _get_selected_option_metadata_as_string(option_button: OptionButton) -> String:
	var selected_index: int = option_button.get_selected_id()
	if selected_index < 0:
		return ""
	return str(option_button.get_item_metadata(selected_index)).strip_edges()


func _parse_multiline_values(value: String) -> Array[String]:
	var result: Array[String] = []
	for line in value.split("\n", false):
		var trimmed := line.strip_edges()
		if trimmed.is_empty():
			continue
		if result.has(trimmed):
			continue
		result.append(trimmed)
	return result


func _extract_string_array(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is not Array:
		return result
	for value in values:
		var text := str(value).strip_edges()
		if text.is_empty():
			continue
		result.append(text)
	return result


func _get_matching_entry(entries: Array[Dictionary], field_name: String, expected_value: String) -> Dictionary:
	for entry in entries:
		if str(entry.get(field_name, "")).to_lower() == expected_value.to_lower():
			return entry
	return {}


func _get_selected_species_profile() -> Dictionary:
	var archetype_id := _get_selected_option_metadata_as_string(species_archetype_option_button)
	var species_type_id := _get_selected_option_metadata_as_string(species_type_option_button)
	return SPECIES_LIBRARY.get_species_entry(_species_catalog, archetype_id, species_type_id)


func _get_archetype_display_name(archetype_id: String) -> String:
	var archetype_entry: Variant = _species_catalog.get(archetype_id, {})
	if archetype_entry is Dictionary:
		var display_name := str(archetype_entry.get("display_name", "")).strip_edges()
		if not display_name.is_empty():
			return display_name
	return archetype_id.capitalize()


func _update_selected_species_summary() -> void:
	var species_profile: Dictionary = _get_selected_species_profile()
	if species_profile.is_empty():
		selected_species_name_label.text = "No Species Selected"
		selected_species_category_label.text = "Choose a species from the discovered gallery."
		select_species_button.text = "Select Species"
		return

	var species_display_name := str(species_profile.get("display_name", species_profile.get("species_name", "Unknown Species"))).strip_edges()
	if species_display_name.is_empty():
		species_display_name = "Unknown Species"

	var leader_count := _extract_string_array(species_profile.get("leader_portrait_paths", [])).size()
	selected_species_name_label.text = species_display_name
	selected_species_category_label.text = "%s category | %d leader portraits" % [
		_get_archetype_display_name(str(species_profile.get("archetype_id", ""))),
		leader_count,
	]
	select_species_button.text = "Change Species"


func _sync_species_gallery_selection() -> void:
	var selected_archetype := _get_selected_option_metadata_as_string(species_archetype_option_button)
	var selected_species_type := _get_selected_option_metadata_as_string(species_type_option_button)

	for tab_index in range(species_gallery_tabs.get_child_count()):
		var tab_page := species_gallery_tabs.get_child(tab_index)
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
			species_gallery_tabs.current_tab = tab_index
			break


func _set_species_selection(archetype_id: String, species_type_id: String, overwrite_names: bool) -> void:
	_refresh_species_type_options(archetype_id, species_type_id, overwrite_names)


func _apply_selected_species_profile(overwrite_names: bool) -> void:
	var species_profile: Dictionary = _get_selected_species_profile()
	if species_profile.is_empty():
		species_visuals_id_edit.text = ""
		menu_portrait_path_edit.text = ""
		leader_portraits_edit.text = ""
		_update_selected_species_summary()
		_refresh_menu_portrait_preview()
		return

	species_visuals_id_edit.text = str(species_profile.get("species_visuals_id", ""))
	menu_portrait_path_edit.text = str(species_profile.get("menu_portrait_path", ""))

	var leader_portrait_lines: Array[String] = []
	var leader_portrait_values: Variant = species_profile.get("leader_portrait_paths", [])
	if leader_portrait_values is Array:
		for leader_portrait_value in leader_portrait_values:
			leader_portrait_lines.append(str(leader_portrait_value))
	leader_portraits_edit.text = "\n".join(leader_portrait_lines)

	if overwrite_names or species_name_edit.text.strip_edges().is_empty():
		species_name_edit.text = str(species_profile.get("species_name", ""))
	if overwrite_names or species_plural_name_edit.text.strip_edges().is_empty():
		species_plural_name_edit.text = str(species_profile.get("species_plural_name", ""))
	if overwrite_names or species_adjective_edit.text.strip_edges().is_empty():
		species_adjective_edit.text = str(species_profile.get("species_adjective", ""))
	if overwrite_names or name_set_id_edit.text.strip_edges().is_empty():
		name_set_id_edit.text = str(species_profile.get("name_set_id", ""))

	_update_selected_species_summary()
	_refresh_menu_portrait_preview()


func _refresh_menu_portrait_preview() -> void:
	portrait_preview.texture = _load_texture_from_path(menu_portrait_path_edit.text)
	_refresh_leader_portrait_previews()


func _refresh_leader_portrait_previews() -> void:
	_clear_container_children(leader_portrait_preview_flow)

	var portrait_paths: Array[String] = _parse_multiline_values(leader_portraits_edit.text)
	if portrait_paths.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No leader portraits discovered for this species."
		leader_portrait_preview_flow.add_child(empty_label)
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
		portrait_texture_rect.texture = _load_texture_from_path(portrait_path)
		portrait_margin.add_child(portrait_texture_rect)

		leader_portrait_preview_flow.add_child(portrait_card)


func _clear_container_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _load_texture_from_path(path: String) -> Texture2D:
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


func _open_species_gallery() -> void:
	_sync_species_gallery_selection()
	species_gallery_overlay.visible = true

	var selected_archetype := _get_selected_option_metadata_as_string(species_archetype_option_button)
	for tab_index in range(species_gallery_tabs.get_child_count()):
		var tab_page := species_gallery_tabs.get_child(tab_index)
		if str(tab_page.get_meta("archetype_id", "")) != selected_archetype:
			continue
		species_gallery_tabs.current_tab = tab_index
		break


func _close_species_gallery() -> void:
	species_gallery_overlay.visible = false


func _open_delete_overlay() -> void:
	if _selected_preset_name.is_empty():
		return
	delete_confirm_label.text = "Delete '%s' permanently from disk?" % _selected_preset_name
	delete_overlay.visible = true


func _close_delete_overlay() -> void:
	delete_overlay.visible = false


func _refresh_music_settings() -> void:
	var track_name: String = MusicManager.get_current_track_name()
	if track_name.is_empty():
		track_name = "Menu ambience idle"
	settings_track_label.text = "Current Track: %s" % track_name
	settings_volume_slider.value = MusicManager.get_volume_ratio()
	settings_volume_value_label.text = "Volume: %d%%" % int(round(MusicManager.get_volume_ratio() * 100.0))


func _refresh_preset_list(selected_name: String = "") -> void:
	EmpirePresetManager.load_presets()
	preset_list.clear()

	var presets: Array[EmpirePreset] = EmpirePresetManager.get_presets()
	for preset in presets:
		preset_list.add_item("%s  |  %s" % [preset.preset_name, preset.empire_name])
		var item_index: int = preset_list.get_item_count() - 1
		preset_list.set_item_metadata(item_index, preset.preset_name)
		preset_list.set_item_custom_fg_color(item_index, preset.color)
		var portrait_texture := _load_texture_from_path(preset.menu_portrait_path)
		if portrait_texture != null:
			preset_list.set_item_icon(item_index, portrait_texture)
		if not selected_name.is_empty() and preset.preset_name == selected_name:
			preset_list.select(item_index)

	preset_count_label.text = "Saved Empires: %d" % presets.size()
	delete_preset_button.disabled = _get_selected_preset_name().is_empty()


func _clear_form() -> void:
	_selected_preset_name = ""
	preset_name_edit.text = ""
	empire_name_edit.text = ""
	_reload_species_catalog()
	_apply_selected_species_profile(true)
	government_type_id_edit.text = ""
	authority_type_id_edit.text = ""
	civic_ids_edit.text = ""
	flag_path_edit.text = ""
	origin_id_edit.text = ""
	starting_system_type_edit.text = ""
	starting_planet_type_edit.text = ""
	ship_set_spin_box.value = 0
	color_picker_button.color = DEFAULT_EDITOR_COLOR
	biography_edit.text = ""
	preset_list.deselect_all()
	delete_preset_button.disabled = true
	status_label.text = "Create a new empire preset or select one to edit."
	_close_delete_overlay()


func _load_preset_into_form(preset_name: String) -> void:
	var preset: EmpirePreset = EmpirePresetManager.get_preset_by_name(preset_name)
	if preset == null:
		status_label.text = "Preset '%s' could not be loaded." % preset_name
		return

	_selected_preset_name = preset.preset_name
	preset_name_edit.text = preset.preset_name
	empire_name_edit.text = preset.empire_name
	_reload_species_catalog(str(preset.species_archetype_id), str(preset.species_type_id))
	species_name_edit.text = preset.species_name
	species_plural_name_edit.text = preset.species_plural_name
	species_adjective_edit.text = preset.species_adjective
	var selected_species_profile: Dictionary = _get_selected_species_profile()
	if selected_species_profile.is_empty():
		species_visuals_id_edit.text = str(preset.species_visuals_id)
		menu_portrait_path_edit.text = preset.menu_portrait_path
		leader_portraits_edit.text = "\n".join(preset.leader_portrait_paths)
	else:
		_apply_selected_species_profile(false)
	name_set_id_edit.text = str(preset.name_set_id)
	government_type_id_edit.text = str(preset.government_type_id)
	authority_type_id_edit.text = str(preset.authority_type_id)
	civic_ids_edit.text = ", ".join(_stringify_string_name_array(preset.civic_ids))
	flag_path_edit.text = preset.flag_path
	origin_id_edit.text = str(preset.origin_id)
	starting_system_type_edit.text = str(preset.starting_system_type)
	starting_planet_type_edit.text = str(preset.starting_planet_type)
	ship_set_spin_box.value = preset.ship_set_id
	color_picker_button.color = preset.color
	biography_edit.text = preset.biography
	_refresh_menu_portrait_preview()
	delete_preset_button.disabled = false
	status_label.text = "Editing preset '%s'." % preset.preset_name
	_close_delete_overlay()


func _build_preset_from_form() -> EmpirePreset:
	var preset := EmpirePreset.new()
	var species_profile: Dictionary = _get_selected_species_profile()
	var resolved_leader_portraits: Array[String] = _extract_string_array(species_profile.get("leader_portrait_paths", []))
	if resolved_leader_portraits.is_empty():
		resolved_leader_portraits = _parse_multiline_values(leader_portraits_edit.text)
	preset.preset_name = preset_name_edit.text
	preset.empire_name = empire_name_edit.text
	preset.species_archetype_id = StringName(_get_selected_option_metadata_as_string(species_archetype_option_button))
	preset.species_type_id = StringName(_get_selected_option_metadata_as_string(species_type_option_button))
	preset.species_visuals_id = StringName(str(species_profile.get("species_visuals_id", species_visuals_id_edit.text.strip_edges())))
	preset.species_name = species_name_edit.text
	preset.species_plural_name = species_plural_name_edit.text
	preset.species_adjective = species_adjective_edit.text
	preset.name_set_id = StringName(name_set_id_edit.text.strip_edges())
	preset.government_type_id = StringName(government_type_id_edit.text.strip_edges())
	preset.authority_type_id = StringName(authority_type_id_edit.text.strip_edges())
	preset.civic_ids = _parse_civic_ids(civic_ids_edit.text)
	preset.flag_path = flag_path_edit.text
	preset.biography = biography_edit.text
	preset.color = color_picker_button.color
	preset.ship_set_id = int(ship_set_spin_box.value)
	preset.menu_portrait_path = str(species_profile.get("menu_portrait_path", menu_portrait_path_edit.text))
	preset.leader_portrait_paths = resolved_leader_portraits
	preset.origin_id = StringName(origin_id_edit.text.strip_edges())
	preset.starting_system_type = StringName(starting_system_type_edit.text.strip_edges())
	preset.starting_planet_type = StringName(starting_planet_type_edit.text.strip_edges())
	preset.ensure_defaults()
	return preset


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


func _get_selected_preset_name() -> String:
	var selected_items: PackedInt32Array = preset_list.get_selected_items()
	if selected_items.size() == 0:
		return ""
	return str(preset_list.get_item_metadata(int(selected_items[0])))


func _show_page(page_index: int) -> void:
	content_tabs.current_tab = page_index
	landing_button.disabled = page_index == PAGE_LANDING
	presets_button.disabled = page_index == PAGE_PRESETS
	settings_button.disabled = page_index == PAGE_SETTINGS
	multiplayer_button.disabled = page_index == PAGE_MULTIPLAYER
	if page_index != PAGE_PRESETS:
		_close_species_gallery()
	if page_index == PAGE_PRESETS:
		_reload_species_catalog(
			_get_selected_option_metadata_as_string(species_archetype_option_button),
			_get_selected_option_metadata_as_string(species_type_option_button)
		)
		_refresh_preset_list(_selected_preset_name)
	if page_index == PAGE_SETTINGS:
		_refresh_music_settings()
		_refresh_display_settings()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if species_gallery_overlay.visible:
		_close_species_gallery()
		var species_gallery_viewport := get_viewport()
		if species_gallery_viewport != null:
			species_gallery_viewport.set_input_as_handled()
		return
	if delete_overlay.visible:
		_close_delete_overlay()
		var overlay_viewport := get_viewport()
		if overlay_viewport != null:
			overlay_viewport.set_input_as_handled()
		return
	if content_tabs.current_tab != PAGE_LANDING:
		_show_page(PAGE_LANDING)
		var page_viewport := get_viewport()
		if page_viewport != null:
			page_viewport.set_input_as_handled()


func _on_open_landing_pressed() -> void:
	_show_page(PAGE_LANDING)


func _on_open_presets_pressed() -> void:
	_show_page(PAGE_PRESETS)


func _on_open_settings_pressed() -> void:
	_show_page(PAGE_SETTINGS)


func _on_open_multiplayer_pressed() -> void:
	_show_page(PAGE_MULTIPLAYER)


func _on_open_species_gallery_pressed() -> void:
	_open_species_gallery()


func _on_species_gallery_item_selected(index: int, species_list: ItemList) -> void:
	var metadata: Variant = species_list.get_item_metadata(index)
	if metadata is not Dictionary:
		return

	var archetype_id := str(metadata.get("archetype_id", "")).strip_edges()
	var species_type_id := str(metadata.get("species_type_id", "")).strip_edges()
	if archetype_id.is_empty() or species_type_id.is_empty():
		return

	_set_species_selection(archetype_id, species_type_id, true)
	status_label.text = "Selected species '%s'." % species_list.get_item_text(index)
	_close_species_gallery()


func _on_species_archetype_selected(index: int) -> void:
	if _is_syncing_species_ui:
		return
	var selected_archetype := str(species_archetype_option_button.get_item_metadata(index))
	_refresh_species_type_options(selected_archetype)


func _on_species_type_selected(_index: int) -> void:
	if _is_syncing_species_ui:
		return
	_apply_selected_species_profile(false)


func _on_preset_selected(_index: int) -> void:
	var preset_name: String = _get_selected_preset_name()
	delete_preset_button.disabled = preset_name.is_empty()
	if preset_name.is_empty():
		return
	_load_preset_into_form(preset_name)


func _on_preset_activated(_index: int) -> void:
	_on_preset_selected(_index)


func _on_new_preset_pressed() -> void:
	_clear_form()


func _on_clear_form_pressed() -> void:
	_clear_form()


func _on_save_preset_pressed() -> void:
	var preset: EmpirePreset = _build_preset_from_form()
	var save_error: Error = EmpirePresetManager.save_preset(preset, _selected_preset_name)
	if save_error != OK:
		status_label.text = "Saving failed with error code %d." % save_error
		return

	_selected_preset_name = preset.preset_name
	_refresh_preset_list(_selected_preset_name)
	_load_preset_into_form(_selected_preset_name)
	status_label.text = "Saved preset '%s'." % _selected_preset_name


func _on_request_delete_preset_pressed() -> void:
	if _selected_preset_name.is_empty():
		status_label.text = "Select a preset before deleting it."
		return
	_open_delete_overlay()


func _on_confirm_delete_preset_pressed() -> void:
	if _selected_preset_name.is_empty():
		_close_delete_overlay()
		return

	var deleted_name: String = _selected_preset_name
	var delete_error: Error = EmpirePresetManager.delete_preset(_selected_preset_name)
	if delete_error != OK:
		status_label.text = "Delete failed with error code %d." % delete_error
		_close_delete_overlay()
		return

	_clear_form()
	_refresh_preset_list()
	status_label.text = "Deleted preset '%s'." % deleted_name


func _on_open_galaxy_setup_pressed() -> void:
	get_tree().change_scene_to_file(GENERATE_MENU_SCENE_PATH)


func _on_settings_volume_changed(value: float) -> void:
	SettingsManager.set_music_volume(value)
	settings_volume_value_label.text = "Volume: %d%%" % int(round(value * 100.0))


func _on_window_mode_selected(index: int) -> void:
	if _is_syncing_settings_ui:
		return
	SettingsManager.set_window_mode(int(settings_window_mode_option.get_item_metadata(index)))
	settings_status_label.text = "Saved window mode: %s." % settings_window_mode_option.get_item_text(index)
	_refresh_display_settings()


func _on_resolution_selected(index: int) -> void:
	if _is_syncing_settings_ui:
		return
	var metadata: Variant = settings_resolution_option.get_item_metadata(index)
	if not metadata is Vector2i:
		return
	SettingsManager.set_resolution(metadata as Vector2i)
	settings_status_label.text = "Saved resolution: %s." % settings_resolution_option.get_item_text(index)
	_refresh_display_settings()


func _on_aa_selected(index: int) -> void:
	if _is_syncing_settings_ui:
		return
	SettingsManager.set_msaa(int(settings_aa_option.get_item_metadata(index)))
	settings_status_label.text = "Saved anti-aliasing: %s." % settings_aa_option.get_item_text(index)
	_refresh_display_settings()


func _on_music_playback_changed(_track_name: String, _paused: bool, _volume_ratio: float, _mode: String) -> void:
	_refresh_music_settings()


func _on_quit_pressed() -> void:
	get_tree().quit()
