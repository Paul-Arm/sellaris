extends Control
class_name BottomCategoryBar

signal category_selected(category: Dictionary, index: int)

const MAX_CATEGORY_COUNT := 9
const FALLBACK_CONTEXT_EMPIRE := "None selected"
const FALLBACK_CONTEXT_SYSTEM := "No system selected"
const FALLBACK_CONTEXT_OWNER := "Unclaimed"
const PALETTE_DUSK_BLUE := Color("355070")
const PALETTE_DUSTY_LAVENDER := Color("6D597A")
const PALETTE_ROSEWOOD := Color("B56576")
const PALETTE_LIGHT_CORAL := Color("E56B6F")
const PALETTE_LIGHT_BRONZE := Color("EAAC8B")
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
@export_range(0.35, 0.95, 0.01) var width_ratio: float = 0.68
@export_range(460.0, 1400.0, 10.0) var min_bar_width: float = 640.0
@export_range(600.0, 1800.0, 10.0) var max_bar_width: float = 1180.0
@export_range(44.0, 100.0, 1.0) var collapsed_height: float = 62.0
@export_range(120.0, 280.0, 1.0) var expanded_height: float = 188.0
@export_range(0.05, 0.4, 0.01) var expand_duration: float = 0.2

@onready var dock_panel: PanelContainer = $BottomAnchor/BottomAlign/CenterRow/DockPanel
@onready
var overlay_root: Control = $BottomAnchor/BottomAlign/CenterRow/DockPanel/DockMargin/OverlayRoot
@onready
var tab_view: TabContainer = $BottomAnchor/BottomAlign/CenterRow/DockPanel/DockMargin/OverlayRoot/TabView
@onready
var bubble_layer: Control = $BottomAnchor/BottomAlign/CenterRow/DockPanel/DockMargin/OverlayRoot/BubbleLayer

var _tab_bar: TabBar
var _categories: Array[Dictionary] = []
var _bubble_nodes: Array[Control] = []
var _selected_category_index: int = -1
var _interaction_enabled: bool = true
var _expanded: bool = false
var _suppress_tab_signal: bool = false
var _panel_tween: Tween
var _content_tween: Tween
var _active_empire_name: String = FALLBACK_CONTEXT_EMPIRE
var _selected_system_name: String = FALLBACK_CONTEXT_SYSTEM
var _selected_system_owner_name: String = FALLBACK_CONTEXT_OWNER


func _ready() -> void:
	_tab_bar = tab_view.get_tab_bar()
	_configure_tab_view()
	_collect_categories_from_pages()
	_build_bubbles()
	_apply_theme()
	_refresh_tab_titles()
	_refresh_page_contexts()
	if not _categories.is_empty():
		_select_category(clampi(tab_view.current_tab, 0, _categories.size() - 1), false)
	_set_expanded(false, false)
	_refresh_responsive_layout()
	dock_panel.mouse_entered.connect(_on_dock_mouse_entered)
	dock_panel.mouse_exited.connect(_on_dock_mouse_exited)
	tab_view.tab_changed.connect(_on_tab_view_tab_changed)
	call_deferred("_refresh_bubble_positions")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_refresh_responsive_layout()
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
	if not _categories.is_empty():
		_select_category(clampi(current_index, 0, _categories.size() - 1), false)
	call_deferred("_refresh_bubble_positions")


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
			_select_category(index)
			return true

	return false


func get_selected_category() -> Dictionary:
	if _selected_category_index < 0 or _selected_category_index >= _categories.size():
		return {}
	return _categories[_selected_category_index]


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
		var accent_line: ColorRect = (
			page.get_node_or_null("PageContent/PageMargin/PageVBox/AccentLine") as ColorRect
		)
		var context_label: Label = (
			page.get_node_or_null("PageContent/PageMargin/PageVBox/ContextLabel") as Label
		)
		var accent: Color = DEFAULT_ACCENTS[index % DEFAULT_ACCENTS.size()]
		if accent_line != null:
			accent = accent_line.color

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
	tab_view.tabs_position = TabContainer.POSITION_BOTTOM
	tab_view.use_hidden_tabs_for_min_size = false
	tab_view.all_tabs_in_front = true

	_tab_bar.clip_tabs = false
	_tab_bar.scrolling_enabled = false
	_tab_bar.scroll_to_selected = false
	_tab_bar.max_tab_width = 0


func _build_bubbles() -> void:
	for child in bubble_layer.get_children():
		child.queue_free()
	_bubble_nodes.clear()

	for index in range(_categories.size()):
		var bubble := PanelContainer.new()
		bubble.custom_minimum_size = Vector2(30, 30)
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble.size = bubble.custom_minimum_size

		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble.add_child(center)

		var label := Label.new()
		label.text = _format_hotkey(int(_categories[index].get("hotkey", KEY_NONE)))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		center.add_child(label)

		bubble.set_meta("label_path", bubble.get_path_to(label))
		bubble_layer.add_child(bubble)
		_bubble_nodes.append(bubble)

	_refresh_bubble_theme()


func _apply_theme() -> void:
	dock_panel.add_theme_stylebox_override(
		"panel",
		_build_panel_style(
			PALETTE_DUSK_BLUE.darkened(0.18), PALETTE_DUSTY_LAVENDER.lightened(0.05), 24, 0.94
		)
	)

	tab_view.add_theme_stylebox_override("panel", _build_page_panel_style())
	tab_view.add_theme_stylebox_override("tabbar_background", _build_tabbar_background_style())
	tab_view.add_theme_color_override("font_unselected_color", Color(0.96, 0.93, 0.95, 0.82))
	tab_view.add_theme_color_override("font_hovered_color", Color(1.0, 0.98, 0.97, 1.0))
	tab_view.add_theme_color_override("font_selected_color", PALETTE_DUSK_BLUE.darkened(0.25))
	tab_view.add_theme_color_override("font_disabled_color", Color(0.96, 0.93, 0.95, 0.42))
	tab_view.add_theme_font_size_override("font_size", 14)
	_refresh_selected_theme()


func _refresh_tab_titles() -> void:
	for index in range(_categories.size()):
		var category: Dictionary = _categories[index]
		var title := str(category.get("title", "Tab"))
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


func _build_context_text(category_id: String) -> String:
	var active_empire_label := _active_empire_name
	if active_empire_label == FALLBACK_CONTEXT_EMPIRE:
		active_empire_label = "your future empire"

	match category_id:
		"planets":
			if _selected_system_name == FALLBACK_CONTEXT_SYSTEM:
				return (
					"Select a system to surface its worlds here. Active empire: %s."
					% _active_empire_name
				)
			return (
				"%s currently belongs to %s. This page is ready for worlds, districts, and build queues."
				% [
					_selected_system_name,
					_selected_system_owner_name,
				]
			)
		"starbases":
			return (
				"Use this page for choke points, shipyards, and anchorages across %s space. Selected system: %s."
				% [
					active_empire_label,
					_selected_system_name,
				]
			)
		"passive_fleets":
			return (
				"Civilian and support task groups can stay organized here. Selected system: %s."
				% _selected_system_name
			)
		"military_fleets":
			return (
				"Combat fleets, rally anchors, and offensive staging can cluster here for %s. Focus: %s."
				% [
					active_empire_label,
					_selected_system_name,
				]
			)
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
	call_deferred("_refresh_bubble_positions")


func _set_panel_height(value: float) -> void:
	dock_panel.custom_minimum_size.y = value


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
	if _expanded:
		_show_active_page_content(true)
	call_deferred("_refresh_bubble_positions")

	if emit_signal:
		category_selected.emit(_categories[index], index)


func _refresh_selected_theme() -> void:
	var accent: Color = PALETTE_LIGHT_CORAL
	if _selected_category_index >= 0 and _selected_category_index < _categories.size():
		accent = _categories[_selected_category_index].get("accent", accent)

	tab_view.add_theme_stylebox_override(
		"tab_selected", _build_tab_style(accent, accent.darkened(0.12))
	)
	tab_view.add_theme_stylebox_override(
		"tab_hovered",
		_build_tab_style(
			PALETTE_LIGHT_BRONZE.lerp(PALETTE_DUSTY_LAVENDER, 0.38),
			PALETTE_LIGHT_BRONZE.darkened(0.18)
		)
	)
	tab_view.add_theme_stylebox_override(
		"tab_unselected",
		_build_tab_style(
			PALETTE_DUSTY_LAVENDER.darkened(0.08), PALETTE_DUSTY_LAVENDER.lightened(0.08)
		)
	)
	tab_view.add_theme_stylebox_override(
		"tab_disabled",
		_build_tab_style(PALETTE_DUSK_BLUE.lightened(0.02), PALETTE_DUSTY_LAVENDER.darkened(0.18))
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
		var x_position: float = (
			_tab_bar.position.x + rect.position.x + rect.size.x * 0.5 - bubble_size.x * 0.5
		)
		var y_position: float = _tab_bar.position.y + rect.position.y - bubble_size.y * 0.72
		bubble.position = Vector2(round(x_position), round(y_position))


func _build_panel_style(
	background: Color, border: Color, radius: int, alpha: float
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.bg_color.a = alpha
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 6)
	return style


func _build_page_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PALETTE_DUSK_BLUE.darkened(0.08)
	style.bg_color.a = 0.98
	style.border_color = PALETTE_DUSTY_LAVENDER.lightened(0.04)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
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
	style.set_corner_radius_all(999)
	style.content_margin_left = 18
	style.content_margin_top = 10
	style.content_margin_right = 18
	style.content_margin_bottom = 10
	return style


func _build_focus_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = accent.lightened(0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(999)
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


func _on_dock_mouse_entered() -> void:
	if not _interaction_enabled:
		return
	_set_expanded(true)


func _on_dock_mouse_exited() -> void:
	_set_expanded(false)


func _on_tab_view_tab_changed(tab: int) -> void:
	if _suppress_tab_signal:
		return
	_select_category(tab, true)
