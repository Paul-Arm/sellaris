extends Control

const GENERATE_MENU_SCENE_PATH := "res://scene/GennerateMenue/GennerateMenue.tscn"
const DEFAULT_EDITOR_COLOR := Color(0.36, 0.72, 1.0, 1.0)
const PAGE_LANDING := 0
const PAGE_PRESETS := 1
const PAGE_SETTINGS := 2
const PAGE_MULTIPLAYER := 3

@onready var ui_root: MarginContainer = $UiRoot

var content_tabs: TabContainer
var landing_button: Button
var presets_button: Button
var settings_button: Button
var multiplayer_button: Button
var preset_count_label: Label
var preset_list: ItemList
var delete_preset_button: Button
var status_label: Label
var preset_name_edit: LineEdit
var empire_name_edit: LineEdit
var species_type_id_edit: LineEdit
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
var save_preset_button: Button
var clear_form_button: Button
var settings_track_label: Label
var settings_volume_slider: HSlider
var settings_volume_value_label: Label
var delete_overlay: Control
var delete_confirm_label: Label
var delete_cancel_button: Button
var delete_confirm_button: Button

var _selected_preset_name: String = ""


func _ready() -> void:
	MusicManager.play_menu_loops()
	_build_ui()
	_bind_actions()
	_refresh_preset_list()
	_refresh_music_settings()
	_clear_form()
	_show_page(PAGE_LANDING)


func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 18)
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui_root.add_child(root_vbox)

	root_vbox.add_child(_build_header())
	root_vbox.add_child(_build_shell())
	delete_overlay = _build_delete_overlay()
	add_child(delete_overlay)


func _build_header() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 104)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Sellaris Command Nexus"
	title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A real fullscreen main menu scene with a shader background, plus dedicated pages for presets, settings, and multiplayer."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(subtitle)
	return panel


func _build_shell() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 18)
	margin.add_child(row)

	row.add_child(_build_nav_column())
	content_tabs = _build_content_tabs()
	row.add_child(content_tabs)
	return panel


func _build_nav_column() -> VBoxContainer:
	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(220, 0)
	nav.add_theme_constant_override("separation", 10)

	landing_button = _make_button("Landing Page")
	landing_button.pressed.connect(func() -> void: _show_page(PAGE_LANDING))
	nav.add_child(landing_button)

	var singleplayer_button := _make_button("Singleplayer")
	singleplayer_button.pressed.connect(_on_open_galaxy_setup_pressed)
	nav.add_child(singleplayer_button)

	presets_button = _make_button("Empire Presets")
	presets_button.pressed.connect(func() -> void: _show_page(PAGE_PRESETS))
	nav.add_child(presets_button)

	settings_button = _make_button("Settings")
	settings_button.pressed.connect(func() -> void: _show_page(PAGE_SETTINGS))
	nav.add_child(settings_button)

	multiplayer_button = _make_button("Multiplayer")
	multiplayer_button.pressed.connect(func() -> void: _show_page(PAGE_MULTIPLAYER))
	nav.add_child(multiplayer_button)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)

	var quit_button := _make_button("Quit Game")
	quit_button.pressed.connect(_on_quit_pressed)
	nav.add_child(quit_button)
	return nav


func _build_content_tabs() -> TabContainer:
	var tabs := TabContainer.new()
	tabs.tabs_visible = false
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(_build_landing_page())
	tabs.add_child(_build_presets_page())
	tabs.add_child(_build_settings_page())
	tabs.add_child(_build_multiplayer_page())
	return tabs


func _build_landing_page() -> Control:
	var page := Control.new()
	page.name = "LandingPage"
	var margin := _make_full_margin(8)
	page.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	var hero_panel := PanelContainer.new()
	hero_panel.custom_minimum_size = Vector2(0, 240)
	vbox.add_child(hero_panel)

	var hero_margin := _make_margin(24)
	hero_panel.add_child(hero_margin)

	var hero_vbox := VBoxContainer.new()
	hero_vbox.add_theme_constant_override("separation", 14)
	hero_margin.add_child(hero_vbox)

	var hero_title := Label.new()
	hero_title.text = "Shape the next galactic era."
	hero_title.add_theme_font_size_override("font_size", 32)
	hero_vbox.add_child(hero_title)

	var hero_text := Label.new()
	hero_text.text = "This is the actual main screen now. Launch singleplayer, open empire presets, tune settings, or step into the multiplayer placeholder from here."
	hero_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_vbox.add_child(hero_text)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	hero_vbox.add_child(action_row)

	var singleplayer_cta := _make_button("Start Singleplayer", 190, 46)
	singleplayer_cta.pressed.connect(_on_open_galaxy_setup_pressed)
	action_row.add_child(singleplayer_cta)

	var presets_cta := _make_button("Open Empire Presets", 190, 46)
	presets_cta.pressed.connect(func() -> void: _show_page(PAGE_PRESETS))
	action_row.add_child(presets_cta)

	var info_row := HBoxContainer.new()
	info_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_row.add_theme_constant_override("separation", 16)
	vbox.add_child(info_row)

	info_row.add_child(_build_info_card(
		"Settings",
		"Music settings are live already, and this page is ready for graphics, controls, and accessibility later.",
		"Open Settings",
		func() -> void: _show_page(PAGE_SETTINGS)
	))
	info_row.add_child(_build_info_card(
		"Multiplayer",
		"The multiplayer destination exists now so the future lobby flow has a real home in the menu.",
		"Open Multiplayer",
		func() -> void: _show_page(PAGE_MULTIPLAYER)
	))
	return page


func _build_info_card(title_text: String, body_text: String, button_text: String, callback: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := _make_margin(18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	var button := _make_button(button_text, 0, 42)
	button.pressed.connect(callback)
	vbox.add_child(button)
	return panel


func _build_presets_page() -> Control:
	var page := Control.new()
	page.name = "PresetsPage"
	var margin := _make_full_margin(8)
	page.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	row.add_child(_build_preset_browser())
	row.add_child(_build_preset_editor())
	return page


func _build_preset_browser() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := _make_margin(18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Empire Presets"
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)

	preset_count_label = Label.new()
	preset_count_label.text = "Saved Empires: 0"
	vbox.add_child(preset_count_label)

	preset_list = ItemList.new()
	preset_list.custom_minimum_size = Vector2(0, 420)
	preset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(preset_list)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	vbox.add_child(action_row)

	var new_button := _make_button("New Preset")
	new_button.pressed.connect(_on_new_preset_pressed)
	action_row.add_child(new_button)

	delete_preset_button = _make_button("Delete")
	delete_preset_button.disabled = true
	delete_preset_button.pressed.connect(_on_request_delete_preset_pressed)
	action_row.add_child(delete_preset_button)

	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(0, 62)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Create a new empire preset or select one to edit."
	vbox.add_child(status_label)
	return panel


func _build_preset_editor() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := _make_margin(20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Empire Designer"
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var form_vbox := VBoxContainer.new()
	form_vbox.custom_minimum_size = Vector2(0, 720)
	form_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(form_vbox)

	var grid := GridContainer.new()
	grid.columns = 2
	form_vbox.add_child(grid)

	preset_name_edit = _add_labeled_line_edit(grid, "Preset Name")
	empire_name_edit = _add_labeled_line_edit(grid, "Empire Name")
	species_type_id_edit = _add_labeled_line_edit(grid, "Species Type Id")
	species_visuals_id_edit = _add_labeled_line_edit(grid, "Species Visuals Id")
	species_name_edit = _add_labeled_line_edit(grid, "Species Name")
	species_plural_name_edit = _add_labeled_line_edit(grid, "Species Plural")
	species_adjective_edit = _add_labeled_line_edit(grid, "Species Adjective")
	name_set_id_edit = _add_labeled_line_edit(grid, "Name Set Id")
	government_type_id_edit = _add_labeled_line_edit(grid, "Government Type Id")
	authority_type_id_edit = _add_labeled_line_edit(grid, "Authority Type Id")
	civic_ids_edit = _add_labeled_line_edit(grid, "Civic Ids")
	flag_path_edit = _add_labeled_line_edit(grid, "Flag Path")
	origin_id_edit = _add_labeled_line_edit(grid, "Origin Id")
	starting_system_type_edit = _add_labeled_line_edit(grid, "Starting System Type")
	starting_planet_type_edit = _add_labeled_line_edit(grid, "Starting Planet Type")
	ship_set_spin_box = _add_labeled_spin_box(grid, "Ship Set Id")
	color_picker_button = _add_labeled_color_picker(grid, "Empire Color")

	var biography_label := Label.new()
	biography_label.text = "Biography"
	form_vbox.add_child(biography_label)

	biography_edit = TextEdit.new()
	biography_edit.custom_minimum_size = Vector2(0, 180)
	form_vbox.add_child(biography_edit)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	vbox.add_child(action_row)

	save_preset_button = _make_button("Save Preset")
	save_preset_button.pressed.connect(_on_save_preset_pressed)
	action_row.add_child(save_preset_button)

	clear_form_button = _make_button("Clear Form")
	clear_form_button.pressed.connect(_on_clear_form_pressed)
	action_row.add_child(clear_form_button)
	return panel


func _build_settings_page() -> Control:
	var page := Control.new()
	page.name = "SettingsPage"
	var margin := _make_full_margin(18)
	page.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var description := Label.new()
	description.text = "Menu audio is live here now. This is a full page in the main scene, not a popup."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(description)

	settings_track_label = Label.new()
	vbox.add_child(settings_track_label)

	settings_volume_slider = HSlider.new()
	vbox.add_child(settings_volume_slider)

	settings_volume_value_label = Label.new()
	vbox.add_child(settings_volume_value_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	vbox.add_child(button_row)

	var previous_button := _make_button("Previous", 0, 42)
	previous_button.pressed.connect(func() -> void: MusicManager.previous_track())
	button_row.add_child(previous_button)

	var pause_button := _make_button("Pause", 0, 42)
	pause_button.pressed.connect(func() -> void: MusicManager.toggle_pause())
	button_row.add_child(pause_button)

	var next_button := _make_button("Next", 0, 42)
	next_button.pressed.connect(func() -> void: MusicManager.next_track())
	button_row.add_child(next_button)

	var hint := Label.new()
	hint.custom_minimum_size = Vector2(0, 180)
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Next natural additions here would be graphics, controls, accessibility, and gameplay defaults."
	vbox.add_child(hint)
	return page


func _build_multiplayer_page() -> Control:
	var page := Control.new()
	page.name = "MultiplayerPage"
	var margin := _make_full_margin(18)
	page.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Multiplayer"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var description := Label.new()
	description.text = "This is a dedicated main-menu page reserved for future hosting, joining, lobbies, and empire slot assignment."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(description)

	var status_panel := PanelContainer.new()
	status_panel.custom_minimum_size = Vector2(0, 180)
	vbox.add_child(status_panel)

	var status_margin := _make_margin(18)
	status_panel.add_child(status_margin)

	var status_vbox := VBoxContainer.new()
	status_vbox.add_theme_constant_override("separation", 10)
	status_margin.add_child(status_vbox)

	var status_title := Label.new()
	status_title.text = "Not Yet Implemented"
	status_title.add_theme_font_size_override("font_size", 22)
	status_vbox.add_child(status_title)

	var status_text := Label.new()
	status_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_text.text = "The important part now is that multiplayer has its own real page in the fullscreen main menu instead of being a popup afterthought."
	status_vbox.add_child(status_text)
	return page


func _build_delete_overlay() -> Control:
	var overlay := Control.new()
	overlay.name = "DeleteOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false

	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.62)
	overlay.add_child(dimmer)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -220.0
	panel.offset_top = -90.0
	panel.offset_right = 220.0
	panel.offset_bottom = 90.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(panel)

	var margin := _make_margin(18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Confirm Delete"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	delete_confirm_label = Label.new()
	delete_confirm_label.custom_minimum_size = Vector2(0, 52)
	delete_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	delete_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	delete_confirm_label.text = "Delete this preset permanently from disk?"
	vbox.add_child(delete_confirm_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	vbox.add_child(button_row)

	delete_cancel_button = _make_button("Cancel", 0, 40)
	button_row.add_child(delete_cancel_button)

	delete_confirm_button = _make_button("Delete Preset", 0, 40)
	button_row.add_child(delete_confirm_button)
	return overlay


func _make_margin(size: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", size)
	margin.add_theme_constant_override("margin_top", size)
	margin.add_theme_constant_override("margin_right", size)
	margin.add_theme_constant_override("margin_bottom", size)
	return margin


func _make_full_margin(size: int) -> MarginContainer:
	var margin := _make_margin(size)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return margin


func _make_button(text: String, min_width: int = 0, min_height: int = 44) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, min_height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func _add_labeled_line_edit(grid: GridContainer, label_text: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	var edit := LineEdit.new()
	grid.add_child(edit)
	return edit


func _add_labeled_spin_box(grid: GridContainer, label_text: String) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	var spin := SpinBox.new()
	grid.add_child(spin)
	return spin


func _add_labeled_color_picker(grid: GridContainer, label_text: String) -> ColorPickerButton:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(0, 36)
	grid.add_child(picker)
	return picker


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
		if not selected_name.is_empty() and preset.preset_name == selected_name:
			preset_list.select(item_index)

	preset_count_label.text = "Saved Empires: %d" % presets.size()
	delete_preset_button.disabled = _get_selected_preset_name().is_empty()


func _clear_form() -> void:
	_selected_preset_name = ""
	preset_name_edit.text = ""
	empire_name_edit.text = ""
	species_type_id_edit.text = ""
	species_visuals_id_edit.text = ""
	species_name_edit.text = ""
	species_plural_name_edit.text = ""
	species_adjective_edit.text = ""
	name_set_id_edit.text = ""
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
	species_type_id_edit.text = str(preset.species_type_id)
	species_visuals_id_edit.text = str(preset.species_visuals_id)
	species_name_edit.text = preset.species_name
	species_plural_name_edit.text = preset.species_plural_name
	species_adjective_edit.text = preset.species_adjective
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
	delete_preset_button.disabled = false
	status_label.text = "Editing preset '%s'." % preset.preset_name
	_close_delete_overlay()


func _build_preset_from_form() -> EmpirePreset:
	var preset := EmpirePreset.new()
	preset.preset_name = preset_name_edit.text
	preset.empire_name = empire_name_edit.text
	preset.species_type_id = StringName(species_type_id_edit.text.strip_edges())
	preset.species_visuals_id = StringName(species_visuals_id_edit.text.strip_edges())
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


func _open_delete_overlay() -> void:
	if _selected_preset_name.is_empty():
		return
	delete_confirm_label.text = "Delete '%s' permanently from disk?" % _selected_preset_name
	delete_overlay.visible = true


func _close_delete_overlay() -> void:
	delete_overlay.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if delete_overlay.visible:
		_close_delete_overlay()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return
	if content_tabs.current_tab != PAGE_LANDING:
		_show_page(PAGE_LANDING)
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


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


func _show_page(page_index: int) -> void:
	content_tabs.current_tab = page_index
	landing_button.disabled = page_index == PAGE_LANDING
	presets_button.disabled = page_index == PAGE_PRESETS
	settings_button.disabled = page_index == PAGE_SETTINGS
	multiplayer_button.disabled = page_index == PAGE_MULTIPLAYER
	if page_index == PAGE_PRESETS:
		_refresh_preset_list(_selected_preset_name)
	if page_index == PAGE_SETTINGS:
		_refresh_music_settings()


func _on_open_galaxy_setup_pressed() -> void:
	get_tree().change_scene_to_file(GENERATE_MENU_SCENE_PATH)


func _on_settings_volume_changed(value: float) -> void:
	MusicManager.set_volume_ratio(value)
	settings_volume_value_label.text = "Volume: %d%%" % int(round(value * 100.0))


func _on_music_playback_changed(_track_name: String, _paused: bool, _volume_ratio: float, _mode: String) -> void:
	_refresh_music_settings()


func _bind_actions() -> void:
	preset_list.item_selected.connect(_on_preset_selected)
	preset_list.item_activated.connect(_on_preset_activated)
	settings_volume_slider.value_changed.connect(_on_settings_volume_changed)
	delete_cancel_button.pressed.connect(_close_delete_overlay)
	delete_confirm_button.pressed.connect(_on_confirm_delete_preset_pressed)
	MusicManager.playback_changed.connect(_on_music_playback_changed)


func _on_quit_pressed() -> void:
	get_tree().quit()
