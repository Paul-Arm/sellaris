extends Node

## Presentation only: never changes simulation data or consumes its RNG.
const BASE_THEME: Theme = preload("res://scene/UI/theme/ObservatoryTheme.tres")
var _original: Theme
var _panels: Array[Dictionary] = []

func _ready() -> void:
	get_tree().node_added.connect(_on_control_added)
	_original = BASE_THEME.duplicate(true)
	SettingsManager.design_changed.connect(_apply)
	_apply(SettingsManager.get_design_variant())

func is_clean() -> bool:
	return SettingsManager.get_design_variant() == "clean"

func track_panel(style: StyleBoxFlat) -> void:
	_panels.append({"ref": weakref(style), "fill": style.bg_color, "edge": style.border_color})
	if is_clean():
		_style_panel(style)

func _style_panel(style: StyleBoxFlat) -> void:
	style.bg_color = Color(0.012, 0.019, 0.024, 0.97)
	style.border_color = Color(0.16, 0.24, 0.27, 0.55)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	style.content_margin_left = minf(style.content_margin_left, 8.0)
	style.content_margin_right = minf(style.content_margin_right, 8.0)
	style.content_margin_top = minf(style.content_margin_top, 4.0)
	style.content_margin_bottom = minf(style.content_margin_bottom, 4.0)

func _apply(variant: String) -> void:
	var clean := variant == "clean"
	RenderingServer.global_shader_parameter_set("design_clean", clean)
	# Mutate the shared project theme so existing controls update as well.
	for type_name in _original.get_type_list():
		for style_name in _original.get_stylebox_list(type_name):
			var style: StyleBox = _original.get_stylebox(style_name, type_name).duplicate()
			if style is StyleBoxFlat:
				var flat := style as StyleBoxFlat
				if clean:
					_style_panel(flat)
					if style_name in ["pressed", "selected", "selected_focus", "tab_selected", "fill"] or type_name == "PrimaryButton":
						flat.bg_color = Color("34302a")
						flat.border_color = Color("e6b878")
					elif style_name in ["hover", "tab_hovered"]:
						flat.bg_color = Color("223247")
					elif style_name in ["focus", "tab_focus"]:
						flat.bg_color = Color.TRANSPARENT
						flat.border_color = Color("e6b878")
						flat.set_border_width_all(2)
				else:
					flat.bg_color = flat.bg_color.lerp(Color(0.075, 0.064, 0.097, flat.bg_color.a), 0.22)
					flat.border_color = flat.border_color.lerp(Color(0.51, 0.46, 0.57, flat.border_color.a), 0.28)
			BASE_THEME.set_stylebox(style_name, type_name, style)
	for index in range(_panels.size() - 1, -1, -1):
		var style: StyleBoxFlat = _panels[index]["ref"].get_ref()
		if style == null:
			_panels.remove_at(index)
		elif clean:
			_style_panel(style)
		else:
			style.bg_color = _panels[index]["fill"]
			style.border_color = _panels[index]["edge"]
			style.set_corner_radius_all(3)
	BASE_THEME.set("default_font_size", 13 if clean else _original.default_font_size)
	for type_name in _original.get_type_list():
		for font_name in _original.get_font_size_list(type_name):
			var original_size := _original.get_font_size(font_name, type_name)
			BASE_THEME.set_font_size(font_name, type_name, clampi(roundi(original_size * 0.82), 11, 24) if clean else original_size)
	# Clean uses native logical pixels, so a larger monitor reveals more space.
	get_tree().root.content_scale_size = Vector2i.ZERO if clean else Vector2i(1600, 900)
	_refresh_controls.call_deferred(get_tree().root)
	BASE_THEME.emit_changed()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		SettingsManager.set_design_variant("pastel" if is_clean() else "clean")
		get_viewport().set_input_as_handled()


func _on_control_added(node: Node) -> void:
	if node is Control:
		_style_control_deferred.call_deferred(weakref(node))


func _style_control_deferred(reference: WeakRef) -> void:
	var control: Control = reference.get_ref()
	if control != null:
		_style_control(control)


func _refresh_controls(node: Node) -> void:
	if node is Control:
		_style_control(node)
	for child in node.get_children():
		_refresh_controls(child)


func _style_control(control: Control) -> void:
	var ancestor: Node = control
	while ancestor != null:
		if ancestor.has_meta("atlas_ui"):
			return
		ancestor = ancestor.get_parent()
	if not control.has_meta("design_metrics"):
		var metrics := {"minimum": control.custom_minimum_size, "constants": {}, "styles": {}}
		if control is TabBar or control is TabContainer:
			metrics["selected_text"] = control.get_theme_color("font_selected_color")
		if control.has_theme_font_size_override("font_size"):
			metrics["font"] = control.get_theme_font_size("font_size")
		for key in ["separation", "h_separation", "v_separation", "margin_left", "margin_right", "margin_top", "margin_bottom"]:
			if control.has_theme_constant_override(key):
				metrics["constants"][key] = control.get_theme_constant(key)
		for property in control.get_property_list():
			var key := str(property["name"])
			if key.begins_with("theme_override_styles/") and control.get(key) is StyleBoxFlat:
				metrics["styles"][key] = control.get(key).duplicate()
		control.set_meta("design_metrics", metrics)
	var metrics: Dictionary = control.get_meta("design_metrics")
	var clean := is_clean()
	if metrics.has("selected_text"):
		control.add_theme_color_override("font_selected_color", Color("e6b878") if clean else metrics["selected_text"])
	if metrics.has("font"):
		var font_size := int(metrics["font"])
		control.add_theme_font_size_override("font_size", clampi(roundi(font_size * 0.84), 11, 24) if clean else font_size)
	for key in metrics["constants"]:
		var value := int(metrics["constants"][key])
		control.add_theme_constant_override(key, maxi(2, roundi(value * 0.6)) if clean else value)
	for key in metrics["styles"]:
		var style: StyleBoxFlat = metrics["styles"][key].duplicate()
		if clean:
			_style_panel(style)
			if str(key).ends_with("hover"):
				style.bg_color = Color(0.045, 0.09, 0.10)
			elif str(key).ends_with("pressed") or str(key).ends_with("selected"):
				style.bg_color = Color(0.075, 0.18, 0.18)
		control.set(key, style)
	if control is BaseButton:
		var minimum: Vector2 = metrics["minimum"]
		control.custom_minimum_size = Vector2(minf(minimum.x, 160), minf(minimum.y, 28)) if clean else minimum
