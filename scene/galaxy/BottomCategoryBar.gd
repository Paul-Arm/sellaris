extends Control
class_name BottomCategoryBar

signal category_selected(category: Dictionary, index: int)
signal runtime_entry_activated(category_id: String, entry: Dictionary)
signal runtime_action_requested(category_id: String, entry: Dictionary)

const CHROME_SCRIPT := preload("res://scene/galaxy/BottomCategoryChrome.gd")
const MAX_CATEGORY_COUNT := 9
const FALLBACK_CONTEXT_EMPIRE := "None selected"
const FALLBACK_CONTEXT_SYSTEM := "No system selected"
const FALLBACK_CONTEXT_OWNER := "Unclaimed"
const PALETTE_DUSK_BLUE := Color("355070")
const PALETTE_DUSTY_LAVENDER := Color("6D597A")
const PALETTE_ROSEWOOD := Color("B56576")
const PALETTE_LIGHT_CORAL := Color("E56B6F")
const PALETTE_LIGHT_BRONZE := Color("EAAC8B")
const LIST_ROW_ICON_SIZE := Vector2i(22, 22)
const DEFAULT_ACCENTS := [
	PALETTE_DUSTY_LAVENDER,
	PALETTE_ROSEWOOD,
	PALETTE_LIGHT_CORAL,
	PALETTE_LIGHT_BRONZE,
	PALETTE_DUSTY_LAVENDER,
	PALETTE_ROSEWOOD,
	PALETTE_LIGHT_CORAL,
	PALETTE_LIGHT_BRONZE,
	PALETTE_DUSTY_LAVENDER,
]

@export var tab_hotkeys: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4]
@export_range(0.35, 0.95, 0.01) var width_ratio: float = 0.82
@export_range(460.0, 1400.0, 10.0) var min_bar_width: float = 640.0
@export_range(600.0, 1800.0, 10.0) var max_bar_width: float = 1260.0
@export_range(44.0, 100.0, 1.0) var collapsed_height: float = 54.0
@export_range(120.0, 280.0, 1.0) var expanded_height: float = 132.0
@export_range(0.05, 0.4, 0.01) var expand_duration: float = 0.16

@onready var dock_panel: PanelContainer = $BottomAnchor/BottomAlign/CenterRow/DockPanel
@onready
var dock_margin: MarginContainer = $BottomAnchor/BottomAlign/CenterRow/DockPanel/DockMargin
@onready
var overlay_root: Control = $BottomAnchor/BottomAlign/CenterRow/DockPanel/DockMargin/OverlayRoot
@onready
var tab_view: TabContainer = $BottomAnchor/BottomAlign/CenterRow/DockPanel/DockMargin/OverlayRoot/TabView
@onready
var bubble_layer: Control = $BottomAnchor/BottomAlign/CenterRow/DockPanel/DockMargin/OverlayRoot/BubbleLayer

var _tab_bar: TabBar
var _chrome_layer: BottomCategoryChrome = null
var _categories: Array[Dictionary] = []
var _bubble_nodes: Array[Control] = []
var _selected_category_index: int = -1
var _interaction_enabled: bool = true
var _expanded: bool = false
var _suppress_tab_signal: bool = false
var _last_tab_changed_frame: int = -1
var _panel_tween: Tween
var _content_tween: Tween
var _active_empire_name: String = FALLBACK_CONTEXT_EMPIRE
var _selected_system_name: String = FALLBACK_CONTEXT_SYSTEM
var _selected_system_owner_name: String = FALLBACK_CONTEXT_OWNER
var _runtime_entries_by_category: Dictionary = {
	"planets": [],
	"starbases": [],
	"passive_fleets": [],
	"military_fleets": [],
}
var _runtime_icon_textures: Dictionary = {}


func _ready() -> void:
	_tab_bar = tab_view.get_tab_bar()
	_install_chrome_layer()
	_configure_tab_view()
	_collect_categories_from_pages()
	_build_bubbles()
	_apply_theme()
	_refresh_tab_titles()
	_refresh_page_contexts()
	_refresh_runtime_lists()
	if not _categories.is_empty():
		_select_category(clampi(tab_view.current_tab, 0, _categories.size() - 1), false)
	_set_expanded(false, false)
	_refresh_responsive_layout()
	tab_view.tab_changed.connect(_on_tab_view_tab_changed)
	if _tab_bar != null and not _tab_bar.tab_clicked.is_connected(_on_tab_bar_tab_clicked):
		_tab_bar.tab_clicked.connect(_on_tab_bar_tab_clicked)
	call_deferred("_refresh_bubble_positions")
	call_deferred("_refresh_chrome_state")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_refresh_responsive_layout()
		if _chrome_layer != null:
			_chrome_layer.queue_redraw()
		call_deferred("_refresh_bubble_positions")


func set_category_hotkey(index: int, hotkey: Key) -> void:
	if index < 0 or index >= MAX_CATEGORY_COUNT:
		return

	while tab_hotkeys.size() <= index:
		tab_hotkeys.append(KEY_NONE)

	tab_hotkeys[index] = hotkey
	var current_index: int = _selected_category_index
	_collect_categories_from_pages()
	_build_bubbles()
	_refresh_tab_titles()
	_refresh_page_contexts()
	_refresh_runtime_lists()
	if not _categories.is_empty():
		_select_category(clampi(current_index, 0, _categories.size() - 1), false)
	call_deferred("_refresh_bubble_positions")
	call_deferred("_refresh_chrome_state")


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	dock_panel.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	for tab_index in range(tab_view.get_tab_count()):
		tab_view.set_tab_disabled(tab_index, not enabled)
	if not enabled:
		_set_expanded(false, false)
	dock_panel.modulate = Color(1.0, 1.0, 1.0, 1.0 if enabled else 0.68)


func set_context(
	active_empire_name: String, selected_system_name: String, selected_system_owner_name: String
) -> void:
	_active_empire_name = (
		active_empire_name if not active_empire_name.is_empty() else FALLBACK_CONTEXT_EMPIRE
	)
	_selected_system_name = (
		selected_system_name if not selected_system_name.is_empty() else FALLBACK_CONTEXT_SYSTEM
	)
	_selected_system_owner_name = (
		selected_system_owner_name
		if not selected_system_owner_name.is_empty()
		else FALLBACK_CONTEXT_OWNER
	)
	_refresh_page_contexts()


func set_runtime_entries(
	starbases: Variant,
	passive_fleets: Variant,
	military_fleets: Variant,
	planets: Variant = null
) -> void:
	_runtime_entries_by_category["starbases"] = _normalize_runtime_entries(starbases)
	_runtime_entries_by_category["passive_fleets"] = _normalize_runtime_entries(passive_fleets)
	_runtime_entries_by_category["military_fleets"] = _normalize_runtime_entries(military_fleets)
	if planets != null:
		_runtime_entries_by_category["planets"] = _normalize_runtime_entries(planets)
	_refresh_page_contexts()
	_refresh_runtime_lists()


func consume_hotkey_event(event: InputEvent) -> bool:
	if not _interaction_enabled:
		return false
	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false

	for index in range(_categories.size()):
		var hotkey: Key = int(_categories[index].get("hotkey", KEY_NONE))
		if hotkey == KEY_NONE:
			continue
		if key_event.keycode == hotkey or key_event.physical_keycode == hotkey:
			if index == _selected_category_index and _expanded:
				_set_expanded(false)
			else:
				_select_category(index)
				_set_expanded(true)
			return true

	return false


func get_selected_category() -> Dictionary:
	if _selected_category_index < 0 or _selected_category_index >= _categories.size():
		return {}
	return _categories[_selected_category_index]


func _install_chrome_layer() -> void:
	dock_margin.add_theme_constant_override("margin_left", 18)
	dock_margin.add_theme_constant_override("margin_top", 10)
	dock_margin.add_theme_constant_override("margin_right", 18)
	dock_margin.add_theme_constant_override("margin_bottom", 12)

	_chrome_layer = CHROME_SCRIPT.new() as BottomCategoryChrome
	_chrome_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chrome_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.add_child(_chrome_layer)
	overlay_root.move_child(_chrome_layer, 0)


func _collect_categories_from_pages() -> void:
	_categories.clear()

	var page_count: int = mini(tab_view.get_tab_count(), MAX_CATEGORY_COUNT)
	var resolved_hotkeys: Array[Key] = _build_resolved_hotkeys(page_count)

	for index in range(page_count):
		var page: Control = tab_view.get_tab_control(index)
		if page == null:
			continue

		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var page_content: Control = page.get_node_or_null("PageContent") as Control
		var page_margin: MarginContainer = (
			page.get_node_or_null("PageContent/PageMargin") as MarginContainer
		)
		var page_vbox: VBoxContainer = (
			page.get_node_or_null("PageContent/PageMargin/PageVBox") as VBoxContainer
		)
		var accent_line: ColorRect = (
			page.get_node_or_null("PageContent/PageMargin/PageVBox/AccentLine") as ColorRect
		)
		var context_label: Label = (
			page.get_node_or_null("PageContent/PageMargin/PageVBox/ContextLabel") as Label
		)
		var page_title: Label = (
			page.get_node_or_null("PageContent/PageMargin/PageVBox/PageTitle") as Label
		)
		var page_description: Label = (
			page.get_node_or_null("PageContent/PageMargin/PageVBox/PageDescription") as Label
		)
		var runtime_list_label: Label = (
			page.get_node_or_null("PageContent/PageMargin/PageVBox/RuntimeListLabel") as Label
		)
		var runtime_item_list: ItemList = (
			page.get_node_or_null("PageContent/PageMargin/PageVBox/RuntimeItemList") as ItemList
		)
		if runtime_item_list == null:
			runtime_item_list = page.find_child("RuntimeItemList", true, false) as ItemList
		var runtime_action_button: Button = (
			page.get_node_or_null("PageContent/PageMargin/PageVBox/RuntimeActionButton") as Button
		)
		if runtime_action_button == null:
			runtime_action_button = page.find_child("RuntimeActionButton", true, false) as Button
		if runtime_item_list != null:
			_configure_runtime_item_list(runtime_item_list)
			runtime_item_list.set_meta("category_id", page.name.to_snake_case())
			if not bool(runtime_item_list.get_meta("runtime_signals_bound", false)):
				runtime_item_list.item_activated.connect(_on_runtime_item_activated.bind(runtime_item_list))
				runtime_item_list.item_selected.connect(_on_runtime_item_selected.bind(runtime_item_list))
				runtime_item_list.set_meta("runtime_signals_bound", true)
		if runtime_action_button != null:
			_configure_runtime_action_button(runtime_action_button)
			runtime_action_button.set_meta("category_id", page.name.to_snake_case())
			runtime_action_button.set_meta("runtime_item_list_path", runtime_action_button.get_path_to(runtime_item_list) if runtime_item_list != null else NodePath(""))
			if not bool(runtime_action_button.get_meta("runtime_signals_bound", false)):
				runtime_action_button.pressed.connect(_on_runtime_action_button_pressed.bind(runtime_action_button))
				runtime_action_button.set_meta("runtime_signals_bound", true)
		var accent: Color = DEFAULT_ACCENTS[index % DEFAULT_ACCENTS.size()]
		if accent_line != null:
			accent = accent_line.color
			accent_line.visible = false
		if page_title != null:
			page_title.visible = false
		if page_description != null:
			page_description.visible = false
		if runtime_list_label != null:
			runtime_list_label.visible = false
		if context_label != null:
			context_label.clip_text = true
		if page_margin != null:
			page_margin.add_theme_constant_override("margin_left", 76)
			page_margin.add_theme_constant_override("margin_top", 12)
			page_margin.add_theme_constant_override("margin_right", 76)
			page_margin.add_theme_constant_override("margin_bottom", 14)
		if page_vbox != null:
			page_vbox.add_theme_constant_override("separation", 5)
			page_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			page_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_configure_page_command_row(page_vbox, context_label, runtime_item_list, runtime_action_button)

		(
			_categories
			. append(
				{
					"id": page.name.to_snake_case(),
					"title": page.name,
					"hotkey": resolved_hotkeys[index],
					"accent": accent,
					"page": page,
					"page_content": page_content,
					"context_label": context_label,
					"runtime_item_list": runtime_item_list,
					"runtime_action_button": runtime_action_button,
				}
			)
		)


func _build_resolved_hotkeys(count: int) -> Array[Key]:
	var resolved: Array[Key] = []
	var used_hotkeys: Dictionary = {}

	for index in range(count):
		var requested_hotkey: Key = KEY_NONE
		if index < tab_hotkeys.size():
			requested_hotkey = int(tab_hotkeys[index])
		if requested_hotkey == KEY_NONE or used_hotkeys.has(requested_hotkey):
			requested_hotkey = _find_next_open_hotkey(used_hotkeys)
		used_hotkeys[requested_hotkey] = true
		resolved.append(requested_hotkey)

	return resolved


func _find_next_open_hotkey(used_hotkeys: Dictionary) -> Key:
	for keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]:
		if not used_hotkeys.has(keycode):
			return keycode
	return KEY_NONE


func _configure_tab_view() -> void:
	tab_view.clip_tabs = false
	tab_view.tab_alignment = TabBar.ALIGNMENT_CENTER
	tab_view.tabs_visible = true
	tab_view.tabs_position = TabContainer.POSITION_TOP
	tab_view.use_hidden_tabs_for_min_size = false
	tab_view.all_tabs_in_front = true

	_tab_bar.clip_tabs = false
	_tab_bar.scrolling_enabled = false
	_tab_bar.scroll_to_selected = false
	_tab_bar.max_tab_width = 0


func _configure_page_command_row(
	page_vbox: VBoxContainer,
	context_label: Label,
	runtime_item_list: ItemList,
	runtime_action_button: Button
) -> void:
	if page_vbox == null or runtime_item_list == null:
		return
	if context_label != null:
		context_label.visible = false

	var command_row := page_vbox.get_node_or_null("RuntimeCommandRow") as HBoxContainer
	if command_row == null:
		command_row = HBoxContainer.new()
		command_row.name = "RuntimeCommandRow"
		command_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		command_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		command_row.alignment = BoxContainer.ALIGNMENT_CENTER
		command_row.add_theme_constant_override("separation", 14)
		page_vbox.add_child(command_row)

	if runtime_item_list.get_parent() != command_row:
		var old_list_parent := runtime_item_list.get_parent()
		if old_list_parent != null:
			old_list_parent.remove_child(runtime_item_list)
		command_row.add_child(runtime_item_list)

	if runtime_action_button != null and runtime_action_button.get_parent() != command_row:
		var old_button_parent := runtime_action_button.get_parent()
		if old_button_parent != null:
			old_button_parent.remove_child(runtime_action_button)
		command_row.add_child(runtime_action_button)
	if runtime_action_button != null:
		runtime_action_button.set_meta(
			"runtime_item_list_path",
			runtime_action_button.get_path_to(runtime_item_list)
		)


func _configure_runtime_item_list(runtime_item_list: ItemList) -> void:
	runtime_item_list.custom_minimum_size = Vector2(0, 38)
	runtime_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	runtime_item_list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	runtime_item_list.fixed_icon_size = LIST_ROW_ICON_SIZE
	runtime_item_list.icon_mode = ItemList.ICON_MODE_LEFT
	runtime_item_list.max_text_lines = 1
	runtime_item_list.same_column_width = false
	runtime_item_list.allow_reselect = true
	runtime_item_list.add_theme_font_size_override("font_size", 14)
	runtime_item_list.add_theme_color_override("font_color", Color(0.92, 0.96, 0.98, 0.96))
	runtime_item_list.add_theme_color_override("font_selected_color", Color(0.96, 0.98, 1.0, 1.0))
	runtime_item_list.add_theme_color_override("font_hovered_color", Color(1.0, 0.98, 0.94, 1.0))
	runtime_item_list.add_theme_stylebox_override(
		"panel",
		_build_list_style(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0)
	)
	runtime_item_list.add_theme_stylebox_override(
		"hovered",
		_build_list_style(Color(0.09, 0.13, 0.16, 0.24), Color(0.42, 0.63, 0.72, 0.18), 8)
	)
	runtime_item_list.add_theme_stylebox_override(
		"selected",
		_build_list_style(Color(0.16, 0.24, 0.29, 0.28), Color(0.62, 0.82, 0.94, 0.22), 8)
	)
	runtime_item_list.add_theme_stylebox_override(
		"selected_focus",
		_build_list_style(Color(0.16, 0.24, 0.29, 0.32), Color(0.7, 0.9, 1.0, 0.3), 8)
	)


func _configure_runtime_action_button(runtime_action_button: Button) -> void:
	runtime_action_button.custom_minimum_size = Vector2(132, 28)
	runtime_action_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	runtime_action_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	runtime_action_button.add_theme_font_size_override("font_size", 13)
	runtime_action_button.add_theme_stylebox_override(
		"normal",
		_build_action_button_style(Color(0.08, 0.105, 0.13, 0.96), Color(0.28, 0.46, 0.56, 0.52))
	)
	runtime_action_button.add_theme_stylebox_override(
		"hover",
		_build_action_button_style(Color(0.12, 0.16, 0.19, 1.0), Color(0.55, 0.78, 0.9, 0.75))
	)
	runtime_action_button.add_theme_stylebox_override(
		"pressed",
		_build_action_button_style(Color(0.04, 0.07, 0.09, 1.0), Color(0.7, 0.9, 1.0, 0.9))
	)
	runtime_action_button.add_theme_stylebox_override(
		"disabled",
		_build_action_button_style(Color(0.05, 0.06, 0.07, 0.68), Color(0.16, 0.22, 0.26, 0.42))
	)


func _build_bubbles() -> void:
	bubble_layer.visible = false
	for child in bubble_layer.get_children():
		child.queue_free()
	_bubble_nodes.clear()


func _apply_theme() -> void:
	dock_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	tab_view.add_theme_stylebox_override("panel", _build_page_panel_style())
	tab_view.add_theme_stylebox_override("tabbar_background", _build_tabbar_background_style())
	tab_view.add_theme_color_override("font_unselected_color", Color(0.82, 0.88, 0.92, 0.9))
	tab_view.add_theme_color_override("font_hovered_color", Color(0.96, 0.99, 1.0, 1.0))
	tab_view.add_theme_color_override("font_selected_color", Color(0.96, 0.99, 1.0, 1.0))
	tab_view.add_theme_color_override("font_disabled_color", Color(0.96, 0.93, 0.95, 0.42))
	tab_view.add_theme_font_size_override("font_size", 14)
	_refresh_selected_theme()


func _refresh_tab_titles() -> void:
	for index in range(_categories.size()):
		var category: Dictionary = _categories[index]
		var category_id: String = str(category.get("id", ""))
		var title := str(category.get("title", "Tab"))
		var count: int = _get_runtime_entry_count(category_id)
		if count > 0 and category_id in ["planets", "starbases", "passive_fleets", "military_fleets"]:
			title = "%s (%d)" % [title, count]
		tab_view.set_tab_title(index, title)
		tab_view.set_tab_tooltip(
			index, "%s [%s]" % [title, _format_hotkey(int(category.get("hotkey", KEY_NONE)))]
		)


func _refresh_page_contexts() -> void:
	for category_variant in _categories:
		var category: Dictionary = category_variant
		var context_label: Label = category.get("context_label", null) as Label
		if context_label != null:
			context_label.text = _build_context_text(str(category.get("id", "")))


func _refresh_runtime_lists() -> void:
	for category_variant in _categories:
		var category: Dictionary = category_variant
		var category_id: String = str(category.get("id", ""))
		var runtime_item_list: ItemList = category.get("runtime_item_list", null) as ItemList
		if runtime_item_list == null:
			_set_runtime_action_button_state(category, false)
			continue
		_populate_runtime_item_list(runtime_item_list, category_id, _runtime_entries_by_category.get(category_id, []))
		_refresh_runtime_action_button(category)
	_refresh_tab_titles()


func _get_selected_accent() -> Color:
	if _selected_category_index >= 0 and _selected_category_index < _categories.size():
		return _categories[_selected_category_index].get("accent", PALETTE_LIGHT_CORAL)
	return PALETTE_LIGHT_CORAL


func _refresh_chrome_state() -> void:
	if _chrome_layer == null:
		return
	_chrome_layer.set_state(_get_selected_accent(), _expanded)


func _populate_runtime_item_list(runtime_item_list: ItemList, category_id: String, entries_variant: Variant) -> void:
	runtime_item_list.clear()
	var entries: Array = entries_variant if entries_variant is Array else []
	if entries.is_empty():
		runtime_item_list.add_item(_get_empty_runtime_text(category_id))
		runtime_item_list.set_item_disabled(0, true)
		return

	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		runtime_item_list.add_item(
			_build_runtime_entry_text(category_id, entry),
			_get_runtime_entry_icon(category_id, entry)
		)
		var item_index: int = runtime_item_list.get_item_count() - 1
		runtime_item_list.set_item_metadata(item_index, entry.duplicate(true))
		var tooltip := str(entry.get("tooltip", "")).strip_edges()
		if not tooltip.is_empty():
			runtime_item_list.set_item_tooltip(item_index, tooltip)
		if bool(entry.get("is_local", false)):
			runtime_item_list.set_item_custom_fg_color(item_index, PALETTE_LIGHT_BRONZE)
	if runtime_item_list.get_item_count() > 0:
		runtime_item_list.select(0)


func _build_runtime_entry_text(category_id: String, entry: Dictionary) -> String:
	var title: String = str(entry.get("title", "Unnamed")).strip_edges()
	if title.is_empty():
		title = "Unnamed"
	if category_id == "planets":
		return title

	var summary: String = str(entry.get("summary", "")).strip_edges()
	var location: String = str(entry.get("location", "")).strip_edges()
	var parts: Array[String] = [title]
	if not location.is_empty():
		parts.append(location)
	if not summary.is_empty():
		parts.append(summary)
	return "  |  ".join(parts)


func _get_runtime_entry_icon(category_id: String, entry: Dictionary) -> Texture2D:
	var is_local := bool(entry.get("is_local", false))
	match category_id:
		"planets":
			return _get_runtime_icon_texture(
				"planet_local" if is_local else "planet",
				PALETTE_LIGHT_BRONZE if is_local else Color(0.42, 0.72, 0.9, 1.0)
			)
		"starbases":
			return _get_runtime_icon_texture(
				"starbase_local" if is_local else "starbase",
				PALETTE_LIGHT_BRONZE if is_local else Color(0.7, 0.76, 0.84, 1.0)
			)
		"passive_fleets":
			return _get_runtime_icon_texture(
				"passive_fleet_local" if is_local else "passive_fleet",
				PALETTE_LIGHT_BRONZE if is_local else Color(0.5, 0.78, 0.68, 1.0)
			)
		"military_fleets":
			return _get_runtime_icon_texture(
				"military_fleet_local" if is_local else "military_fleet",
				PALETTE_LIGHT_BRONZE if is_local else Color(0.92, 0.48, 0.46, 1.0)
			)
		_:
			return _get_runtime_icon_texture("generic", Color(0.72, 0.78, 0.84, 1.0))


func _get_runtime_icon_texture(icon_id: String, base_color: Color) -> Texture2D:
	if _runtime_icon_textures.has(icon_id):
		return _runtime_icon_textures[icon_id] as Texture2D

	var size_px := 28
	var center := Vector2(float(size_px) * 0.5, float(size_px) * 0.5)
	var radius := 9.5
	var image := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(size_px):
		for x in range(size_px):
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var distance := point.distance_to(center)
			if distance > radius + 1.5:
				continue
			var edge_alpha := clampf(radius + 1.5 - distance, 0.0, 1.0)
			if distance > radius:
				image.set_pixel(x, y, Color(0.06, 0.08, 0.1, 0.62 * edge_alpha))
				continue

			var light := clampf(1.0 - point.distance_to(Vector2(10.0, 8.0)) / 24.0, 0.0, 1.0)
			var color := base_color.darkened(0.18).lerp(base_color.lightened(0.26), light)
			color.a = edge_alpha
			if icon_id.begins_with("starbase"):
				if abs(point.x - center.x) < 1.7 or abs(point.y - center.y) < 1.7:
					color = color.lightened(0.28)
			elif icon_id.begins_with("passive_fleet") or icon_id.begins_with("military_fleet"):
				if point.y > center.y + abs(point.x - center.x) * 0.5 - 2.0:
					color = color.darkened(0.24)
			else:
				if point.distance_to(Vector2(10.0, 8.0)) < 3.0:
					color = color.lightened(0.42)
			image.set_pixel(x, y, color)

	var texture := ImageTexture.create_from_image(image)
	_runtime_icon_textures[icon_id] = texture
	return texture


func _get_empty_runtime_text(category_id: String) -> String:
	match category_id:
		"starbases":
			return "No owned stations yet."
		"planets":
			return "No owned colonies yet."
		"passive_fleets":
			return "No passive fleets yet."
		"military_fleets":
			return "No military fleets yet."
		_:
			return "No runtime entries."


func _get_runtime_entry_count(category_id: String) -> int:
	var entries_variant: Variant = _runtime_entries_by_category.get(category_id, [])
	if entries_variant is Array:
		return entries_variant.size()
	return 0


func _normalize_runtime_entries(entries_variant: Variant) -> Array[Dictionary]:
	var normalized_entries: Array[Dictionary] = []
	if entries_variant is not Array:
		return normalized_entries

	for entry_variant in entries_variant:
		if entry_variant is not Dictionary:
			continue
		normalized_entries.append((entry_variant as Dictionary).duplicate(true))

	return normalized_entries


func _build_context_text(category_id: String) -> String:
	var active_empire_label := _active_empire_name
	if active_empire_label == FALLBACK_CONTEXT_EMPIRE:
		active_empire_label = "your future empire"

	match category_id:
		"planets":
			if _selected_system_name == FALLBACK_CONTEXT_SYSTEM:
				return "%d colonies in %s space" % [_get_runtime_entry_count("planets"), active_empire_label]
			return "%d colonies  |  Focus %s" % [_get_runtime_entry_count("planets"), _selected_system_name]
		"starbases":
			return "%d owned stations  |  Focus %s" % [_get_runtime_entry_count("starbases"), _selected_system_name]
		"passive_fleets":
			return "%d support fleets  |  Focus %s" % [_get_runtime_entry_count("passive_fleets"), _selected_system_name]
		"military_fleets":
			return "%d military fleets  |  Focus %s" % [_get_runtime_entry_count("military_fleets"), _selected_system_name]
		_:
			return (
				"Active empire: %s  |  Selected system: %s  |  Owner: %s"
				% [
					_active_empire_name,
					_selected_system_name,
					_selected_system_owner_name,
				]
			)


func _refresh_responsive_layout() -> void:
	if not is_node_ready():
		return
	var target_height: float = expanded_height if _expanded else collapsed_height
	dock_panel.custom_minimum_size = Vector2(_get_responsive_bar_width(), target_height)


func _get_responsive_bar_width() -> float:
	var safe_max_width := maxf(size.x - 48.0, 320.0)
	var safe_min_width := minf(min_bar_width, safe_max_width)
	return clampf(size.x * width_ratio, safe_min_width, minf(max_bar_width, safe_max_width))


func _set_expanded(expanded: bool, animate: bool = true) -> void:
	var next_expanded := expanded and _interaction_enabled
	if _panel_tween != null:
		_panel_tween.kill()
	if _content_tween != null:
		_content_tween.kill()

	var active_content := _get_active_page_content()
	var start_height: float = dock_panel.custom_minimum_size.y
	var end_height: float = expanded_height if next_expanded else collapsed_height
	_expanded = next_expanded

	if not animate:
		_set_panel_height(end_height)
		if _expanded:
			_show_active_page_content(false)
		else:
			_hide_all_page_contents()
		_refresh_chrome_state()
		call_deferred("_refresh_bubble_positions")
		return

	if _expanded:
		_show_active_page_content(true)
	else:
		if active_content != null:
			_content_tween = create_tween()
			_content_tween.set_trans(Tween.TRANS_QUAD)
			_content_tween.set_ease(Tween.EASE_IN)
			_content_tween.tween_property(active_content, "modulate:a", 0.0, expand_duration * 0.55)
			_content_tween.tween_callback(_hide_all_page_contents)
		else:
			_hide_all_page_contents()

	_panel_tween = create_tween()
	_panel_tween.set_trans(Tween.TRANS_QUAD)
	_panel_tween.set_ease(Tween.EASE_OUT)
	_panel_tween.tween_method(_set_panel_height, start_height, end_height, expand_duration)
	_panel_tween.tween_callback(_refresh_responsive_layout)
	_refresh_chrome_state()
	call_deferred("_refresh_bubble_positions")


func _set_panel_height(value: float) -> void:
	dock_panel.custom_minimum_size.y = value
	if _chrome_layer != null:
		_chrome_layer.queue_redraw()


func _show_active_page_content(animate: bool) -> void:
	_hide_all_page_contents()
	var active_content := _get_active_page_content()
	if active_content == null:
		return

	active_content.visible = true
	active_content.modulate = Color(1.0, 1.0, 1.0, 0.0 if animate else 1.0)
	if not animate:
		return

	_content_tween = create_tween()
	_content_tween.set_trans(Tween.TRANS_QUAD)
	_content_tween.set_ease(Tween.EASE_OUT)
	_content_tween.tween_interval(expand_duration * 0.2)
	_content_tween.tween_property(active_content, "modulate:a", 1.0, expand_duration * 0.7)


func _hide_all_page_contents() -> void:
	for category_variant in _categories:
		var category: Dictionary = category_variant
		var page_content: Control = category.get("page_content", null) as Control
		if page_content != null:
			page_content.visible = false
			page_content.modulate = Color.WHITE


func _get_active_page_content() -> Control:
	if _selected_category_index < 0 or _selected_category_index >= _categories.size():
		return null
	return _categories[_selected_category_index].get("page_content", null) as Control


func _select_category(index: int, emit_signal: bool = true) -> void:
	if index < 0 or index >= _categories.size():
		return

	if tab_view.current_tab != index:
		_suppress_tab_signal = true
		tab_view.current_tab = index
		_suppress_tab_signal = false

	_selected_category_index = index
	_refresh_selected_theme()
	_refresh_bubble_theme()
	_refresh_chrome_state()
	if _expanded:
		_show_active_page_content(true)
	call_deferred("_refresh_bubble_positions")

	if emit_signal:
		category_selected.emit(_categories[index], index)


func _refresh_selected_theme() -> void:
	var accent: Color = _get_selected_accent()

	tab_view.add_theme_stylebox_override(
		"tab_selected", _build_tab_style(accent, accent.darkened(0.12))
	)
	tab_view.add_theme_stylebox_override(
		"tab_hovered",
		_build_tab_style(
			Color(0.12, 0.18, 0.22, 0.95),
			Color(0.54, 0.72, 0.82, 0.58)
		)
	)
	tab_view.add_theme_stylebox_override(
		"tab_unselected",
		_build_tab_style(
			Color(0.055, 0.075, 0.092, 0.9), Color(0.22, 0.34, 0.42, 0.48)
		)
	)
	tab_view.add_theme_stylebox_override(
		"tab_disabled",
		_build_tab_style(Color(0.04, 0.052, 0.064, 0.58), Color(0.1, 0.16, 0.2, 0.4))
	)
	tab_view.add_theme_stylebox_override("tab_focus", _build_focus_style(accent))


func _refresh_bubble_theme() -> void:
	for index in range(_bubble_nodes.size()):
		var bubble := _bubble_nodes[index]
		var bubble_label := (
			bubble.get_node_or_null(NodePath(str(bubble.get_meta("label_path")))) as Label
		)
		var accent: Color = DEFAULT_ACCENTS[index % DEFAULT_ACCENTS.size()]
		var is_selected := index == _selected_category_index
		var bubble_fill := PALETTE_LIGHT_BRONZE
		var bubble_border := PALETTE_LIGHT_BRONZE.darkened(0.15)
		var text_color := PALETTE_DUSK_BLUE.darkened(0.32)

		if is_selected:
			bubble_fill = accent.lightened(0.08)
			bubble_border = accent.darkened(0.12)
			text_color = Color(1.0, 0.98, 0.97, 1.0)

		bubble.add_theme_stylebox_override("panel", _build_bubble_style(bubble_fill, bubble_border))
		if bubble_label != null:
			bubble_label.add_theme_font_size_override("font_size", 12)
			bubble_label.add_theme_color_override("font_color", text_color)


func _refresh_bubble_positions() -> void:
	if _tab_bar == null:
		return

	for index in range(_bubble_nodes.size()):
		var bubble := _bubble_nodes[index]
		if index >= _tab_bar.tab_count:
			bubble.visible = false
			continue

		bubble.visible = true
		var rect: Rect2 = _tab_bar.get_tab_rect(index)
		var bubble_size: Vector2 = bubble.custom_minimum_size
		bubble.size = bubble_size
		var x_position: float = rect.position.x + rect.size.x * 0.5 - bubble_size.x * 0.5
		var y_position: float = rect.position.y - bubble_size.y * 0.72
		bubble.position = Vector2(round(x_position), round(y_position))


func _build_page_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.bg_color = Color(0.025, 0.035, 0.045, 0.0)
	style.border_color = Color(0.24, 0.42, 0.52, 0.0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(6)
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	return style


func _build_tabbar_background_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	return style


func _build_tab_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.16)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0.0, 2.0)
	style.content_margin_left = 16
	style.content_margin_top = 7
	style.content_margin_right = 16
	style.content_margin_bottom = 7
	return style


func _build_focus_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = accent.lightened(0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


func _build_list_style(fill_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_right = 8
	style.content_margin_bottom = 4
	return style


func _build_action_button_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_top = 5
	style.content_margin_right = 10
	style.content_margin_bottom = 5
	return style


func _build_bubble_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(999)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.14)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 2)
	return style


func _format_hotkey(hotkey: Key) -> String:
	if hotkey == KEY_NONE:
		return "-"
	return OS.get_keycode_string(hotkey)


func _on_tab_view_tab_changed(tab: int) -> void:
	if _suppress_tab_signal:
		return
	_last_tab_changed_frame = Engine.get_process_frames()
	_select_category(tab, true)
	_set_expanded(true)


func _on_tab_bar_tab_clicked(tab: int) -> void:
	if tab < 0 or tab >= _categories.size():
		return
	if Engine.get_process_frames() == _last_tab_changed_frame:
		return
	if tab == _selected_category_index:
		_set_expanded(not _expanded)


func _on_runtime_item_selected(_index: int, runtime_item_list: ItemList) -> void:
	var category_id := str(runtime_item_list.get_meta("category_id", ""))
	for category in _categories:
		if str(category.get("id", "")) != category_id:
			continue
		_refresh_runtime_action_button(category)
		return


func _on_runtime_item_activated(index: int, runtime_item_list: ItemList) -> void:
	var entry := _get_runtime_entry_at(runtime_item_list, index)
	if entry.is_empty():
		return
	runtime_entry_activated.emit(str(runtime_item_list.get_meta("category_id", "")), entry)


func _on_runtime_action_button_pressed(runtime_action_button: Button) -> void:
	var category_id := str(runtime_action_button.get_meta("category_id", ""))
	var list_path := NodePath(str(runtime_action_button.get_meta("runtime_item_list_path", NodePath(""))))
	var runtime_item_list := runtime_action_button.get_node_or_null(list_path) as ItemList
	if runtime_item_list == null:
		return
	var selected_items := runtime_item_list.get_selected_items()
	if selected_items.is_empty():
		return
	var entry := _get_runtime_entry_at(runtime_item_list, selected_items[0])
	if entry.is_empty():
		return
	runtime_action_requested.emit(category_id, entry)


func _get_runtime_entry_at(runtime_item_list: ItemList, index: int) -> Dictionary:
	if index < 0 or index >= runtime_item_list.get_item_count():
		return {}
	if runtime_item_list.is_item_disabled(index):
		return {}
	var metadata: Variant = runtime_item_list.get_item_metadata(index)
	if metadata is not Dictionary:
		return {}
	return (metadata as Dictionary).duplicate(true)


func _refresh_runtime_action_button(category: Dictionary) -> void:
	var runtime_item_list: ItemList = category.get("runtime_item_list", null) as ItemList
	var enabled := false
	if runtime_item_list != null and not runtime_item_list.get_selected_items().is_empty():
		enabled = not _get_runtime_entry_at(runtime_item_list, runtime_item_list.get_selected_items()[0]).is_empty()
	_set_runtime_action_button_state(category, enabled)


func _set_runtime_action_button_state(category: Dictionary, enabled: bool) -> void:
	var runtime_action_button: Button = category.get("runtime_action_button", null) as Button
	if runtime_action_button == null:
		return
	var category_id := str(category.get("id", ""))
	match category_id:
		"planets":
			runtime_action_button.text = "Manage Colony"
		_:
			runtime_action_button.text = "Open"
	runtime_action_button.disabled = not enabled
