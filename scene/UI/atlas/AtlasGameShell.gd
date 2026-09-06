extends Control
const S = preload("res://scene/UI/atlas/AtlasStyle.gd")
var host: Control
var top_band: PanelContainer
var top_row: HBoxContainer
var resource_scroll: ScrollContainer
var time_status: Label
var rail: PanelContainer
var navigation: VBoxContainer
var resource_strip: HBoxContainer
var resource_labels: Dictionary = {}
var clock_panel: HBoxContainer
var date: Label
var pause_button: Button
var speed_button: Button
var operations: PanelContainer
var operation_title: Label
var content: MarginContainer
var bottom: Control
var drawer: Control
var empire_parent: Node
var empire_content: Control
var empire_stack: VBoxContainer
var empire_picker: OptionButton
var list_scroll: ScrollContainer
var operation_rows: VBoxContainer
var list_search: LineEdit
var nav_buttons: Dictionary = {}
var _category_index := 0
var _list_signature := ""
var _active := false
var _operation := ""
var _tick := 0.0

func _ready() -> void:
	hide()
	name = "AtlasGameShell"
	set_meta("atlas_ui", true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom = host.get_parent().get_node_or_null("BottomCategoryBar")
	drawer = host.get_parent().get_node_or_null("EmpireCommandDrawer")
	top_band = PanelContainer.new()
	top_band.mouse_filter = Control.MOUSE_FILTER_STOP
	var top_style := S.box(S.INK, S.LINE, 8)
	top_style.content_margin_left = 12
	top_style.content_margin_right = 12
	top_style.content_margin_top = 7
	top_style.content_margin_bottom = 7
	top_band.add_theme_stylebox_override("panel", top_style)
	add_child(top_band)
	rail = PanelContainer.new()
	var rail_style := S.box(S.INK, S.LINE, 0)
	rail_style.content_margin_left = 8
	rail_style.content_margin_right = 8
	rail.add_theme_stylebox_override("panel", rail_style)
	add_child(rail)
	navigation = VBoxContainer.new()
	navigation.add_theme_constant_override("separation", 8)
	rail.add_child(navigation)
	var brand := S.label(navigation, "S /", 24, S.ACCENT)
	brand.custom_minimum_size.y = 54
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for entry in [["Map", -1], ["Worlds", 0], ["Bases", 1], ["Support", 2], ["Fleets", 3]]:
		var category: int = entry[1]
		var button := S.button(navigation, entry[0], func(): _navigate(category))
		button.add_theme_font_size_override("font_size", 11)
		button.custom_minimum_size.y = 42
		nav_buttons[category] = button
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	navigation.add_child(spacer)
	for entry in [["Research", "research"], ["Shipyard", "ship_design"], ["Empire", "government"]]:
		var category: String = entry[1]
		var button := S.button(navigation, entry[0], func(): _empire(category))
		button.add_theme_font_size_override("font_size", 11)
	var settings := S.button(navigation, "Settings", _open_settings)
	settings.add_theme_font_size_override("font_size", 11)
	top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 18)
	top_band.add_child(top_row)
	resource_scroll = ScrollContainer.new()
	resource_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	top_row.add_child(resource_scroll)
	resource_strip = HBoxContainer.new()
	resource_strip.add_theme_constant_override("separation", 8)
	resource_scroll.add_child(resource_strip)
	var separator := VSeparator.new()
	top_row.add_child(separator)
	clock_panel = HBoxContainer.new()
	clock_panel.add_theme_constant_override("separation", 8)
	clock_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(clock_panel)
	var clock_text := VBoxContainer.new()
	clock_text.custom_minimum_size.x = 82
	clock_text.add_theme_constant_override("separation", 2)
	clock_panel.add_child(clock_text)
	date = S.label(clock_text, "", 12)
	time_status = S.label(clock_text, "PAUSED", 9, S.ACCENT)
	pause_button = S.button(clock_panel, "Play", func(): host.sim_pause_requested.emit(), true)
	pause_button.add_theme_font_size_override("font_size", 12)
	speed_button = S.button(clock_panel, "Speed >", func(): host.sim_speed_requested.emit())
	speed_button.add_theme_font_size_override("font_size", 12)
	speed_button.tooltip_text = "Cycle simulation speed"
	operations = PanelContainer.new()
	operations.add_theme_stylebox_override("panel", S.box())
	add_child(operations)
	operations.hide()
	operations.minimum_size_changed.connect(_layout.call_deferred)
	operations.visibility_changed.connect(_highlight_navigation)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	operations.add_child(stack)
	var header := HBoxContainer.new()
	stack.add_child(header)
	operation_title = S.label(header, "Operations", 22)
	operation_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	S.button(header, "X", func(): operations.hide())
	content = MarginContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(content)
	var list_stack := VBoxContainer.new()
	list_stack.name = "ObjectList"
	list_stack.add_theme_constant_override("separation", 14)
	content.add_child(list_stack)
	list_search = LineEdit.new()
	list_search.placeholder_text = "Find by name or system..."
	list_search.custom_minimum_size.y = 38
	list_search.text_changed.connect(func(_text): _rebuild_entries())
	list_stack.add_child(list_search)
	list_scroll = ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_stack.add_child(list_scroll)
	operation_rows = VBoxContainer.new()
	operation_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	operation_rows.add_theme_constant_override("separation", 12)
	list_scroll.add_child(operation_rows)
	empire_stack = VBoxContainer.new()
	empire_stack.add_theme_constant_override("separation", 16)
	content.add_child(empire_stack)
	empire_stack.hide()
	empire_picker = OptionButton.new()
	empire_picker.custom_minimum_size.y = 38
	for entry in drawer.DEFAULT_CATEGORIES:
		empire_picker.add_item(entry["title"])
		empire_picker.set_item_metadata(empire_picker.item_count - 1, entry["id"])
	empire_picker.item_selected.connect(func(index): drawer.set_active_category(empire_picker.get_item_metadata(index)))
	empire_stack.add_child(empire_picker)
	if bottom != null:
		bottom.category_selected.connect(func(_category, index):
			if _active: _show_category(index)
		)
	resized.connect(_layout)
	_layout()

func activate(enabled: bool) -> void:
	if _active == enabled: return
	_active = enabled
	visible = enabled
	if bottom == null or drawer == null: return
	if enabled:
		empire_content = drawer.get("_content_root")
		empire_parent = empire_content.get_parent()
		empire_content.reparent(empire_stack)
		bottom.hide()
		drawer.hide()
		S.adopt(empire_content)
	else:
		S.release(empire_content)
		empire_content.reparent(empire_parent)
		DesignDirector.call_deferred("_refresh_controls", empire_content)
		bottom.show()
		drawer.show()
		bottom.call("_set_expanded", false, false)
		drawer.call("_set_expanded", false, false)
		operations.hide()

func _open_settings() -> void:
	var controller: Node = host.get_parent().get_parent().get("_scene_ui_controller")
	controller.set_settings_overlay_visible(true)

func _navigate(category: int) -> void:
	if category < 0:
		var router := host.get_parent().get_parent().get_node_or_null("SceneSystems/ViewRouter")
		if router != null: router.system_close_requested.emit()
		operations.hide()
		return
	if bottom == null: return
	bottom.call("_select_category", category, true)


func _show_category(category: int) -> void:
	_operation = "category"
	_category_index = category
	content.get_node("ObjectList").show()
	empire_stack.hide()
	operation_title.text = ["Worlds", "Starbases", "Support ships", "Military fleets"][category]
	list_search.text = ""
	_list_signature = ""
	_rebuild_entries()
	operations.show()
	_highlight_navigation()
	_layout()

func _rebuild_entries() -> void:
	for child in operation_rows.get_children():
		operation_rows.remove_child(child)
		child.queue_free()
	var category_id: String = ["planets", "starbases", "passive_fleets", "military_fleets"][_category_index]
	var entries: Array = bottom.get("_runtime_entries_by_category").get(category_id, [])
	for entry: Dictionary in entries:
		var title := str(entry.get("title", "Unnamed"))
		var location := str(entry.get("location", ""))
		if not list_search.text.is_empty() and not (title + " " + location).to_lower().contains(list_search.text.to_lower()): continue
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", S.box(Color("172334"), S.LINE, 6))
		operation_rows.add_child(card)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 9)
		card.add_child(column)
		var name_label := S.label(column, title, 17)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var description := location
		if not str(entry.get("summary", "")).is_empty(): description += "   /   " + str(entry["summary"])
		if not description.is_empty():
			var detail := S.label(column, description, 12, S.MUTED)
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var action: String = ["Manage colony", "Open station", "Locate ship", "Locate fleet"][_category_index]
		var record := entry.duplicate(true)
		S.button(column, action + "   >", func():
			operations.hide()
			bottom.runtime_action_requested.emit(category_id, record)
		)
		card.tooltip_text = str(entry.get("tooltip", ""))
	if operation_rows.get_child_count() == 0:
		var empty := S.label(operation_rows, "No matching objects" if not list_search.text.is_empty() else "No objects in this category yet.", 14, S.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _empire(category: String) -> void:
	if drawer == null: return
	if category == "research":
		drawer.research_open_requested.emit()
		return
	if category == "ship_design":
		drawer.ship_designer_open_requested.emit()
		return
	_operation = "empire"
	drawer.set_active_category(category)
	drawer.call("_set_expanded", true, false)
	content.get_node("ObjectList").hide()
	empire_stack.show()
	for index in range(empire_picker.item_count):
		if empire_picker.get_item_metadata(index) == category: empire_picker.select(index)
	operation_title.text = "Empire command"
	operations.show()
	_layout()

func _process(delta: float) -> void:
	if not _active: return
	# Old controllers may refresh their chrome on state changes; ownership of
	# clean presentation stays with this shell.
	host.top_panel.hide()
	if bottom != null: bottom.hide()
	if drawer != null: drawer.hide()
	_tick += delta
	if _tick < 0.25: return
	_tick = 0
	date.text = host.sim_date_label.text.substr(0, 10)
	pause_button.text = host.sim_pause_button.text
	time_status.text = "PAUSED" if pause_button.text == "Play" else "RUNNING"
	var speed_text: String = host.sim_date_label.text.substr(10).strip_edges()
	speed_button.text = "Speed >" if pause_button.text == "Play" else speed_text + " >"
	var chips: Dictionary = host.get("_resource_chip_nodes")
	if str(resource_labels.keys()) != str(chips.keys()):
		for child in resource_strip.get_children():
			resource_strip.remove_child(child)
			child.queue_free()
		resource_labels.clear()
		for key in chips:
			var card := PanelContainer.new()
			var card_style := S.box(Color("141e2a"), Color.TRANSPARENT, 4)
			card_style.content_margin_left = 8
			card_style.content_margin_right = 8
			card_style.content_margin_top = 3
			card_style.content_margin_bottom = 3
			card.add_theme_stylebox_override("panel", card_style)
			resource_strip.add_child(card)
			var column := VBoxContainer.new()
			column.add_theme_constant_override("separation", 1)
			card.add_child(column)
			var name_label := S.label(column, host.call("_get_resource_short_name", key).to_upper(), 9, S.MUTED)
			var values := HBoxContainer.new()
			values.add_theme_constant_override("separation", 8)
			column.add_child(values)
			var amount_label := S.label(values, "", 15)
			amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var net_label := S.label(values, "", 10, S.MUTED)
			resource_labels[key] = {"column": card, "name": name_label, "amount": amount_label, "net": net_label}
	for key in chips:
		var nodes: Dictionary = chips[key]
		resource_labels[key]["amount"].text = nodes["amount_label"].text
		resource_labels[key]["column"].tooltip_text = nodes["chip"].tooltip_text
		resource_labels[key]["net"].text = nodes["net_label"].text
		resource_labels[key]["net"].add_theme_color_override("font_color", nodes["net_label"].get_theme_color("font_color"))
	_layout_resources()
	if operations.visible and _operation == "category":
		var signature: String = str(bottom.get("_runtime_entries_by_category"))
		if signature != _list_signature:
			_list_signature = signature
			_rebuild_entries()

func _layout_resources() -> void:
	var budget := clampf((size.x - 400) / maxf(resource_labels.size(), 1) - 8, 62, 132)
	for key in resource_labels:
		var data: Dictionary = resource_labels[key]
		data["column"].custom_minimum_size.x = budget
		data["net"].visible = budget >= 110
		data["name"].text = str(host.call("_get_resource_short_name", key)).substr(0, 3).to_upper() if budget < 80 else str(host.call("_get_resource_short_name", key)).to_upper()

func _layout() -> void:
	if rail == null: return
	S.rect(top_band, Vector2(112, 12), Vector2(size.x - 128, 56))
	S.rect(rail, Vector2.ZERO, Vector2(96, size.y))
	navigation.add_theme_constant_override("separation", 4 if size.y < 650 else 8)
	var width := minf(400, size.x - 144)
	S.rect(operations, Vector2(size.x - width - 24, 92), Vector2(width, maxf(260, size.y - 148)))
	_layout_resources()

func _highlight_navigation() -> void:
	for index in nav_buttons:
		var active: bool = index == _category_index if operations.visible and _operation == "category" else index == -1 and not operations.visible
		nav_buttons[index].add_theme_stylebox_override("normal", S.button_box(Color("34302a") if active else Color("172334"), S.ACCENT if active else S.LINE))
