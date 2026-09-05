extends PanelContainer
class_name EmpireListActionRow

signal action_requested(entry: Dictionary)

const STATUS_COLORS := {
	"discovered": Color(0.9, 0.62, 0.38, 1.0),
	"researched": Color(0.54, 0.78, 0.92, 1.0),
}

var _entry: Dictionary = {}
var _title_label: Label = null
var _meta_label: Label = null
var _status_label: Label = null
var _action_button: Button = null


func _ready() -> void:
	_build()
	_apply_entry()


func set_entry(entry: Dictionary) -> void:
	_entry = entry.duplicate(true)
	_apply_entry()


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0.0, 58.0)
	add_theme_stylebox_override("panel", _build_panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	add_child(margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)

	_title_label = Label.new()
	_title_label.clip_text = true
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color(0.94, 0.97, 0.99, 0.96))
	text_box.add_child(_title_label)

	_meta_label = Label.new()
	_meta_label.clip_text = true
	_meta_label.add_theme_font_size_override("font_size", 12)
	_meta_label.add_theme_color_override("font_color", Color(0.72, 0.8, 0.86, 0.86))
	text_box.add_child(_meta_label)

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(82.0, 24.0)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 11)
	row.add_child(_status_label)

	_action_button = Button.new()
	_action_button.custom_minimum_size = Vector2(72.0, 28.0)
	_action_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_action_button.text = "Oeffnen"
	_action_button.pressed.connect(_on_action_button_pressed)
	_style_button(_action_button)
	row.add_child(_action_button)


func _apply_entry() -> void:
	if _title_label == null:
		return

	var title := str(_entry.get("title", "Unbenannt")).strip_edges()
	var meta := str(_entry.get("meta", "")).strip_edges()
	var status := str(_entry.get("status", "")).strip_edges()
	var action_label := str(_entry.get("action_label", "Oeffnen")).strip_edges()
	var action_enabled := bool(_entry.get("action_enabled", true))

	_title_label.text = title if not title.is_empty() else "Unbenannt"
	_meta_label.text = meta
	_status_label.text = _format_status(status)
	_status_label.add_theme_color_override("font_color", _get_status_color(status))
	_status_label.add_theme_stylebox_override("normal", _build_badge_style(_get_status_color(status)))
	_action_button.text = action_label if not action_label.is_empty() else "Oeffnen"
	_action_button.disabled = not action_enabled
	tooltip_text = str(_entry.get("tooltip", ""))


func _format_status(status: String) -> String:
	if status.is_empty():
		return "Status"
	return status.replace("_", " ").capitalize()


func _get_status_color(status: String) -> Color:
	return STATUS_COLORS.get(status, Color(0.7, 0.76, 0.82, 1.0))


func _build_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.064, 0.72)
	style.border_color = Color(0.28, 0.42, 0.5, 0.34)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style


func _build_badge_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.12)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.42)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 7
	style.content_margin_top = 3
	style.content_margin_right = 7
	style.content_margin_bottom = 3
	return style


func _style_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color(0.91, 0.96, 0.98, 0.96))
	button.add_theme_color_override("font_disabled_color", Color(0.68, 0.74, 0.78, 0.48))
	button.add_theme_stylebox_override("normal", _build_button_style(Color(0.07, 0.095, 0.12, 0.95), Color(0.34, 0.54, 0.64, 0.52)))
	button.add_theme_stylebox_override("hover", _build_button_style(Color(0.11, 0.15, 0.18, 1.0), Color(0.58, 0.78, 0.9, 0.72)))
	button.add_theme_stylebox_override("pressed", _build_button_style(Color(0.04, 0.065, 0.085, 1.0), Color(0.74, 0.9, 1.0, 0.88)))
	button.add_theme_stylebox_override("disabled", _build_button_style(Color(0.045, 0.055, 0.065, 0.72), Color(0.16, 0.22, 0.26, 0.4)))


func _build_button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ObservatoryStyle.SURFACE.lerp(fill, 0.22)
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_right = 8
	style.content_margin_bottom = 4
	return style


func _on_action_button_pressed() -> void:
	if _entry.is_empty():
		return
	action_requested.emit(_entry.duplicate(true))
