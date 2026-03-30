extends Node

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_MUSIC_VOLUME := 0.7
const DEFAULT_WINDOW_MODE := DisplayServer.WINDOW_MODE_MAXIMIZED
const DEFAULT_RESOLUTION := Vector2i(1920, 1080)
const DEFAULT_MSAA := Viewport.MSAA_2X

var _music_volume: float = DEFAULT_MUSIC_VOLUME
var _window_mode: int = DEFAULT_WINDOW_MODE
var _resolution: Vector2i = DEFAULT_RESOLUTION
var _msaa: int = DEFAULT_MSAA


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	var load_error: Error = config.load(SETTINGS_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		push_warning("Failed to load settings from %s with error %d." % [SETTINGS_PATH, load_error])

	_music_volume = clampf(float(config.get_value("audio", "music_volume", DEFAULT_MUSIC_VOLUME)), 0.0, 1.0)
	_window_mode = _normalize_window_mode(config.get_value("display", "window_mode", DEFAULT_WINDOW_MODE))
	_resolution = _normalize_resolution(config.get_value("display", "resolution", DEFAULT_RESOLUTION))
	_msaa = _normalize_msaa(config.get_value("display", "msaa", DEFAULT_MSAA))

	_apply_audio_settings()
	_apply_display_settings()

	if load_error == ERR_FILE_NOT_FOUND:
		save_settings()


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("audio", "music_volume", _music_volume)
	config.set_value("display", "window_mode", _window_mode)
	config.set_value("display", "resolution", _resolution)
	config.set_value("display", "msaa", _msaa)
	return config.save(SETTINGS_PATH)


func get_music_volume() -> float:
	return _music_volume


func set_music_volume(value: float) -> void:
	_music_volume = clampf(value, 0.0, 1.0)
	_apply_audio_settings()
	save_settings()


func get_window_mode() -> int:
	return _window_mode


func set_window_mode(mode: int) -> void:
	_window_mode = _normalize_window_mode(mode)
	_apply_display_settings()
	save_settings()


func get_resolution() -> Vector2i:
	return _resolution


func set_resolution(value: Vector2i) -> void:
	_resolution = _normalize_resolution(value)
	_apply_display_settings()
	save_settings()


func get_msaa() -> int:
	return _msaa


func set_msaa(value: int) -> void:
	_msaa = _normalize_msaa(value)
	_apply_display_settings()
	save_settings()


func _apply_audio_settings() -> void:
	MusicManager.set_volume_ratio(_music_volume)


func _apply_display_settings() -> void:
	if _is_headless():
		return

	var root_window: Window = get_tree().root
	root_window.msaa_2d = _msaa
	root_window.msaa_3d = _msaa

	match _window_mode:
		DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(_resolution)
			_center_window()
		DisplayServer.WINDOW_MODE_MAXIMIZED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(_resolution)
			_center_window()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_:
			DisplayServer.window_set_mode(_window_mode)


func _center_window() -> void:
	if _is_headless():
		return

	var screen_index: int = DisplayServer.window_get_current_screen()
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_index)
	var screen_position: Vector2i = DisplayServer.screen_get_position(screen_index)
	var centered_position := screen_position + Vector2i(
		maxi(0, int((screen_size.x - _resolution.x) / 2.0)),
		maxi(0, int((screen_size.y - _resolution.y) / 2.0))
	)
	DisplayServer.window_set_position(centered_position)


func _normalize_window_mode(value: Variant) -> int:
	var mode: int = DEFAULT_WINDOW_MODE
	if value is int:
		mode = int(value)

	match mode:
		DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return mode
		_:
			return DEFAULT_WINDOW_MODE


func _normalize_resolution(value: Variant) -> Vector2i:
	if value is Vector2i:
		return _clamp_resolution(value)
	if value is Vector2:
		var source := value as Vector2
		return _clamp_resolution(Vector2i(roundi(source.x), roundi(source.y)))
	return DEFAULT_RESOLUTION


func _clamp_resolution(value: Vector2i) -> Vector2i:
	return Vector2i(maxi(value.x, 960), maxi(value.y, 540))


func _normalize_msaa(value: Variant) -> int:
	var msaa: int = DEFAULT_MSAA
	if value is int:
		msaa = int(value)

	match msaa:
		Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X:
			return msaa
		_:
			return DEFAULT_MSAA


func _is_headless() -> bool:
	return DisplayServer.get_name().to_lower() == "headless"
