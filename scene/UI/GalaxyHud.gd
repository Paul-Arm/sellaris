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

const CHROME_SCRIPT: Script = preload("res://scene/UI/GalaxyHudChrome.gd")
const RESOURCE_DISPLAY_ORDER: Array[String] = [
	"matter",
	"energy",
	"food",
	"alloys",
	"exotic_gases",
	"living_metal",
	"dark_matter",
]
const ALWAYS_VISIBLE_RESOURCE_IDS := {
	"matter": true,
	"energy": true,
	"food": true,
	"alloys": true,
}
const RESOURCE_DISPLAY_NAMES := {
	"matter": "Matter",
	"energy": "Energy",
	"food": "Food",
	"alloys": "Alloys",
	"exotic_gases": "Exotic Gases",
	"living_metal": "Living Metal",
	"dark_matter": "Dark Matter",
}
const RESOURCE_SHORT_NAMES := {
	"matter": "Matter",
	"energy": "Energy",
	"food": "Food",
	"alloys": "Alloys",
	"exotic_gases": "Gas",
	"living_metal": "Metal",
	"dark_matter": "Dark",
}

@onready var settings_overlay: Control = $SettingsOverlay
@onready var settings_music_volume_slider: HSlider = $SettingsOverlay/Panel/MarginContainer/VBoxContainer/MusicVolumeSlider
@onready var territory_bright_rim_check_box: CheckBox = $SettingsOverlay/Panel/MarginContainer/VBoxContainer/TerritoryBrightRimCheckBox
@onready var territory_core_opacity_slider: HSlider = $SettingsOverlay/Panel/MarginContainer/VBoxContainer/TerritoryCoreOpacitySlider
@onready var close_settings_button: Button = $SettingsOverlay/Panel/MarginContainer/VBoxContainer/CloseSettingsButton
@onready var top_panel: Panel = $TopPanel
@onready var top_margin: MarginContainer = $TopPanel/MarginContainer
@onready var top_bar_row: HBoxContainer = $TopPanel/MarginContainer/TopBarRow
@onready var resource_box: PanelContainer = $TopPanel/MarginContainer/TopBarRow/ResourceBox
@onready var resource_margin: MarginContainer = $TopPanel/MarginContainer/TopBarRow/ResourceBox/ResourceMargin
@onready var resource_row: HBoxContainer = $TopPanel/MarginContainer/TopBarRow/ResourceBox/ResourceMargin/ResourceRow
@onready var music_box: PanelContainer = $TopPanel/MarginContainer/TopBarRow/MusicBox
@onready var music_margin: MarginContainer = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin
@onready var music_row: HBoxContainer = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin/MusicRow
@onready var music_track_label: Label = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin/MusicRow/MusicTrackLabel
@onready var previous_track_button: Button = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin/MusicRow/PreviousTrackButton
@onready var pause_track_button: Button = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin/MusicRow/PauseTrackButton
@onready var next_track_button: Button = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin/MusicRow/NextTrackButton
@onready var top_music_volume_slider: HSlider = $TopPanel/MarginContainer/TopBarRow/MusicBox/MusicMargin/MusicRow/MusicVolumeSlider
@onready var sim_box: PanelContainer = $TopPanel/MarginContainer/TopBarRow/SimBox
@onready var sim_margin: MarginContainer = $TopPanel/MarginContainer/TopBarRow/SimBox/SimMargin
@onready var sim_row: HBoxContainer = $TopPanel/MarginContainer/TopBarRow/SimBox/SimMargin/SimRow
@onready var sim_date_label: Label = $TopPanel/MarginContainer/TopBarRow/SimBox/SimMargin/SimRow/SimDateLabel
@onready var sim_pause_button: Button = $TopPanel/MarginContainer/TopBarRow/SimBox/SimMargin/SimRow/SimPauseButton
@onready var sim_speed_button: Button = $TopPanel/MarginContainer/TopBarRow/SimBox/SimMargin/SimRow/SimSpeedButton

var _is_syncing: bool = false
var _top_chrome: GalaxyHudChrome = null
var _active_empire_id: String = ""
var _resource_chip_nodes: Dictionary = {}
var _resource_icon_textures: Dictionary = {}
var _resource_refresh_queued: bool = false


func _ready() -> void:
	_install_top_chrome()
	_apply_top_bar_theme()
	_setup_resource_signals()
	_rebuild_resource_chips()
	_refresh_resource_ui()

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


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _top_chrome != null:
		call_deferred("_sync_top_chrome_bounds")


func is_settings_visible() -> bool:
	return settings_overlay.visible


func set_settings_visible(visible_state: bool) -> void:
	settings_overlay.visible = visible_state


func set_active_empire(empire_id: String) -> void:
	var normalized_empire_id := empire_id.strip_edges()
	if _active_empire_id == normalized_empire_id:
		_queue_resource_refresh()
		return
	_active_empire_id = normalized_empire_id
	_queue_resource_refresh()


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


func _install_top_chrome() -> void:
	_top_chrome = CHROME_SCRIPT.new() as GalaxyHudChrome
	_top_chrome.name = "TopChrome"
	_top_chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	_top_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_panel.add_child(_top_chrome)
	top_panel.move_child(_top_chrome, 0)


func _apply_top_bar_theme() -> void:
	top_panel.anchor_left = 0.0
	top_panel.anchor_top = 0.0
	top_panel.anchor_right = 1.0
	top_panel.anchor_bottom = 0.0
	top_panel.offset_left = 0.0
	top_panel.offset_top = 0.0
	top_panel.offset_right = 0.0
	top_panel.offset_bottom = 54.0
	top_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	top_margin.add_theme_constant_override("margin_left", 18)
	top_margin.add_theme_constant_override("margin_top", 8)
	top_margin.add_theme_constant_override("margin_right", 18)
	top_margin.add_theme_constant_override("margin_bottom", 8)
	top_bar_row.add_theme_constant_override("separation", 8)
	top_bar_row.alignment = BoxContainer.ALIGNMENT_END

	resource_box.custom_minimum_size = Vector2(382.0, 0.0)
	resource_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	resource_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	resource_box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	resource_margin.add_theme_constant_override("margin_left", 4)
	resource_margin.add_theme_constant_override("margin_top", 0)
	resource_margin.add_theme_constant_override("margin_right", 4)
	resource_margin.add_theme_constant_override("margin_bottom", 0)
	resource_row.add_theme_constant_override("separation", 6)
	resource_row.alignment = BoxContainer.ALIGNMENT_CENTER

	music_box.custom_minimum_size = Vector2(226.0, 0.0)
	music_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	music_box.add_theme_stylebox_override("panel", _build_hud_segment_style(Color(0.04, 0.055, 0.07, 0.56), Color(0.32, 0.55, 0.68, 0.22)))
	music_margin.add_theme_constant_override("margin_left", 9)
	music_margin.add_theme_constant_override("margin_top", 4)
	music_margin.add_theme_constant_override("margin_right", 9)
	music_margin.add_theme_constant_override("margin_bottom", 4)
	music_row.add_theme_constant_override("separation", 6)

	sim_box.custom_minimum_size = Vector2(252.0, 0.0)
	sim_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sim_box.add_theme_stylebox_override("panel", _build_hud_segment_style(Color(0.04, 0.055, 0.07, 0.6), Color(0.58, 0.42, 0.64, 0.28)))
	sim_margin.add_theme_constant_override("margin_left", 10)
	sim_margin.add_theme_constant_override("margin_top", 4)
	sim_margin.add_theme_constant_override("margin_right", 10)
	sim_margin.add_theme_constant_override("margin_bottom", 4)
	sim_row.add_theme_constant_override("separation", 7)

	music_track_label.add_theme_color_override("font_color", Color(0.84, 0.91, 0.94, 0.9))
	music_track_label.add_theme_font_size_override("font_size", 13)
	music_track_label.custom_minimum_size = Vector2(98.0, 0.0)
	sim_date_label.add_theme_color_override("font_color", Color(0.93, 0.96, 0.98, 0.95))
	sim_date_label.add_theme_font_size_override("font_size", 13)
	sim_date_label.custom_minimum_size = Vector2(128.0, 0.0)

	_style_hud_button(previous_track_button, 28)
	_style_hud_button(pause_track_button, 54)
	_style_hud_button(next_track_button, 28)
	_style_hud_button(sim_pause_button, 52)
	_style_hud_button(sim_speed_button, 32)

	top_music_volume_slider.custom_minimum_size = Vector2(66.0, 0.0)
	top_music_volume_slider.add_theme_stylebox_override("slider", _build_slider_style(Color(0.1, 0.15, 0.18, 0.86), Color(0.36, 0.58, 0.7, 0.28)))
	top_music_volume_slider.add_theme_stylebox_override("grabber_area", _build_slider_style(Color(0.54, 0.82, 0.98, 0.34), Color(0.58, 0.86, 1.0, 0.5)))
	top_music_volume_slider.add_theme_icon_override("grabber", _get_slider_grabber_icon())
	top_music_volume_slider.add_theme_icon_override("grabber_highlight", _get_slider_grabber_icon(Color(0.86, 0.96, 1.0, 1.0)))

	if _top_chrome != null:
		_top_chrome.set_accent(Color(0.58, 0.42, 0.64, 1.0))
	call_deferred("_sync_top_chrome_bounds")


func _setup_resource_signals() -> void:
	if not EconomyManager.registry_loaded.is_connected(_on_economy_registry_loaded):
		EconomyManager.registry_loaded.connect(_on_economy_registry_loaded)
	if not EconomyManager.economy_bootstrapped.is_connected(_on_economy_bootstrapped):
		EconomyManager.economy_bootstrapped.connect(_on_economy_bootstrapped)
	if not EconomyManager.empire_stockpile_changed.is_connected(_on_empire_stockpile_changed):
		EconomyManager.empire_stockpile_changed.connect(_on_empire_stockpile_changed)
	if not EconomyManager.monthly_settlement_completed.is_connected(_on_monthly_settlement_completed):
		EconomyManager.monthly_settlement_completed.connect(_on_monthly_settlement_completed)
	if not EconomyManager.source_registered.is_connected(_on_economy_source_changed):
		EconomyManager.source_registered.connect(_on_economy_source_changed)
	if not EconomyManager.source_removed.is_connected(_on_economy_source_changed):
		EconomyManager.source_removed.connect(_on_economy_source_changed)


func _rebuild_resource_chips() -> void:
	for child in resource_row.get_children():
		resource_row.remove_child(child)
		child.queue_free()
	_resource_chip_nodes.clear()

	for resource_id in _get_display_resource_ids():
		var accent := _get_resource_accent(resource_id)
		var chip := PanelContainer.new()
		chip.name = "%s_resource_chip" % resource_id
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = "%s stockpile and projected monthly net." % _get_resource_display_name(resource_id)
		chip.add_theme_stylebox_override("panel", _build_resource_chip_style(accent, false, false))

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 7)
		margin.add_theme_constant_override("margin_top", 3)
		margin.add_theme_constant_override("margin_right", 7)
		margin.add_theme_constant_override("margin_bottom", 3)
		chip.add_child(margin)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		margin.add_child(row)

		var icon := TextureRect.new()
		icon.texture = _get_resource_icon_texture(resource_id)
		icon.custom_minimum_size = Vector2(16.0, 16.0)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)

		var name_label := Label.new()
		name_label.text = _get_resource_short_name(resource_id)
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", Color(0.86, 0.92, 0.95, 0.9))
		row.add_child(name_label)

		var amount_label := Label.new()
		amount_label.custom_minimum_size = Vector2(42.0, 0.0)
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_label.add_theme_font_size_override("font_size", 12)
		amount_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 0.96))
		row.add_child(amount_label)

		var net_label := Label.new()
		net_label.custom_minimum_size = Vector2(48.0, 0.0)
		net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		net_label.add_theme_font_size_override("font_size", 11)
		row.add_child(net_label)

		resource_row.add_child(chip)
		_resource_chip_nodes[resource_id] = {
			"chip": chip,
			"amount_label": amount_label,
			"net_label": net_label,
		}


func _refresh_resource_ui() -> void:
	_resource_refresh_queued = false
	if not is_node_ready():
		return

	var desired_resource_ids := _get_display_resource_ids()
	if not _resource_chip_set_matches(desired_resource_ids):
		_rebuild_resource_chips()
		call_deferred("_sync_top_chrome_bounds")

	var has_active_empire := not _active_empire_id.is_empty()
	var stockpile := EconomyManager.get_stockpile_map(_active_empire_id) if has_active_empire else {}
	var monthly_net := EconomyManager.get_projected_monthly_net_map(_active_empire_id) if has_active_empire else {}
	resource_box.tooltip_text = "Resources for the active empire." if has_active_empire else "No active empire selected."

	for resource_id_variant in _resource_chip_nodes.keys():
		var resource_id := str(resource_id_variant)
		var nodes: Dictionary = _resource_chip_nodes[resource_id]
		var amount_label := nodes.get("amount_label", null) as Label
		var net_label := nodes.get("net_label", null) as Label
		var chip := nodes.get("chip", null) as PanelContainer
		var amount := int(stockpile.get(resource_id, 0))
		var net := int(monthly_net.get(resource_id, 0))
		if amount_label != null:
			amount_label.text = _format_resource_amount(amount) if has_active_empire else "--"
		if net_label != null:
			net_label.text = _format_resource_delta(net) if has_active_empire else ""
			net_label.add_theme_color_override("font_color", _get_delta_color(net, has_active_empire))
		if chip != null:
			chip.add_theme_stylebox_override(
				"panel",
				_build_resource_chip_style(_get_resource_accent(resource_id), has_active_empire, net < 0)
			)


func _queue_resource_refresh() -> void:
	if not is_node_ready():
		return
	if _resource_refresh_queued:
		return
	_resource_refresh_queued = true
	call_deferred("_refresh_resource_ui")


func _sync_top_chrome_bounds() -> void:
	if _top_chrome == null or not is_node_ready():
		return

	var chrome_rect := _top_chrome.get_global_rect()
	var left_edge := INF
	var right_edge := -INF
	for control_variant in [resource_box, music_box, sim_box]:
		var control := control_variant as Control
		if control == null or not control.visible:
			continue
		var control_rect: Rect2 = control.get_global_rect()
		if control_rect.size.x <= 1.0:
			continue
		left_edge = minf(left_edge, control_rect.position.x - chrome_rect.position.x)
		right_edge = maxf(right_edge, control_rect.position.x + control_rect.size.x - chrome_rect.position.x)

	if left_edge == INF:
		_top_chrome.set_cluster_bounds(-1.0, -1.0)
		return

	_top_chrome.set_cluster_bounds(left_edge - 42.0, right_edge + 18.0)


func _get_display_resource_ids() -> Array[String]:
	var registry_ids := EconomyManager.get_resource_ids()
	var stockpile := EconomyManager.get_stockpile_map(_active_empire_id) if not _active_empire_id.is_empty() else {}
	var monthly_net := EconomyManager.get_projected_monthly_net_map(_active_empire_id) if not _active_empire_id.is_empty() else {}
	var result: Array[String] = []

	for resource_id in RESOURCE_DISPLAY_ORDER:
		if _resource_is_known(resource_id, registry_ids) and _should_show_resource(resource_id, stockpile, monthly_net):
			result.append(resource_id)

	for resource_id in registry_ids:
		if result.has(resource_id):
			continue
		if _should_show_resource(resource_id, stockpile, monthly_net):
			result.append(resource_id)

	if result.is_empty():
		for fallback_resource_id in ["matter", "energy", "food", "alloys"]:
			result.append(fallback_resource_id)
	return result


func _resource_is_known(resource_id: String, registry_ids: PackedStringArray) -> bool:
	return registry_ids.is_empty() or registry_ids.has(resource_id)


func _should_show_resource(resource_id: String, stockpile: Dictionary, monthly_net: Dictionary) -> bool:
	if ALWAYS_VISIBLE_RESOURCE_IDS.has(resource_id):
		return true
	return absi(int(stockpile.get(resource_id, 0))) > 0 or absi(int(monthly_net.get(resource_id, 0))) > 0


func _resource_chip_set_matches(resource_ids: Array[String]) -> bool:
	if _resource_chip_nodes.size() != resource_ids.size():
		return false
	var desired_lookup := {}
	for resource_id in resource_ids:
		desired_lookup[resource_id] = true
	for resource_id_variant in _resource_chip_nodes.keys():
		if not desired_lookup.has(str(resource_id_variant)):
			return false
	return true


func _get_resource_display_name(resource_id: String) -> String:
	return str(RESOURCE_DISPLAY_NAMES.get(resource_id, resource_id.replace("_", " ").capitalize()))


func _get_resource_short_name(resource_id: String) -> String:
	return str(RESOURCE_SHORT_NAMES.get(resource_id, _get_resource_display_name(resource_id)))


func _get_resource_accent(resource_id: String) -> Color:
	match resource_id:
		"matter":
			return Color(0.55, 0.68, 0.74, 1.0)
		"energy":
			return Color(0.62, 0.88, 1.0, 1.0)
		"food":
			return Color(0.58, 0.82, 0.55, 1.0)
		"alloys":
			return Color(0.86, 0.68, 0.52, 1.0)
		"exotic_gases":
			return Color(0.74, 0.54, 0.9, 1.0)
		"living_metal":
			return Color(0.55, 0.86, 0.78, 1.0)
		"dark_matter":
			return Color(0.62, 0.58, 0.98, 1.0)
		_:
			return Color(0.75, 0.82, 0.88, 1.0)


func _format_resource_amount(milliunits: int) -> String:
	return _format_milliunits(milliunits, false)


func _format_resource_delta(milliunits: int) -> String:
	if milliunits == 0:
		return "0/mo"
	var prefix := "+" if milliunits > 0 else "-"
	return "%s%s/mo" % [prefix, _format_milliunits(absi(milliunits), true)]


func _format_milliunits(milliunits: int, allow_decimal_units: bool) -> String:
	var sign := "-" if milliunits < 0 else ""
	var units := float(absi(milliunits)) / 1000.0
	if units >= 1000000.0:
		return "%s%sM" % [sign, _trim_decimal(units / 1000000.0)]
	if units >= 1000.0:
		return "%s%sK" % [sign, _trim_decimal(units / 1000.0)]
	if units >= 100.0:
		return "%s%d" % [sign, int(round(units))]
	if units >= 10.0:
		return "%s%s" % [sign, _trim_decimal(units)]
	if units > 0.0:
		var small_value_text := _trim_decimal(units) if allow_decimal_units else str(int(ceil(units)))
		return "%s%s" % [sign, small_value_text]
	return "0"


func _trim_decimal(value: float) -> String:
	var text := "%.1f" % value
	if text.ends_with(".0"):
		return text.substr(0, text.length() - 2)
	return text


func _get_delta_color(milliunits: int, has_active_empire: bool) -> Color:
	if not has_active_empire:
		return Color(0.64, 0.7, 0.74, 0.52)
	if milliunits > 0:
		return Color(0.62, 0.9, 0.68, 0.95)
	if milliunits < 0:
		return Color(1.0, 0.58, 0.54, 0.95)
	return Color(0.75, 0.81, 0.86, 0.72)


func _get_resource_icon_texture(resource_id: String) -> Texture2D:
	if _resource_icon_textures.has(resource_id):
		return _resource_icon_textures[resource_id] as Texture2D

	var size_px := 20
	var center := Vector2(float(size_px) * 0.5, float(size_px) * 0.5)
	var radius := 6.8
	var accent := _get_resource_accent(resource_id)
	var image := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for y in range(size_px):
		for x in range(size_px):
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var distance := point.distance_to(center)
			if distance > radius + 2.0:
				continue
			var edge_alpha := clampf(radius + 2.0 - distance, 0.0, 1.0)
			if distance > radius:
				image.set_pixel(x, y, Color(accent.r, accent.g, accent.b, 0.22 * edge_alpha))
				continue

			var light := clampf(1.0 - point.distance_to(Vector2(7.0, 6.0)) / 16.0, 0.0, 1.0)
			var color := accent.darkened(0.22).lerp(accent.lightened(0.28), light)
			color.a = 0.94
			if resource_id == "energy" and absf(point.x - center.x) < 1.2:
				color = color.lightened(0.28)
			elif resource_id == "alloys" and point.y > center.y + 1.0:
				color = color.darkened(0.22)
			elif resource_id == "dark_matter" and distance < 2.4:
				color = Color(0.08, 0.07, 0.14, 0.95)
			image.set_pixel(x, y, color)

	var texture := ImageTexture.create_from_image(image)
	_resource_icon_textures[resource_id] = texture
	return texture


func _get_slider_grabber_icon(color: Color = Color(0.66, 0.9, 1.0, 1.0)) -> Texture2D:
	var icon_id := "slider_%s" % color.to_html()
	if _resource_icon_textures.has(icon_id):
		return _resource_icon_textures[icon_id] as Texture2D

	var size_px := 14
	var center := Vector2(float(size_px) * 0.5, float(size_px) * 0.5)
	var image := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(size_px):
		for x in range(size_px):
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var distance := point.distance_to(center)
			if distance > 5.0:
				continue
			var alpha := clampf(5.4 - distance, 0.0, 1.0)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
	var texture := ImageTexture.create_from_image(image)
	_resource_icon_textures[icon_id] = texture
	return texture


func _build_hud_segment_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_right = 8
	style.content_margin_bottom = 4
	return style


func _build_resource_chip_style(accent: Color, active: bool, warning: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var fill_alpha := 0.56 if active else 0.34
	var border_alpha := 0.34 if active else 0.16
	style.bg_color = Color(0.035, 0.048, 0.06, fill_alpha)
	style.border_color = Color(accent.r, accent.g, accent.b, border_alpha)
	if warning:
		style.border_color = Color(1.0, 0.46, 0.42, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 2
	style.content_margin_top = 2
	style.content_margin_right = 2
	style.content_margin_bottom = 2
	return style


func _build_button_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 9
	style.content_margin_top = 4
	style.content_margin_right = 9
	style.content_margin_bottom = 4
	return style


func _build_focus_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = accent
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	return style


func _build_slider_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(999)
	style.content_margin_left = 4
	style.content_margin_top = 3
	style.content_margin_right = 4
	style.content_margin_bottom = 3
	return style


func _style_hud_button(button: Button, min_width: int) -> void:
	button.custom_minimum_size = Vector2(float(min_width), 26.0)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color(0.91, 0.96, 0.98, 0.96))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.94, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.86, 0.96, 1.0, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.72, 0.78, 0.82, 0.45))
	button.add_theme_stylebox_override("normal", _build_button_style(Color(0.05, 0.07, 0.09, 0.62), Color(0.28, 0.48, 0.58, 0.35)))
	button.add_theme_stylebox_override("hover", _build_button_style(Color(0.09, 0.12, 0.14, 0.78), Color(0.58, 0.82, 0.95, 0.55)))
	button.add_theme_stylebox_override("pressed", _build_button_style(Color(0.035, 0.05, 0.065, 0.9), Color(0.7, 0.92, 1.0, 0.76)))
	button.add_theme_stylebox_override("focus", _build_focus_style(Color(0.7, 0.9, 1.0, 0.75)))


func _on_economy_registry_loaded(_registry_hash: String, _resource_ids: PackedStringArray) -> void:
	if not is_node_ready():
		return
	_rebuild_resource_chips()
	_refresh_resource_ui()


func _on_economy_bootstrapped(_empire_ids: PackedStringArray) -> void:
	if not is_node_ready():
		return
	_rebuild_resource_chips()
	_refresh_resource_ui()


func _on_empire_stockpile_changed(empire_id: String, _revision: int) -> void:
	if empire_id == _active_empire_id:
		_queue_resource_refresh()


func _on_monthly_settlement_completed(_month_serial: int) -> void:
	_queue_resource_refresh()


func _on_economy_source_changed(_source_id: String) -> void:
	_queue_resource_refresh()


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
