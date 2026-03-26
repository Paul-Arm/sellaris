extends Node

signal playback_changed(track_name: String, paused: bool, volume_ratio: float, mode: String)

const MENU_LOOP_DIR := "res://music/Loops/ogg"
const GAME_TRACK_DIR := "res://music/Tracks/ogg"

var _player: AudioStreamPlayer
var _menu_tracks: Array[Dictionary] = []
var _game_tracks: Array[Dictionary] = []
var _mode: String = ""
var _current_track_name: String = ""
var _current_game_index: int = -1
var _volume_ratio: float = 0.7
var _menu_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_menu_rng.randomize()
	_menu_tracks = _load_tracks(MENU_LOOP_DIR, true)
	_game_tracks = _load_tracks(GAME_TRACK_DIR, false)

	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_on_player_finished)
	set_volume_ratio(_volume_ratio)
	_emit_playback_changed()


func play_menu_loops() -> void:
	if _menu_tracks.is_empty():
		return
	if _mode == "menu" and _player.playing:
		return
	_mode = "menu"
	_play_random_menu_track()


func play_game_tracks() -> void:
	if _game_tracks.is_empty():
		return
	if _mode == "game" and _player.playing:
		return
	_mode = "game"
	if _current_game_index < 0 or _current_game_index >= _game_tracks.size():
		_current_game_index = 0
	_play_game_track(_current_game_index)


func toggle_pause() -> void:
	if _player == null or _player.stream == null:
		return
	_player.stream_paused = not _player.stream_paused
	_emit_playback_changed()


func next_track() -> void:
	if _mode == "menu":
		_play_random_menu_track()
		return
	if _game_tracks.is_empty():
		return
	_current_game_index = (_current_game_index + 1) % _game_tracks.size()
	_play_game_track(_current_game_index)


func previous_track() -> void:
	if _mode == "menu":
		_play_random_menu_track()
		return
	if _game_tracks.is_empty():
		return
	_current_game_index = posmod(_current_game_index - 1, _game_tracks.size())
	_play_game_track(_current_game_index)


func set_volume_ratio(value: float) -> void:
	_volume_ratio = clampf(value, 0.0, 1.0)
	if _player != null:
		_player.volume_db = linear_to_db(maxf(_volume_ratio, 0.0001))
	_emit_playback_changed()


func get_volume_ratio() -> float:
	return _volume_ratio


func get_current_track_name() -> String:
	return _current_track_name


func is_paused() -> bool:
	return _player != null and _player.stream_paused


func get_mode() -> String:
	return _mode


func _on_player_finished() -> void:
	if _mode == "menu":
		_play_random_menu_track()
		return
	if _game_tracks.is_empty():
		return
	_current_game_index = (_current_game_index + 1) % _game_tracks.size()
	_play_game_track(_current_game_index)


func _play_random_menu_track() -> void:
	if _menu_tracks.is_empty():
		return
	var next_index: int = _menu_rng.randi_range(0, _menu_tracks.size() - 1)
	if _menu_tracks.size() > 1 and _current_track_name == _menu_tracks[next_index]["name"]:
		next_index = (next_index + 1) % _menu_tracks.size()
	_play_track_entry(_menu_tracks[next_index])


func _play_game_track(index: int) -> void:
	if index < 0 or index >= _game_tracks.size():
		return
	_play_track_entry(_game_tracks[index])


func _play_track_entry(track_entry: Dictionary) -> void:
	var stream: AudioStream = _load_audio_stream(str(track_entry.get("path", "")))
	if stream == null:
		return
	_player.stream = stream
	_player.stream_paused = false
	_player.play()
	_current_track_name = str(track_entry.get("name", "Unknown Track"))
	_emit_playback_changed()


func _emit_playback_changed() -> void:
	playback_changed.emit(_current_track_name, is_paused(), _volume_ratio, _mode)


func _load_audio_stream(resource_path: String) -> AudioStream:
	var absolute_path: String = ProjectSettings.globalize_path(resource_path)
	if resource_path.to_lower().ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(absolute_path)
	if resource_path.to_lower().ends_with(".mp3"):
		return AudioStreamMP3.load_from_file(absolute_path)
	return null


func _load_tracks(directory_path: String, strip_loop_suffix: bool) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var file_names: PackedStringArray = DirAccess.get_files_at(directory_path)
	file_names.sort()

	for file_name in file_names:
		if not file_name.to_lower().ends_with(".ogg"):
			continue
		var track_name: String = file_name.get_basename()
		if strip_loop_suffix:
			track_name = track_name.replace(" (Loop)", "")
		results.append({
			"path": "%s/%s" % [directory_path, file_name],
			"name": track_name,
		})

	return results
