extends Control
class_name SystemView

signal close_requested

const SPECIAL_TYPE_NONE := "none"
const SIM_SPEED_DISPLAY_STEPS := [0.5, 1.0, 2.0, 4.0]
const SIM_SPEED_ACTUAL_STEPS := [0.25, 0.5, 1.0, 2.0]

@onready var title_label: Label = get_node_or_null("HeaderMargin/HeaderRow/HeaderText/Title")
@onready var subtitle_label: Label = get_node_or_null("HeaderMargin/HeaderRow/HeaderText/Subtitle")
@onready var owner_label: Label = get_node_or_null("RightPanel/RightMargin/RightVBox/OwnerLabel")
@onready var summary_label: Label = get_node_or_null("RightPanel/RightMargin/RightVBox/SummaryLabel")
@onready var detail_label: Label = get_node_or_null("RightPanel/RightMargin/RightVBox/DetailLabel")
@onready var footer_label: Label = get_node_or_null("FooterMargin/FooterLabel")
@onready var close_button: Button = get_node_or_null("HeaderMargin/HeaderRow/CloseButton")
@onready var preview: StarSystemPreview = get_node_or_null("PreviewViewportContainer/PreviewViewport/StarSystemPreview")
@onready var galaxy_hud: Control = get_node_or_null("GalaxyHud")

var _current_system_id: String = ""
var _sim_speed_index: int = 0
var _sim_paused: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if close_button != null:
		close_button.pressed.connect(_on_close_pressed)
	if galaxy_hud != null:
		galaxy_hud.previous_track_requested.connect(_on_previous_track_pressed)
		galaxy_hud.pause_track_requested.connect(_on_pause_track_pressed)
		galaxy_hud.next_track_requested.connect(_on_next_track_pressed)
		galaxy_hud.music_hover_changed.connect(_on_music_hover_changed)
		galaxy_hud.music_volume_changed.connect(_on_music_volume_changed)
		galaxy_hud.close_settings_requested.connect(_on_close_settings_pressed)
		galaxy_hud.sim_pause_requested.connect(_on_sim_pause_pressed)
		galaxy_hud.sim_speed_requested.connect(_on_sim_speed_pressed)
	MusicManager.playback_changed.connect(_on_music_playback_changed)
	SimClock.day_tick.connect(_on_sim_day_tick)
	SimClock.month_tick.connect(_on_sim_month_tick)
	SimClock.year_tick.connect(_on_sim_year_tick)
	_sync_music_ui()
	_sync_sim_clock_ui()
	if galaxy_hud != null:
		galaxy_hud.set_settings_visible(false)
		galaxy_hud.set_music_track_visibility(false)


func show_system(system_details: Dictionary, neighbor_count: int) -> void:
	_current_system_id = str(system_details.get("id", ""))
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	if system_details.is_empty():
		_set_label_text(title_label, "Unknown System")
		_set_label_text(subtitle_label, "")
		_set_label_text(owner_label, "Owner: Unknown")
		_set_label_text(summary_label, "")
		_set_label_text(detail_label, "")
		_set_label_text(footer_label, "Esc closes the system view.")
		if preview != null:
			preview.clear_preview()
		return

	var summary: Dictionary = system_details.get("system_summary", {})
	var star_profile: Dictionary = system_details.get("star_profile", {})
	var owner_name: String = str(system_details.get("owner_name", "Unclaimed"))
	var star_class: String = str(summary.get("star_class", star_profile.get("star_class", "G")))
	var star_count: int = int(summary.get("star_count", star_profile.get("star_count", 1)))
	var special_type: String = str(summary.get("special_type", star_profile.get("special_type", SPECIAL_TYPE_NONE)))
	var special_text := ""
	if special_type != SPECIAL_TYPE_NONE:
		special_text = "  Special: %s" % special_type

	_set_label_text(title_label, str(system_details.get("name", _current_system_id)))
	_set_label_text(subtitle_label, "System View")
	_set_label_text(owner_label, "Owner: %s" % owner_name)
	_set_label_text(summary_label, "Star Class: %s  Stars: %d%s\nHyperlane Connections: %d" % [
		star_class,
		star_count,
		special_text,
		neighbor_count,
	])
	_set_label_text(detail_label, "Planets: %d\nAsteroid Belts: %d\nStructures: %d\nRuins: %d\nHabitable Worlds: %d\nColonizable Worlds: %d\nAnomaly Risk: %d%%" % [
		int(summary.get("planet_count", 0)),
		int(summary.get("asteroid_belt_count", 0)),
		int(summary.get("structure_count", 0)),
		int(summary.get("ruin_count", 0)),
		int(summary.get("habitable_worlds", 0)),
		int(summary.get("colonizable_worlds", 0)),
		int(round(float(summary.get("anomaly_risk", 0.0)) * 100.0)),
	])
	_set_label_text(footer_label, "Esc returns to the galaxy view.")
	if preview != null:
		preview.set_system_details(system_details)


func hide_view() -> void:
	_current_system_id = ""
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if galaxy_hud != null:
		galaxy_hud.set_settings_visible(false)
	if preview != null:
		preview.clear_preview()


func handle_view_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		handle_cancel_action()
		return
	preview.forward_input(event)


func is_open() -> bool:
	return visible


func get_current_system_id() -> String:
	return _current_system_id


func handle_cancel_action() -> bool:
	if not visible:
		return false
	if galaxy_hud != null and galaxy_hud.is_settings_visible():
		galaxy_hud.set_settings_visible(false)
		get_viewport().set_input_as_handled()
		return false
	get_viewport().set_input_as_handled()
	return true


func _on_close_pressed() -> void:
	close_requested.emit()


func _sync_music_ui() -> void:
	if galaxy_hud == null:
		return
	var track_name: String = MusicManager.get_current_track_name()
	if track_name.is_empty():
		track_name = "No Track"
	galaxy_hud.set_music_ui(track_name, MusicManager.is_paused(), MusicManager.get_volume_ratio())


func _sync_sim_clock_ui() -> void:
	if galaxy_hud == null:
		return
	var current_speed: float = SimClock.sim_speed
	_sim_paused = current_speed <= 0.0
	if not _sim_paused:
		var best_index := 0
		var best_distance := INF
		for speed_index in range(SIM_SPEED_ACTUAL_STEPS.size()):
			var distance: float = absf(SIM_SPEED_ACTUAL_STEPS[speed_index] - current_speed)
			if distance < best_distance:
				best_distance = distance
				best_index = speed_index
		_sim_speed_index = best_index

	var current_date: Dictionary = SimClock.get_current_date()
	var date_text := "%04d-%02d-%02d" % [
		int(current_date.get("year", 0)),
		int(current_date.get("month", 0)),
		int(current_date.get("day", 0)),
	]
	var speed_value: float = SIM_SPEED_DISPLAY_STEPS[_sim_speed_index]
	var speed_text := "Paused" if _sim_paused else "x%s" % _format_speed_factor(speed_value)
	galaxy_hud.set_sim_ui(date_text, speed_text, _sim_paused)


func _format_speed_factor(speed_value: float) -> String:
	if is_equal_approx(speed_value, round(speed_value)):
		return str(int(round(speed_value)))
	return str(snappedf(speed_value, 0.1))


func _on_music_playback_changed(_track_name: String, _paused: bool, _volume_ratio: float, _mode: String) -> void:
	_sync_music_ui()


func _on_music_hover_changed(hovered: bool) -> void:
	if galaxy_hud != null:
		galaxy_hud.set_music_track_visibility(hovered)


func _on_previous_track_pressed() -> void:
	MusicManager.previous_track()


func _on_pause_track_pressed() -> void:
	MusicManager.toggle_pause()


func _on_next_track_pressed() -> void:
	MusicManager.next_track()


func _on_music_volume_changed(value: float) -> void:
	MusicManager.set_volume_ratio(value)
	_sync_music_ui()


func _on_close_settings_pressed() -> void:
	if galaxy_hud != null:
		galaxy_hud.set_settings_visible(false)


func _on_sim_pause_pressed() -> void:
	if _sim_paused:
		SimClock.set_sim_speed(SIM_SPEED_ACTUAL_STEPS[_sim_speed_index])
	else:
		SimClock.pause_sim()
	_sync_sim_clock_ui()


func _on_sim_speed_pressed() -> void:
	_sim_speed_index = (_sim_speed_index + 1) % SIM_SPEED_ACTUAL_STEPS.size()
	SimClock.set_sim_speed(SIM_SPEED_ACTUAL_STEPS[_sim_speed_index])
	_sync_sim_clock_ui()


func _on_sim_day_tick(_date: Dictionary) -> void:
	_sync_sim_clock_ui()


func _on_sim_month_tick(_year: int, _month: int) -> void:
	_sync_sim_clock_ui()


func _on_sim_year_tick(_year: int) -> void:
	_sync_sim_clock_ui()


func _set_label_text(label: Label, value: String) -> void:
	if label != null:
		label.text = value
