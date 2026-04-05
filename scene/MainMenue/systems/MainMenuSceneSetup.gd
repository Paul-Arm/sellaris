extends RefCounted

var _host: Control = null


func bind(host: Control) -> void:
	_host = host


func unbind() -> void:
	_host = null


func cache_ui_refs() -> void:
	var shell_row: Node = _host.get_node("UiRoot/RootVBox/MainShell/MarginContainer/ShellRow")
	var nav_column: Node = shell_row.get_node("NavColumn")
	_host.content_tabs = shell_row.get_node("ContentTabs") as TabContainer
	_host.landing_button = nav_column.get_node("LandingButton") as Button
	_host.singleplayer_button = nav_column.get_node("SingleplayerButton") as Button
	_host.presets_button = nav_column.get_node("PresetsButton") as Button
	_host.settings_button = nav_column.get_node("SettingsButton") as Button
	_host.multiplayer_button = nav_column.get_node("MultiplayerButton") as Button
	_host.quit_button = nav_column.get_node("QuitButton") as Button

	var landing_hero: Node = _host.content_tabs.get_node("LandingPage/LandingVBox/HeroPanel/MarginContainer/HeroVBox")
	_host.landing_singleplayer_button = landing_hero.get_node("LandingActionRow/StartSingleplayerButton") as Button
	_host.landing_presets_button = landing_hero.get_node("LandingActionRow/OpenEmpirePresetsButton") as Button
	var landing_info_row: Node = _host.content_tabs.get_node("LandingPage/LandingVBox/LandingInfoRow")
	_host.landing_settings_button = landing_info_row.get_node("SettingsCard/MarginContainer/SettingsCardVBox/SettingsCardButton") as Button
	_host.landing_multiplayer_button = landing_info_row.get_node("MultiplayerCard/MarginContainer/MultiplayerCardVBox/MultiplayerCardButton") as Button

	var preset_browser: Node = _host.content_tabs.get_node("PresetsPage/ContentRow/PresetBrowser/MarginContainer/BrowserVBox")
	_host.new_preset_button = preset_browser.get_node("BrowserActionRow/NewPresetButton") as Button
	_host.preset_count_label = preset_browser.get_node("PresetCountLabel") as Label
	_host.preset_list = preset_browser.get_node("PresetList") as ItemList
	_host.delete_preset_button = preset_browser.get_node("BrowserActionRow/DeletePresetButton") as Button
	_host.status_label = preset_browser.get_node("StatusLabel") as Label

	var settings_grid: Node = _host.content_tabs.get_node("PresetsPage/ContentRow/PresetEditor/MarginContainer/EditorVBox/ScrollContainer/FormVBox/SettingsGrid")
	_host.preset_name_edit = settings_grid.get_node("PresetNameEdit") as LineEdit
	_host.empire_name_edit = settings_grid.get_node("EmpireNameEdit") as LineEdit
	_host.selected_species_name_label = settings_grid.get_node("SpeciesPickerRow/SelectedSpeciesInfo/SelectedSpeciesNameLabel") as Label
	_host.selected_species_category_label = settings_grid.get_node("SpeciesPickerRow/SelectedSpeciesInfo/SelectedSpeciesCategoryLabel") as Label
	_host.select_species_button = settings_grid.get_node("SpeciesPickerRow/SelectSpeciesButton") as Button
	_host.species_archetype_option_button = settings_grid.get_node("SpeciesArchetypeOptionButton") as OptionButton
	_host.species_type_option_button = settings_grid.get_node("SpeciesTypeOptionButton") as OptionButton
	_host.species_visuals_id_edit = settings_grid.get_node("SpeciesVisualsIdEdit") as LineEdit
	_host.species_name_edit = settings_grid.get_node("SpeciesNameEdit") as LineEdit
	_host.species_plural_name_edit = settings_grid.get_node("SpeciesPluralEdit") as LineEdit
	_host.species_adjective_edit = settings_grid.get_node("SpeciesAdjectiveEdit") as LineEdit
	_host.name_set_id_edit = settings_grid.get_node("NameSetIdEdit") as LineEdit
	_host.government_type_id_edit = settings_grid.get_node("GovernmentTypeIdEdit") as LineEdit
	_host.authority_type_id_edit = settings_grid.get_node("AuthorityTypeIdEdit") as LineEdit
	_host.civic_ids_edit = settings_grid.get_node("CivicIdsEdit") as LineEdit
	_host.flag_path_edit = settings_grid.get_node("FlagPathEdit") as LineEdit
	_host.origin_id_edit = settings_grid.get_node("OriginIdEdit") as LineEdit
	_host.starting_system_type_edit = settings_grid.get_node("StartingSystemTypeEdit") as LineEdit
	_host.starting_planet_type_edit = settings_grid.get_node("StartingPlanetTypeEdit") as LineEdit
	_host.ship_set_spin_box = settings_grid.get_node("ShipSetSpinBox") as SpinBox
	_host.color_picker_button = settings_grid.get_node("ColorPickerButton") as ColorPickerButton
	_host.menu_portrait_path_edit = settings_grid.get_node("MenuPortraitPathEdit") as LineEdit

	var editor_vbox: Node = _host.content_tabs.get_node("PresetsPage/ContentRow/PresetEditor/MarginContainer/EditorVBox")
	_host.biography_edit = editor_vbox.get_node("ScrollContainer/FormVBox/BiographyEdit") as TextEdit
	_host.portrait_preview = editor_vbox.get_node("ScrollContainer/FormVBox/PortraitPreview") as TextureRect
	_host.leader_portrait_preview_flow = editor_vbox.get_node("ScrollContainer/FormVBox/LeaderPortraitPreviewFlow") as HFlowContainer
	_host.leader_portraits_edit = editor_vbox.get_node("ScrollContainer/FormVBox/LeaderPortraitsEdit") as TextEdit
	_host.save_preset_button = editor_vbox.get_node("EditorActionRow/SavePresetButton") as Button
	_host.clear_form_button = editor_vbox.get_node("EditorActionRow/ClearFormButton") as Button

	var settings_vbox: Node = _host.content_tabs.get_node("SettingsPage/SettingsVBox")
	_host.settings_window_mode_option = settings_vbox.get_node("DisplayPanel/MarginContainer/DisplayVBox/DisplayGrid/WindowModeOptionButton") as OptionButton
	_host.settings_resolution_option = settings_vbox.get_node("DisplayPanel/MarginContainer/DisplayVBox/DisplayGrid/ResolutionOptionButton") as OptionButton
	_host.settings_aa_option = settings_vbox.get_node("DisplayPanel/MarginContainer/DisplayVBox/DisplayGrid/AntiAliasingOptionButton") as OptionButton
	_host.settings_status_label = settings_vbox.get_node("DisplayPanel/MarginContainer/DisplayVBox/SettingsStatusLabel") as Label
	_host.settings_track_label = settings_vbox.get_node("SettingsTrackLabel") as Label
	_host.settings_volume_slider = settings_vbox.get_node("SettingsVolumeSlider") as HSlider
	_host.settings_volume_value_label = settings_vbox.get_node("SettingsVolumeValueLabel") as Label
	_host.settings_previous_button = settings_vbox.get_node("SettingsButtonRow/SettingsPreviousButton") as Button
	_host.settings_pause_button = settings_vbox.get_node("SettingsButtonRow/SettingsPauseButton") as Button
	_host.settings_next_button = settings_vbox.get_node("SettingsButtonRow/SettingsNextButton") as Button

	_host.species_gallery_overlay = _host.get_node("SpeciesGalleryOverlay")
	_host.species_gallery_tabs = _host.get_node("SpeciesGalleryOverlay/SpeciesGalleryCenter/SpeciesGalleryDialog/MarginContainer/SpeciesGalleryVBox/SpeciesGalleryTabs") as TabContainer
	_host.species_gallery_close_button = _host.get_node("SpeciesGalleryOverlay/SpeciesGalleryCenter/SpeciesGalleryDialog/MarginContainer/SpeciesGalleryVBox/SpeciesGalleryHeaderRow/SpeciesGalleryCloseButton") as Button

	_host.delete_overlay = _host.get_node("DeleteOverlay")
	var delete_vbox: Node = _host.get_node("DeleteOverlay/DeleteCenter/DeleteDialog/MarginContainer/DeleteVBox")
	_host.delete_confirm_label = delete_vbox.get_node("DeleteConfirmLabel") as Label
	_host.delete_cancel_button = delete_vbox.get_node("DeleteButtonRow/DeleteCancelButton") as Button
	_host.delete_confirm_button = delete_vbox.get_node("DeleteButtonRow/DeleteConfirmButton") as Button


func configure_widgets() -> void:
	_host.species_gallery_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_host.delete_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_host.settings_volume_slider.min_value = 0.0
	_host.settings_volume_slider.max_value = 1.0
	_host.settings_volume_slider.step = 0.01
	_host.settings_volume_slider.value = SettingsManager.get_music_volume()
	_host.ship_set_spin_box.min_value = 0.0
	_host.ship_set_spin_box.max_value = 999.0
	_host.ship_set_spin_box.step = 1.0
	_host.preset_list.fixed_icon_size = Vector2i(72, 72)
	_host.species_visuals_id_edit.editable = false
	_host.menu_portrait_path_edit.editable = false
	_host.leader_portraits_edit.editable = false
	_host.portrait_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_host.portrait_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_host.selected_species_category_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.biography_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.portrait_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.leader_portrait_preview_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.save_preset_button.custom_minimum_size = Vector2(220, 44)
	_host.clear_form_button.custom_minimum_size = Vector2(220, 44)

	var wide_controls: Array[Control] = [
		_host.preset_name_edit,
		_host.empire_name_edit,
		_host.species_name_edit,
		_host.species_plural_name_edit,
		_host.species_adjective_edit,
		_host.name_set_id_edit,
		_host.government_type_id_edit,
		_host.authority_type_id_edit,
		_host.civic_ids_edit,
		_host.flag_path_edit,
		_host.origin_id_edit,
		_host.starting_system_type_edit,
		_host.starting_planet_type_edit,
		_host.ship_set_spin_box,
		_host.color_picker_button,
	]
	for wide_control in wide_controls:
		wide_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
