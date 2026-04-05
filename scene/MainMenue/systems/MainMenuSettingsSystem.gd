extends RefCounted

const RESOLUTION_OPTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

var _host: Control = null


func bind(host: Control) -> void:
	_host = host


func unbind() -> void:
	_host = null


func populate_settings_options() -> void:
	_host.settings_window_mode_option.clear()
	_add_option_with_metadata(_host.settings_window_mode_option, "Windowed", DisplayServer.WINDOW_MODE_WINDOWED)
	_add_option_with_metadata(_host.settings_window_mode_option, "Maximized", DisplayServer.WINDOW_MODE_MAXIMIZED)
	_add_option_with_metadata(_host.settings_window_mode_option, "Fullscreen", DisplayServer.WINDOW_MODE_FULLSCREEN)
	_add_option_with_metadata(_host.settings_window_mode_option, "Exclusive Fullscreen", DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	_host.settings_resolution_option.clear()
	for resolution in RESOLUTION_OPTIONS:
		_add_option_with_metadata(_host.settings_resolution_option, "%dx%d" % [resolution.x, resolution.y], resolution)

	_host.settings_aa_option.clear()
	_add_option_with_metadata(_host.settings_aa_option, "Off", Viewport.MSAA_DISABLED)
	_add_option_with_metadata(_host.settings_aa_option, "2x MSAA", Viewport.MSAA_2X)
	_add_option_with_metadata(_host.settings_aa_option, "4x MSAA", Viewport.MSAA_4X)
	_add_option_with_metadata(_host.settings_aa_option, "8x MSAA", Viewport.MSAA_8X)


func refresh_display_settings() -> void:
	_host._is_syncing_settings_ui = true
	_select_option_by_metadata(_host.settings_window_mode_option, SettingsManager.get_window_mode())
	_select_option_by_resolution(SettingsManager.get_resolution())
	_select_option_by_metadata(_host.settings_aa_option, SettingsManager.get_msaa())
	_host._is_syncing_settings_ui = false


func refresh_music_settings() -> void:
	var track_name: String = MusicManager.get_current_track_name()
	if track_name.is_empty():
		track_name = "Menu ambience idle"
	_host.settings_track_label.text = "Current Track: %s" % track_name
	_host.settings_volume_slider.value = MusicManager.get_volume_ratio()
	_host.settings_volume_value_label.text = "Volume: %d%%" % int(round(MusicManager.get_volume_ratio() * 100.0))


func on_settings_volume_changed(value: float) -> void:
	SettingsManager.set_music_volume(value)
	_host.settings_volume_value_label.text = "Volume: %d%%" % int(round(value * 100.0))


func on_window_mode_selected(index: int) -> void:
	if _host._is_syncing_settings_ui:
		return
	SettingsManager.set_window_mode(int(_host.settings_window_mode_option.get_item_metadata(index)))
	_host.settings_status_label.text = "Saved window mode: %s." % _host.settings_window_mode_option.get_item_text(index)
	refresh_display_settings()


func on_resolution_selected(index: int) -> void:
	if _host._is_syncing_settings_ui:
		return
	var metadata: Variant = _host.settings_resolution_option.get_item_metadata(index)
	if metadata is not Vector2i:
		return
	SettingsManager.set_resolution(metadata as Vector2i)
	_host.settings_status_label.text = "Saved resolution: %s." % _host.settings_resolution_option.get_item_text(index)
	refresh_display_settings()


func on_aa_selected(index: int) -> void:
	if _host._is_syncing_settings_ui:
		return
	SettingsManager.set_msaa(int(_host.settings_aa_option.get_item_metadata(index)))
	_host.settings_status_label.text = "Saved anti-aliasing: %s." % _host.settings_aa_option.get_item_text(index)
	refresh_display_settings()


func on_music_playback_changed(_track_name: String, _paused: bool, _volume_ratio: float, _mode: String) -> void:
	refresh_music_settings()


func _add_option_with_metadata(option_button: OptionButton, label: String, metadata: Variant) -> void:
	option_button.add_item(label)
	option_button.set_item_metadata(option_button.get_item_count() - 1, metadata)


func _select_option_by_metadata(option_button: OptionButton, expected_metadata: Variant) -> void:
	for option_index in range(option_button.get_item_count()):
		if option_button.get_item_metadata(option_index) == expected_metadata:
			option_button.select(option_index)
			return


func _select_option_by_resolution(expected_resolution: Vector2i) -> void:
	for option_index in range(_host.settings_resolution_option.get_item_count()):
		var metadata: Variant = _host.settings_resolution_option.get_item_metadata(option_index)
		if metadata is Vector2i and metadata == expected_resolution:
			_host.settings_resolution_option.select(option_index)
			return

	_add_option_with_metadata(
		_host.settings_resolution_option,
		"%dx%d" % [expected_resolution.x, expected_resolution.y],
		expected_resolution
	)
	_host.settings_resolution_option.select(_host.settings_resolution_option.get_item_count() - 1)
