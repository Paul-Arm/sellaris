extends Control

const GENERATE_MENU_SCENE_PATH := "res://scene/GennerateMenue/GennerateMenue.tscn"
const MAIN_MENU_SCENE_SETUP_SCRIPT: Script = preload("res://scene/MainMenue/systems/MainMenuSceneSetup.gd")
const MAIN_MENU_SPECIES_SYSTEM_SCRIPT: Script = preload("res://scene/MainMenue/systems/MainMenuSpeciesSystem.gd")
const MAIN_MENU_SETTINGS_SYSTEM_SCRIPT: Script = preload("res://scene/MainMenue/systems/MainMenuSettingsSystem.gd")
const MAIN_MENU_PRESET_SYSTEM_SCRIPT: Script = preload("res://scene/MainMenue/systems/MainMenuPresetSystem.gd")
const PAGE_LANDING := 0
const PAGE_PRESETS := 1
const PAGE_SETTINGS := 2
const PAGE_MULTIPLAYER := 3

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
var _scene_setup = MAIN_MENU_SCENE_SETUP_SCRIPT.new()
var _species_system = MAIN_MENU_SPECIES_SYSTEM_SCRIPT.new()
var _settings_system = MAIN_MENU_SETTINGS_SYSTEM_SCRIPT.new()
var _preset_system = MAIN_MENU_PRESET_SYSTEM_SCRIPT.new()


func _ready() -> void:
	_scene_setup.bind(self)
	_species_system.bind(self)
	_settings_system.bind(self)
	_preset_system.bind(self)

	_scene_setup.cache_ui_refs()
	_scene_setup.configure_widgets()
	_populate_settings_options()
	_reload_species_catalog()
	MusicManager.play_menu_loops()
	_bind_actions()
	_refresh_preset_list()
	_refresh_music_settings()
	_refresh_display_settings()
	_clear_form()
	_show_page(PAGE_LANDING)


func _exit_tree() -> void:
	if _preset_system != null:
		_preset_system.unbind()
	if _settings_system != null:
		_settings_system.unbind()
	if _species_system != null:
		_species_system.unbind()
	if _scene_setup != null:
		_scene_setup.unbind()


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
	_settings_system.populate_settings_options()


func _reload_species_catalog(preferred_archetype: String = "", preferred_type: String = "") -> void:
	_species_system.reload_species_catalog(preferred_archetype, preferred_type)


func _refresh_display_settings() -> void:
	_settings_system.refresh_display_settings()


func _get_selected_option_metadata_as_string(option_button: OptionButton) -> String:
	return _species_system.get_selected_option_metadata_as_string(option_button)


func _parse_multiline_values(value: String) -> Array[String]:
	return _species_system.parse_multiline_values(value)


func _extract_string_array(values: Variant) -> Array[String]:
	return _species_system.extract_string_array(values)


func _get_selected_species_profile() -> Dictionary:
	return _species_system.get_selected_species_profile()


func _apply_selected_species_profile(overwrite_names: bool) -> void:
	_species_system.apply_selected_species_profile(overwrite_names)


func _refresh_menu_portrait_preview() -> void:
	_species_system.refresh_menu_portrait_preview()


func _load_texture_from_path(path: String) -> Texture2D:
	return _species_system.load_texture_from_path(path)


func _open_species_gallery() -> void:
	_species_system.open_species_gallery()


func _close_species_gallery() -> void:
	_species_system.close_species_gallery()


func _refresh_music_settings() -> void:
	_settings_system.refresh_music_settings()


func _refresh_preset_list(selected_name: String = "") -> void:
	_preset_system.refresh_preset_list(selected_name)


func _clear_form() -> void:
	_preset_system.clear_form()


func _load_preset_into_form(preset_name: String) -> void:
	_preset_system.load_preset_into_form(preset_name)


func _build_preset_from_form() -> EmpirePreset:
	return _preset_system.build_preset_from_form()


func _get_selected_preset_name() -> String:
	return _preset_system.get_selected_preset_name()


func _open_delete_overlay() -> void:
	_preset_system.open_delete_overlay()


func _close_delete_overlay() -> void:
	_preset_system.close_delete_overlay()


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


func _on_species_archetype_selected(index: int) -> void:
	_species_system.on_species_archetype_selected(index)


func _on_species_type_selected(_index: int) -> void:
	_species_system.on_species_type_selected()


func _on_preset_selected(_index: int) -> void:
	_preset_system.on_preset_selected()


func _on_preset_activated(_index: int) -> void:
	_preset_system.on_preset_selected()


func _on_new_preset_pressed() -> void:
	_preset_system.on_new_preset_pressed()


func _on_clear_form_pressed() -> void:
	_clear_form()


func _on_save_preset_pressed() -> void:
	_preset_system.on_save_preset_pressed()


func _on_request_delete_preset_pressed() -> void:
	_preset_system.on_request_delete_preset_pressed()


func _on_confirm_delete_preset_pressed() -> void:
	_preset_system.on_confirm_delete_preset_pressed()


func _on_open_galaxy_setup_pressed() -> void:
	get_tree().change_scene_to_file(GENERATE_MENU_SCENE_PATH)


func _on_settings_volume_changed(value: float) -> void:
	_settings_system.on_settings_volume_changed(value)


func _on_window_mode_selected(index: int) -> void:
	_settings_system.on_window_mode_selected(index)


func _on_resolution_selected(index: int) -> void:
	_settings_system.on_resolution_selected(index)


func _on_aa_selected(index: int) -> void:
	_settings_system.on_aa_selected(index)


func _on_music_playback_changed(track_name: String, paused: bool, volume_ratio: float, mode: String) -> void:
	_settings_system.on_music_playback_changed(track_name, paused, volume_ratio, mode)


func _on_quit_pressed() -> void:
	get_tree().quit()
