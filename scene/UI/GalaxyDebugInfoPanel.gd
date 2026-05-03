extends PanelContainer
class_name GalaxyDebugInfoPanel

const PANEL_SIZE := Vector2(390.0, 184.0)

var _bound_label: Label = null
var _content_margin: MarginContainer = null
var _body_label_parent: VBoxContainer = null
var _button_row: HBoxContainer = null
var _time: float = 0.0


static func install(canvas_layer: Node, info_label: Label, action_buttons: Array[Button] = []) -> GalaxyDebugInfoPanel:
	if info_label == null:
		return null
	var existing_panel := _find_existing_panel(info_label)
	if existing_panel != null:
		existing_panel.bind_label(info_label)
		existing_panel.bind_buttons(action_buttons)
		return existing_panel

	var panel := GalaxyDebugInfoPanel.new()
	panel.name = "DebugInfoPanel"
	panel.visible = info_label.visible
	if canvas_layer != null:
		canvas_layer.add_child(panel)
	panel.bind_label(info_label)
	panel.bind_buttons(action_buttons)
	return panel


static func _find_existing_panel(info_label: Label) -> GalaxyDebugInfoPanel:
	var current := info_label.get_parent()
	while current != null:
		var panel := current as GalaxyDebugInfoPanel
		if panel != null:
			return panel
		current = current.get_parent()
	return null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	_configure_layout()


func _process(delta: float) -> void:
	_time += delta
	if _bound_label != null and visible != _bound_label.visible:
		visible = _bound_label.visible
	if visible:
		queue_redraw()


func _draw() -> void:
	if size.x < 120.0 or size.y < 60.0:
		return

	var points := PackedVector2Array([
		Vector2(18.0, 0.0),
		Vector2(size.x - 10.0, 0.0),
		Vector2(size.x, 12.0),
		Vector2(size.x - 16.0, size.y),
		Vector2(10.0, size.y),
		Vector2(0.0, size.y - 14.0),
		Vector2(0.0, 18.0),
	])
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(0.0, 5.0))

	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.24))
	draw_colored_polygon(points, Color(0.018, 0.03, 0.04, 0.72))
	draw_polyline(_closed_points(points), Color(0.34, 0.58, 0.7, 0.36), 1.4, true)
	draw_line(Vector2(26.0, 8.0), Vector2(size.x - 44.0, 8.0), Color(0.58, 0.42, 0.64, 0.5), 2.0, true)

	var pulse := 0.3 + sin(_time * TAU * 0.35) * 0.14
	draw_circle(Vector2(size.x - 18.0, 14.0), 3.2 + pulse, Color(0.58, 0.84, 1.0, 0.18))
	draw_circle(Vector2(size.x - 18.0, 14.0), 1.7, Color(0.88, 0.97, 1.0, 0.7))


func bind_label(info_label: Label) -> void:
	if info_label == null:
		return
	_bound_label = info_label
	_ensure_content()
	var old_parent := info_label.get_parent()
	if old_parent != _body_label_parent:
		if old_parent != null:
			old_parent.remove_child(info_label)
		_body_label_parent.add_child(info_label)
	info_label.custom_minimum_size = Vector2(0.0, 94.0)
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.clip_text = true
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", Color(0.9, 0.96, 0.98, 0.94))
	info_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	info_label.add_theme_constant_override("shadow_offset_x", 1)
	info_label.add_theme_constant_override("shadow_offset_y", 1)
	visible = info_label.visible


func bind_buttons(action_buttons: Array[Button]) -> void:
	_ensure_content()
	for button in action_buttons:
		if button == null:
			continue
		var old_parent := button.get_parent()
		if old_parent != _button_row:
			if old_parent != null:
				old_parent.remove_child(button)
			_button_row.add_child(button)
		_style_button(button)
	_button_row.visible = _button_row.get_child_count() > 0


func _configure_layout() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = PANEL_SIZE
	offset_left = 14.0
	offset_top = 64.0
	offset_right = offset_left + PANEL_SIZE.x
	offset_bottom = offset_top + PANEL_SIZE.y
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_ensure_content()


func _ensure_content() -> void:
	if _content_margin != null:
		return

	_content_margin = MarginContainer.new()
	_content_margin.name = "ContentMargin"
	_content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_margin.add_theme_constant_override("margin_left", 18)
	_content_margin.add_theme_constant_override("margin_top", 14)
	_content_margin.add_theme_constant_override("margin_right", 18)
	_content_margin.add_theme_constant_override("margin_bottom", 14)
	add_child(_content_margin)

	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.add_theme_constant_override("separation", 7)
	_content_margin.add_child(stack)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 7)
	stack.add_child(header)

	var title := Label.new()
	title.text = "Debug Telemetry"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.72, 0.96))
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var hint := Label.new()
	hint.text = "DEBUG"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.62, 0.78, 0.88, 0.62))
	header.add_child(hint)

	_body_label_parent = VBoxContainer.new()
	_body_label_parent.name = "Body"
	_body_label_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label_parent.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_body_label_parent)

	_button_row = HBoxContainer.new()
	_button_row.name = "ButtonRow"
	_button_row.add_theme_constant_override("separation", 7)
	stack.add_child(_button_row)


func _style_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(0.0, 26.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", Color(0.88, 0.94, 0.96, 0.95))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.84, 1.0))
	button.add_theme_stylebox_override("normal", _build_button_style(Color(0.05, 0.07, 0.09, 0.62), Color(0.28, 0.48, 0.58, 0.34)))
	button.add_theme_stylebox_override("hover", _build_button_style(Color(0.08, 0.11, 0.13, 0.86), Color(0.58, 0.82, 0.95, 0.58)))
	button.add_theme_stylebox_override("pressed", _build_button_style(Color(0.03, 0.045, 0.06, 0.95), Color(0.76, 0.92, 1.0, 0.78)))


func _build_button_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_right = 8
	style.content_margin_bottom = 4
	return style


func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if not points.is_empty():
		closed.append(points[0])
	return closed
