extends Control
class_name EmpireCommandDrawer

signal anomaly_open_requested(entry: Dictionary)
signal ship_designer_open_requested
signal research_open_requested

const ANOMALY_PANEL_SCRIPT: Script = preload("res://scene/UI/EmpireAnomalyListPanel.gd")

const DEFAULT_CATEGORIES: Array[Dictionary] = [
	{"id": "anomalies", "title": "Anomalien / Situationen"},
	{"id": "research", "title": "Forschung"},
	{"id": "ship_design", "title": "Schiffsdesign"},
	{"id": "diplomacy", "title": "Diplomatie"},
	{"id": "species", "title": "Spezies"},
	{"id": "government", "title": "Regierung"},
	{"id": "edicts", "title": "Beschluesse"},
]

@export var collapsed_width: float = 54.0
@export var expanded_width: float = 430.0
@export var drawer_height: float = 430.0
@export var animation_duration: float = 0.14

var _panel: PanelContainer = null
var _toggle_button: Button = null
var _expanded_area: HBoxContainer = null
var _category_row: VBoxContainer = null
var _content_root: Control = null
var _anomaly_panel: Control = null
var _ship_design_panel: Control = null
var _research_panel: Control = null
var _research_summary_label: Label = null
var _placeholder_label: Label = null
var _categories: Array[Dictionary] = []
var _category_buttons: Dictionary = {}
var _active_category_id: String = "anomalies"
var _expanded: bool = false
var _tween: Tween = null


func _ready() -> void:
	_build()
	set_categories(DEFAULT_CATEGORIES)
	set_active_category("anomalies")
	_set_expanded(false, false)


func set_categories(categories: Array) -> void:
	_categories.clear()
	for category_variant in categories:
		if category_variant is not Dictionary:
			continue
		var category: Dictionary = category_variant
		var category_id := str(category.get("id", "")).strip_edges()
		var title := str(category.get("title", category_id)).strip_edges()
		if category_id.is_empty() or title.is_empty():
			continue
		_categories.append({"id": category_id, "title": title})
	_rebuild_category_buttons()
	if _active_category_id.is_empty() and not _categories.is_empty():
		_active_category_id = str(_categories[0].get("id", ""))
	_refresh_active_category()


func set_active_category(category_id: String) -> void:
	var normalized_id := category_id.strip_edges()
	if normalized_id.is_empty():
		return
	_active_category_id = normalized_id
	_refresh_active_category()
	if not _expanded:
		_set_expanded(true)


func set_anomaly_entries(entries: Array) -> void:
	if _anomaly_panel != null:
		_anomaly_panel.call("set_entries", entries)


func set_research_summary(summary_text: String) -> void:
	if _research_summary_label != null:
		_research_summary_label.text = summary_text


func is_expanded() -> bool:
	return _expanded


func set_interaction_enabled(enabled: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	modulate = Color(1.0, 1.0, 1.0, 1.0 if enabled else 0.62)
	if _toggle_button != null:
		_toggle_button.disabled = not enabled
	for button_variant in _category_buttons.values():
		var button := button_variant as Button
		if button != null:
			button.disabled = not enabled
	if not enabled:
		_set_expanded(false)


func _build() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 14.0
	offset_top = 78.0
	offset_bottom = 78.0 + drawer_height
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _build_panel_style())
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	_toggle_button = Button.new()
	_toggle_button.custom_minimum_size = Vector2(30.0, 36.0)
	_toggle_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_toggle_button.text = "≡"
	_toggle_button.tooltip_text = "Empire-Menue"
	_toggle_button.pressed.connect(func() -> void: _set_expanded(not _expanded))
	_style_toggle_button(_toggle_button)
	row.add_child(_toggle_button)

	_expanded_area = HBoxContainer.new()
	_expanded_area.name = "ExpandedArea"
	_expanded_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_expanded_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_expanded_area.add_theme_constant_override("separation", 10)
	row.add_child(_expanded_area)

	_category_row = VBoxContainer.new()
	_category_row.custom_minimum_size = Vector2(126.0, 0.0)
	_category_row.add_theme_constant_override("separation", 6)
	_expanded_area.add_child(_category_row)

	_content_root = Control.new()
	_content_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_expanded_area.add_child(_content_root)

	_anomaly_panel = ANOMALY_PANEL_SCRIPT.new() as Control
	_anomaly_panel.connect("anomaly_open_requested", Callable(self, "_on_anomaly_open_requested"))
	_content_root.add_child(_anomaly_panel)

	_ship_design_panel = _build_ship_design_panel()
	_content_root.add_child(_ship_design_panel)

	_research_panel = _build_research_panel()
	_content_root.add_child(_research_panel)

	_placeholder_label = Label.new()
	_placeholder_label.name = "PlaceholderLabel"
	_placeholder_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placeholder_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder_label.add_theme_font_size_override("font_size", 14)
	_placeholder_label.add_theme_color_override("font_color", Color(0.74, 0.82, 0.88, 0.82))
	_content_root.add_child(_placeholder_label)


func _rebuild_category_buttons() -> void:
	if _category_row == null:
		return
	for child in _category_row.get_children():
		child.queue_free()
	_category_buttons.clear()

	for category in _categories:
		var category_id := str(category.get("id", ""))
		var button := Button.new()
		button.text = str(category.get("title", category_id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0.0, 30.0)
		button.tooltip_text = button.text
		button.pressed.connect(_on_category_button_pressed.bind(category_id))
		_style_category_button(button, false)
		_category_row.add_child(button)
		_category_buttons[category_id] = button


func _refresh_active_category() -> void:
	if _anomaly_panel == null:
		return
	for category_id_variant in _category_buttons.keys():
		var category_id := str(category_id_variant)
		var button := _category_buttons[category_id] as Button
		if button != null:
			_style_category_button(button, category_id == _active_category_id)

	var is_anomaly_category := _active_category_id == "anomalies"
	var is_ship_design_category := _active_category_id == "ship_design"
	var is_research_category := _active_category_id == "research"
	_anomaly_panel.visible = is_anomaly_category
	if _ship_design_panel != null:
		_ship_design_panel.visible = is_ship_design_category
	if _research_panel != null:
		_research_panel.visible = is_research_category
	_placeholder_label.visible = not is_anomaly_category and not is_ship_design_category and not is_research_category
	if _placeholder_label.visible:
		_placeholder_label.text = "%s ist vorbereitet und wartet auf die naechste Datenquelle." % _get_category_title(_active_category_id)


func _set_expanded(expanded: bool, animate: bool = true) -> void:
	if _tween != null:
		_tween.kill()
	_expanded = expanded
	_toggle_button.text = "‹" if _expanded else "≡"
	if _expanded_area != null:
		_expanded_area.visible = _expanded

	var target_width := expanded_width if _expanded else collapsed_width
	if not animate:
		custom_minimum_size = Vector2(target_width, drawer_height if _expanded else 52.0)
		size = custom_minimum_size
		return

	var start_width := maxf(size.x, custom_minimum_size.x)
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_drawer_width, start_width, target_width, animation_duration)


func _set_drawer_width(value: float) -> void:
	custom_minimum_size = Vector2(value, drawer_height if _expanded else 52.0)
	size = custom_minimum_size


func _get_category_title(category_id: String) -> String:
	for category in _categories:
		if str(category.get("id", "")) == category_id:
			return str(category.get("title", category_id))
	return category_id.replace("_", " ").capitalize()


func _build_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.038, 0.05, 0.88)
	style.border_color = Color(0.38, 0.58, 0.68, 0.36)
	style.set_border_width_all(1)
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	style.shadow_size = 10
	style.shadow_offset = Vector2(2.0, 2.0)
	return style


func _style_toggle_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _build_button_style(Color(0.06, 0.08, 0.1, 0.92), Color(0.32, 0.5, 0.6, 0.52)))
	button.add_theme_stylebox_override("hover", _build_button_style(Color(0.1, 0.13, 0.16, 1.0), Color(0.58, 0.78, 0.9, 0.7)))
	button.add_theme_stylebox_override("pressed", _build_button_style(Color(0.04, 0.06, 0.08, 1.0), Color(0.7, 0.9, 1.0, 0.82)))
	button.add_theme_stylebox_override("disabled", _build_button_style(Color(0.04, 0.05, 0.06, 0.6), Color(0.14, 0.18, 0.22, 0.42)))


func _style_category_button(button: Button, active: bool) -> void:
	var fill := Color(0.07, 0.095, 0.12, 0.96) if active else Color(0.035, 0.05, 0.064, 0.74)
	var border := Color(0.75, 0.58, 0.4, 0.62) if active else Color(0.26, 0.4, 0.48, 0.36)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color(0.94, 0.97, 0.99, 0.96) if active else Color(0.78, 0.86, 0.9, 0.9))
	button.add_theme_stylebox_override("normal", _build_button_style(fill, border))
	button.add_theme_stylebox_override("hover", _build_button_style(Color(0.1, 0.135, 0.16, 1.0), Color(0.58, 0.78, 0.9, 0.64)))
	button.add_theme_stylebox_override("pressed", _build_button_style(Color(0.04, 0.065, 0.085, 1.0), Color(0.74, 0.9, 1.0, 0.8)))


func _build_button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ObservatoryStyle.SURFACE.lerp(fill, 0.22)
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_top = 5
	style.content_margin_right = 8
	style.content_margin_bottom = 5
	return style


func _on_category_button_pressed(category_id: String) -> void:
	set_active_category(category_id)


func _build_ship_design_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.name = "ShipDesignPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 10)

	var info := Label.new()
	info.text = "Entwirf Schiffs- und Stationsdesigns aus freigeschalteten Komponenten. Werften bauen die gespeicherten Designs."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.74, 0.82, 0.88, 0.82))
	panel.add_child(info)

	var open_button := Button.new()
	open_button.name = "OpenShipDesignerButton"
	open_button.text = "Schiffsdesigner oeffnen"
	open_button.custom_minimum_size = Vector2(0.0, 34.0)
	open_button.pressed.connect(func() -> void:
		ship_designer_open_requested.emit()
	)
	panel.add_child(open_button)
	return panel


func _build_research_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.name = "ResearchPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 10)

	var info := Label.new()
	info.text = "Waehle pro Disziplin ein Forschungsprojekt aus dem aktuellen Angebot. Abschluesse erzeugen Momentum und schalten neue Stufen frei."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.74, 0.82, 0.88, 0.82))
	panel.add_child(info)

	_research_summary_label = Label.new()
	_research_summary_label.name = "ResearchSummaryLabel"
	_research_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_research_summary_label.add_theme_font_size_override("font_size", 12)
	_research_summary_label.add_theme_color_override("font_color", Color(0.86, 0.92, 0.96, 0.92))
	panel.add_child(_research_summary_label)

	var open_button := Button.new()
	open_button.name = "OpenResearchButton"
	open_button.text = "Forschung oeffnen"
	open_button.custom_minimum_size = Vector2(0.0, 34.0)
	open_button.pressed.connect(func() -> void:
		research_open_requested.emit()
	)
	panel.add_child(open_button)
	return panel


func _on_anomaly_open_requested(entry: Dictionary) -> void:
	anomaly_open_requested.emit(entry)
