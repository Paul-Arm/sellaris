extends Node

## Presentation only: never changes simulation data or consumes its RNG.
const BASE_THEME: Theme = preload("res://scene/UI/theme/ObservatoryTheme.tres")
var _original: Theme
var _panels: Array[Dictionary] = []

func _ready() -> void:
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
	style.bg_color = Color(0.018, 0.025, 0.031, 0.96)
	style.border_color = Color(0.23, 0.29, 0.31, 0.52)
	style.set_corner_radius_all(0)
	style.shadow_size = 0

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
						flat.bg_color = Color(0.13, 0.24, 0.24, 1)
						flat.border_color = Color(0.62, 0.86, 0.81, 0.8)
					elif style_name in ["hover", "tab_hovered"]:
						flat.bg_color = Color(0.08, 0.13, 0.15, 1)
					elif style_name in ["focus", "tab_focus"]:
						flat.bg_color = Color.TRANSPARENT
						flat.border_color = Color(0.66, 0.92, 0.85)
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
	BASE_THEME.emit_changed()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		SettingsManager.set_design_variant("pastel" if is_clean() else "clean")
		get_viewport().set_input_as_handled()
