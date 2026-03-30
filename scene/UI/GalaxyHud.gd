extends Control

signal previous_track_requested
signal pause_track_requested
signal next_track_requested
signal music_hover_changed(hovered: bool)
signal music_volume_changed(value: float)
signal close_settings_requested
signal sim_pause_requested
signal sim_speed_requested
signal territory_bright_rim_toggled(enabled: bool)
signal territory_core_opacity_changed(value: float)

@onready var settings_overlay: Control = $SettingsOverlay
@onready var settings_music_volume_slider: HSlider = $SettingsOverlay/Panel/MarginContainer/VBoxContainer/MusicVolumeSlider
@onready var territory_bright_rim_check_box: CheckBox = $SettingsOverlay/Panel/MarginContainer/VBoxContainer/TerritoryBrightRimCheckBox
@onready var territory_core_opacity_slider: HSlider = $SettingsOverlay/Panel/MarginContainer/VBoxContainer/TerritoryCoreOpacitySlider
@onready var close_settings_button: Button = $SettingsOverlay/Panel/MarginContainer/VBoxContainer/CloseSettingsButton
@onready var music_box: Control = $TopPanel/MarginContainer/TopBarRow/MusicBox
@onready var music_track_label: Label = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin/MusicRow/MusicTrackLabel
@onready var previous_track_button: Button = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin/MusicRow/PreviousTrackButton
@onready var pause_track_button: Button = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin/MusicRow/PauseTrackButton
@onready var next_track_button: Button = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin/MusicRow/NextTrackButton
@onready var top_music_volume_slider: HSlider = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin/MusicRow/MusicVolumeSlider
@onready var sim_date_label: Label = $TopPanel/MarginContainer/TopBarRow/SimBox/SimMargin/SimRow/SimDateLabel
@onready var sim_pause_button: Button = $TopPanel/MarginContainer/TopBarRow/SimBox/SimMargin/SimRow/SimPauseButton
@onready var sim_speed_button: Button = $TopPanel/MarginContainer/TopBarRow/SimBox/SimMargin/SimRow/SimSpeedButton

var _is_syncing: bool = false


func _ready() -> void:
	previous_track_button.pressed.connect(func() -> void: previous_track_requested.emit())
	pause_track_button.pressed.connect(func() -> void: pause_track_requested.emit())
	next_track_button.pressed.connect(func() -> void: next_track_requested.emit())
	music_box.mouse_entered.connect(func() -> void: music_hover_changed.emit(true))
	music_box.mouse_exited.connect(func() -> void: music_hover_changed.emit(false))
	top_music_volume_slider.value_changed.connect(_on_music_volume_slider_changed)
	settings_music_volume_slider.value_changed.connect(_on_music_volume_slider_changed)
	territory_bright_rim_check_box.toggled.connect(_on_territory_bright_rim_toggled)
	territory_core_opacity_slider.value_changed.connect(_on_territory_core_opacity_slider_changed)
	close_settings_button.pressed.connect(func() -> void: close_settings_requested.emit())
	sim_pause_button.pressed.connect(func() -> void: sim_pause_requested.emit())
	sim_speed_button.pressed.connect(func() -> void: sim_speed_requested.emit())


func is_settings_visible() -> bool:
	return settings_overlay.visible


func set_settings_visible(visible_state: bool) -> void:
	settings_overlay.visible = visible_state


func set_music_ui(track_name: String, paused: bool, volume_ratio: float) -> void:
	_is_syncing = true
	music_track_label.text = "Music: %s" % track_name
	pause_track_button.text = "Resume" if paused else "Pause"
	top_music_volume_slider.value = volume_ratio
	settings_music_volume_slider.value = volume_ratio
	_is_syncing = false


func set_territory_ui(bright_rim_enabled: bool, core_opacity: float) -> void:
	_is_syncing = true
	territory_bright_rim_check_box.button_pressed = bright_rim_enabled
	territory_core_opacity_slider.value = core_opacity
	_is_syncing = false


func set_music_track_visibility(visible_state: bool) -> void:
	music_track_label.visible = visible_state


func set_sim_ui(date_text: String, speed_text: String, paused: bool) -> void:
	sim_date_label.text = "%s  %s" % [date_text, speed_text]
	sim_pause_button.text = "Play" if paused else "Pause"


func _on_music_volume_slider_changed(value: float) -> void:
	if _is_syncing:
		return
	music_volume_changed.emit(value)


func _on_territory_bright_rim_toggled(enabled: bool) -> void:
	if _is_syncing:
		return
	territory_bright_rim_toggled.emit(enabled)


func _on_territory_core_opacity_slider_changed(value: float) -> void:
	if _is_syncing:
		return
	territory_core_opacity_changed.emit(value)
