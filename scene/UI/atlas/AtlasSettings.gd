extends Control
const S = preload("res://scene/UI/atlas/AtlasStyle.gd")
var host: Control
var panel: PanelContainer
var pages: Array[Control] = []
var tabs: Array[Button] = []
var window_mode: OptionButton
var resolution: OptionButton
var aa: OptionButton
var music: HSlider
var opacity: HSlider
var rim: CheckBox
var _syncing := false

func _ready() -> void:
	name = "AtlasSettings"
	set_meta("atlas_ui", true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", S.box())
	add_child(panel)
	panel.minimum_size_changed.connect(_layout.call_deferred)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 20)
	panel.add_child(stack)
	var header := HBoxContainer.new()
	stack.add_child(header)
	var heading := S.label(header, "Flight settings", 24)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	S.button(header, "X", func(): host.close_settings_requested.emit())
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	stack.add_child(nav)
	for index in range(3):
		var page_index := index
		var button := S.button(nav, ["Display", "Audio", "Map"][index], func(): _select_page(page_index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.append(button)
	var content := MarginContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(content)
	for index in range(3):
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		content.add_child(scroll)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 12)
		scroll.add_child(column)
		pages.append(scroll)
	var display: Control = pages[0].get_child(0)
	S.label(display, "PRESENTATION", 11, S.ACCENT)
	display.add_child(preload("res://scene/UI/theme/DesignSwitcher.gd").new())
	S.label(display, "Window mode", 13, S.MUTED)
	window_mode = _option(display, ["Windowed", "Maximized", "Fullscreen", "Exclusive fullscreen"])
	window_mode.item_selected.connect(func(index):
		if not _syncing:
			SettingsManager.set_window_mode([DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN][index])
			_refresh.call_deferred()
	)
	S.label(display, "Window resolution", 13, S.MUTED)
	resolution = _option(display, [])
	resolution.item_selected.connect(func(index):
		if not _syncing: SettingsManager.set_resolution(resolution.get_item_metadata(index))
	)
	S.label(display, "Anti-aliasing", 13, S.MUTED)
	aa = _option(display, ["Off", "2x MSAA", "4x MSAA", "8x MSAA"])
	aa.item_selected.connect(func(index):
		if not _syncing: SettingsManager.set_msaa(index)
	)
	var audio_page: Control = pages[1].get_child(0)
	S.label(audio_page, "MUSIC", 11, S.ACCENT)
	S.label(audio_page, "Volume", 13, S.MUTED)
	music = HSlider.new()
	music.max_value = 1.0
	music.step = 0.01
	music.custom_minimum_size.y = 32
	audio_page.add_child(music)
	music.value_changed.connect(func(value):
		if not _syncing: host.music_volume_changed.emit(value)
	)
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 8)
	audio_page.add_child(transport)
	S.button(transport, "Previous", func(): host.previous_track_requested.emit())
	S.button(transport, "Play / pause", func(): host.pause_track_requested.emit())
	S.button(transport, "Next", func(): host.next_track_requested.emit())
	var map_page: Control = pages[2].get_child(0)
	S.label(map_page, "GALAXY MAP", 11, S.ACCENT)
	rim = CheckBox.new()
	rim.text = "Bright territory borders"
	map_page.add_child(rim)
	rim.toggled.connect(func(value):
		if not _syncing: host.territory_bright_rim_toggled.emit(value)
	)
	S.label(map_page, "Territory opacity", 13, S.MUTED)
	opacity = HSlider.new()
	opacity.max_value = 0.35
	opacity.step = 0.01
	opacity.custom_minimum_size.y = 32
	map_page.add_child(opacity)
	opacity.value_changed.connect(func(value):
		if not _syncing: host.territory_core_opacity_changed.emit(value)
	)
	S.button(stack, "Return to mission", func(): host.close_settings_requested.emit(), true)
	SettingsManager.design_changed.connect(func(_variant): _apply_design())
	host.settings_overlay.visibility_changed.connect(_refresh)
	get_viewport().size_changed.connect(_refresh)
	resized.connect(_layout)
	_select_page(0)
	_apply_design()
	_refresh()

func _option(parent: Control, values: Array) -> OptionButton:
	var control := OptionButton.new()
	control.custom_minimum_size.y = 36
	control.add_theme_stylebox_override("normal", S.button_box())
	for value in values: control.add_item(value)
	parent.add_child(control)
	return control

func _select_page(index: int) -> void:
	for page_index in range(pages.size()):
		pages[page_index].visible = page_index == index
		tabs[page_index].add_theme_stylebox_override("normal", S.button_box(Color("34302a") if page_index == index else S.PANEL, S.ACCENT if page_index == index else S.LINE))

func _apply_design() -> void:
	visible = DesignDirector.is_clean()
	host.settings_overlay.get_node("Panel").visible = not visible
	_layout()

func _refresh() -> void:
	if window_mode == null: return
	_syncing = true
	var mode := SettingsManager.get_window_mode()
	var modes := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	window_mode.select(maxi(0, modes.find(mode)))
	resolution.clear()
	var actual := SettingsManager.get_resolution()
	var sizes: Array = preload("res://scene/MainMenue/systems/MainMenuSettingsSystem.gd").RESOLUTION_OPTIONS.duplicate()
	if not sizes.has(actual): sizes.append(actual)
	for value: Vector2i in sizes:
		resolution.add_item("%d × %d" % [value.x, value.y])
		resolution.set_item_metadata(resolution.item_count - 1, value)
	resolution.select(sizes.find(actual))
	resolution.disabled = mode != DisplayServer.WINDOW_MODE_WINDOWED
	resolution.tooltip_text = "Fullscreen and maximized modes use the display size automatically."
	aa.select(SettingsManager.get_msaa())
	music.value = host.settings_music_volume_slider.value
	rim.button_pressed = host.territory_bright_rim_check_box.button_pressed
	opacity.value = host.territory_core_opacity_slider.value
	_syncing = false
	_layout()

func _layout() -> void:
	if panel == null: return
	S.rect(panel, Vector2(size.x - 424, 20), Vector2(400, maxf(320, size.y - 40)))
