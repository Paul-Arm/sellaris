extends Control
const S = preload("res://scene/UI/atlas/AtlasStyle.gd")
var host: Control
var original_parent: Node
var page_host: MarginContainer
var welcome: Control
var nav: HBoxContainer
var masthead: Label
var page_title: Label
var subtitle: Label
var title: Label
var intro: Label
var launch: Button
var quick: VBoxContainer
var footer: Label
var quit: Button
var active := false
var navigation: Array[Button] = []
var layout_original: Array[Dictionary] = []

func _ready() -> void:
	hide()
	name = "AtlasMenu"
	set_meta("atlas_ui", true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = S.INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	masthead = S.label(self, "SELLARIS", 22)
	var line := ColorRect.new()
	line.color = S.LINE
	line.position = Vector2(32, 78)
	line.anchor_right = 1
	line.offset_right = -32
	line.offset_bottom = 79
	add_child(line)
	nav = HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	add_child(nav)
	for entry in [["Overview", 0], ["Empires", 1], ["Settings", 2], ["Multiplayer", 3]]:
		var page: int = entry[1]
		navigation.append(S.button(nav, entry[0], func(): show_page(page)))
	quit = S.button(self, "Quit", func(): host.quit_button.pressed.emit())
	welcome = Control.new()
	welcome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(welcome)
	subtitle = S.label(welcome, "MISSION CONTROL  /  01", 12, S.ACCENT)
	title = S.label(welcome, "Beyond the\nknown horizon.", 54)
	intro = S.label(welcome, "Choose your people. Chart distant worlds.\nGive a new civilization its place among the stars.", 16, S.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	launch = S.button(welcome, "Begin expedition    >", func(): host.singleplayer_button.pressed.emit(), true)
	quick = VBoxContainer.new()
	quick.add_theme_constant_override("separation", 16)
	welcome.add_child(quick)
	for entry in [["01   CREATE AN EMPIRE", "Identity, species and a place to begin.", 1], ["02   MULTIPLAYER", "Host an expedition or join your friends.", 3], ["03   FLIGHT SETTINGS", "Display, sound and presentation.", 2]]:
		var page: int = entry[2]
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", S.box())
		quick.add_child(panel)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 10)
		panel.add_child(column)
		S.label(column, entry[0], 12, S.ACCENT)
		var description := S.label(column, entry[1], 14, S.MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		S.button(column, "Open   >", func(): show_page(page))
	page_title = S.label(self, "", 32)
	page_host = MarginContainer.new()
	add_child(page_host)
	footer = S.label(self, "SELLARIS   /   STRATEGIC EXPLORATION", 11, S.MUTED)
	resized.connect(_layout)
	_layout()

func activate(enabled: bool) -> void:
	if enabled == active: return
	active = enabled
	visible = enabled
	if enabled:
		original_parent = host.content_tabs.get_parent()
		host.content_tabs.reparent(page_host)
		host.content_tabs.use_hidden_tabs_for_min_size = false
		host.get_node("UiRoot").hide()
		# Cached page controls retain their actions; the new shell owns navigation.
		for page_name in ["PresetsPage", "SettingsPage", "MultiplayerPage"]:
			var page: Control = host.content_tabs.get_node(page_name)
			if page.get_node_or_null("AtlasScroll") == null:
				var content: Control = page.get_child(0)
				var scroll := ScrollContainer.new()
				scroll.name = "AtlasScroll"
				scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
				page.add_child(scroll)
				content.reparent(scroll)
				content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		S.adopt(host.content_tabs)
		show_page(host.content_tabs.current_tab)
	else:
		for saved in layout_original:
			saved["node"].set(saved["property"], saved["value"])
		layout_original.clear()
		S.release(host.content_tabs)
		for page_name in ["PresetsPage", "SettingsPage", "MultiplayerPage"]:
			var page: Control = host.content_tabs.get_node(page_name)
			var scroll: ScrollContainer = page.get_node_or_null("AtlasScroll")
			if scroll != null:
				scroll.get_child(0).reparent(page)
				page.remove_child(scroll)
				scroll.queue_free()
		host.content_tabs.use_hidden_tabs_for_min_size = true
		host.content_tabs.reparent(original_parent)
		host.content_tabs.show()
		host.get_node("UiRoot").show()
		DesignDirector.call_deferred("_refresh_controls", host.content_tabs)

func show_page(page: int) -> void:
	host.call("_show_page", page)

func sync_page(page: int) -> void:
	welcome.visible = page == 0
	page_host.visible = page != 0
	page_title.visible = page != 0
	page_title.text = ["Overview", "Your empires", "Flight settings", "Multiplayer"][page]
	for index in range(navigation.size()):
		navigation[index].add_theme_stylebox_override("normal", S.button_box(Color("34302a") if index == page else Color.TRANSPARENT, S.ACCENT if index == page else Color.TRANSPARENT, 6))
	_layout()

func _layout() -> void:
	if welcome == null: return
	if active: _layout_pages()
	var margin := maxf(32, (size.x - 1320) * 0.5)
	S.rect(masthead, Vector2(margin, 27), Vector2(170, 34))
	S.rect(nav, Vector2(margin + 188, 24), Vector2(size.x - margin * 2 - 278, 42))
	S.rect(quit, Vector2(size.x - margin - 76, 24), Vector2(76, 40))
	S.rect(welcome, Vector2(margin, 106), Vector2(size.x - margin * 2, size.y - 158))
	var column_width := welcome.size.x * 0.53
	S.rect(subtitle, Vector2(0, 24), Vector2(column_width, 24))
	S.rect(title, Vector2(0, 73), Vector2(column_width, 144))
	title.add_theme_font_size_override("font_size", 54 if size.x >= 1150 else 42)
	S.rect(intro, Vector2(0, 230), Vector2(column_width - 32, 68))
	S.rect(launch, Vector2(0, 319), Vector2(248, 48))
	S.rect(quick, Vector2(column_width + 28, 22), Vector2(welcome.size.x - column_width - 28, 400))
	if size.y < 660:
		quick.add_theme_constant_override("separation", 8)
		for panel in quick.get_children():
			panel.get_child(0).get_child(1).visible = false
		S.rect(title, Vector2(0, 62), Vector2(column_width, 120))
		S.rect(intro, Vector2(0, 196), Vector2(column_width - 32, 64))
		S.rect(launch, Vector2(0, 278), Vector2(248, 44))
	else:
		for panel in quick.get_children(): panel.get_child(0).get_child(1).show()
	S.rect(page_title, Vector2(margin, 108), Vector2(size.x - margin * 2, 45))
	S.rect(page_host, Vector2(margin, 172), Vector2(size.x - margin * 2, maxf(220, size.y - 230)))
	S.rect(footer, Vector2(margin, size.y - 32), Vector2(size.x - margin * 2, 20))

func _set_layout(node: Node, property: String, value: Variant) -> void:
	if node == null: return
	var found := false
	for saved in layout_original:
		if saved["node"] == node and saved["property"] == property:
			found = true
			break
	if not found: layout_original.append({"node": node, "property": property, "value": node.get(property)})
	node.set(property, value)

func _layout_pages() -> void:
	var row: Control = host.content_tabs.get_node_or_null("PresetsPage/AtlasScroll/ContentRow")
	if row == null: return
	var browser: Control = row.get_node("PresetBrowser")
	_set_layout(browser, "custom_minimum_size", Vector2(240, 0))
	_set_layout(browser.find_child("BrowserTitle", true, false), "theme_override_font_sizes/font_size", 18)
	_set_layout(browser.find_child("PresetList", true, false), "custom_minimum_size", Vector2(0, 130 if size.y < 660 else 300))
	var editor: Control = row.get_node("PresetEditor")
	var grid: GridContainer = editor.find_child("SettingsGrid", true, false)
	_set_layout(grid, "columns", 2 if size.x < 1500 else 4)
	for index in range(1, grid.get_child_count(), 2):
		_set_layout(grid.get_child(index), "size_flags_horizontal", Control.SIZE_EXPAND_FILL)
	_set_layout(editor.find_child("ScrollContainer", true, false), "horizontal_scroll_mode", ScrollContainer.SCROLL_MODE_DISABLED)
	_set_layout(editor.find_child("ScrollContainer", true, false), "custom_minimum_size", Vector2(0, 160))
	var settings: Control = host.content_tabs.get_node("SettingsPage")
	_set_layout(settings.find_child("SettingsTitle", true, false), "visible", false)
	_set_layout(settings.find_child("SettingsDescription", true, false), "visible", false)
