extends RefCounted

var _galaxy_hud


func bind(galaxy_hud) -> void:
	if _galaxy_hud == galaxy_hud:
		_sync_music_ui()
		return

	unbind()
	_galaxy_hud = galaxy_hud
	if _galaxy_hud == null:
		return

	_galaxy_hud.previous_track_requested.connect(_on_previous_track_pressed)
	_galaxy_hud.pause_track_requested.connect(_on_pause_track_pressed)
	_galaxy_hud.next_track_requested.connect(_on_next_track_pressed)
	_galaxy_hud.music_hover_changed.connect(_on_music_hover_changed)
	_galaxy_hud.music_volume_changed.connect(_on_music_volume_changed)
	MusicManager.playback_changed.connect(_on_music_playback_changed)
	MusicManager.play_game_tracks()
	_sync_music_ui()


func unbind() -> void:
	if _galaxy_hud != null:
		if _galaxy_hud.previous_track_requested.is_connected(_on_previous_track_pressed):
			_galaxy_hud.previous_track_requested.disconnect(_on_previous_track_pressed)
		if _galaxy_hud.pause_track_requested.is_connected(_on_pause_track_pressed):
			_galaxy_hud.pause_track_requested.disconnect(_on_pause_track_pressed)
		if _galaxy_hud.next_track_requested.is_connected(_on_next_track_pressed):
			_galaxy_hud.next_track_requested.disconnect(_on_next_track_pressed)
		if _galaxy_hud.music_hover_changed.is_connected(_on_music_hover_changed):
			_galaxy_hud.music_hover_changed.disconnect(_on_music_hover_changed)
		if _galaxy_hud.music_volume_changed.is_connected(_on_music_volume_changed):
			_galaxy_hud.music_volume_changed.disconnect(_on_music_volume_changed)

	if MusicManager.playback_changed.is_connected(_on_music_playback_changed):
		MusicManager.playback_changed.disconnect(_on_music_playback_changed)

	_galaxy_hud = null


func _sync_music_ui() -> void:
	if _galaxy_hud == null:
		return

	var track_name: String = MusicManager.get_current_track_name()
	if track_name.is_empty():
		track_name = "No Track"
	var volume_ratio: float = MusicManager.get_volume_ratio()
	_galaxy_hud.set_music_ui(track_name, MusicManager.is_paused(), volume_ratio)


func _set_music_track_visibility(visible_state: bool) -> void:
	if _galaxy_hud == null:
		return
	_galaxy_hud.set_music_track_visibility(visible_state)


func _on_music_playback_changed(_track_name: String, _paused: bool, _volume_ratio: float, _mode: String) -> void:
	_sync_music_ui()


func _on_music_hover_changed(hovered: bool) -> void:
	_set_music_track_visibility(hovered)


func _on_previous_track_pressed() -> void:
	MusicManager.previous_track()


func _on_pause_track_pressed() -> void:
	MusicManager.toggle_pause()


func _on_next_track_pressed() -> void:
	MusicManager.next_track()


func _on_music_volume_changed(value: float) -> void:
	MusicManager.set_volume_ratio(value)
	_sync_music_ui()
