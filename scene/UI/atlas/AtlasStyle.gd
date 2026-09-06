extends RefCounted

const INK := Color("0b111c")
const PANEL := Color("131e2d")
const TEXT := Color("e8e7df")
const MUTED := Color("8594a8")
const ACCENT := Color("e6b878")
const LINE := Color("2b394b")

static func box(fill: Color = PANEL, edge: Color = LINE, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

static func button_box(fill: Color = PANEL, edge: Color = LINE, radius: int = 6) -> StyleBoxFlat:
	var style := box(fill, edge, radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

static func label(parent: Node, text: String, font_size: int = 14, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node

static func button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(0, 38)
	node.add_theme_font_size_override("font_size", 14)
	node.add_theme_color_override("font_color", INK if primary else TEXT)
	node.add_theme_color_override("font_hover_color", INK if primary else Color.WHITE)
	node.add_theme_color_override("font_pressed_color", INK if primary else ACCENT)
	node.add_theme_stylebox_override("normal", button_box(ACCENT if primary else Color("172334"), ACCENT if primary else LINE, 6))
	node.add_theme_stylebox_override("hover", button_box(ACCENT.lightened(0.1) if primary else Color("223247"), ACCENT, 6))
	node.add_theme_stylebox_override("pressed", button_box(ACCENT.darkened(0.1) if primary else Color("293443"), ACCENT, 6))
	var focus := box(Color.TRANSPARENT, ACCENT, 6)
	focus.draw_center = false
	node.add_theme_stylebox_override("focus", focus)
	node.pressed.connect(action)
	parent.add_child(node)
	return node

static func rect(control: Control, position: Vector2, extent: Vector2) -> void:
	control.position = position
	control.size = extent

# Preserve local overrides when borrowing existing game controls for this shell.
static func adopt(node: Node) -> void:
	if node is Control and not node.has_meta("atlas_overrides"):
		var changes: Dictionary = {}
		if node is PanelContainer or node is Panel:
			changes["theme_override_styles/panel"] = box()
		if node is Label or node is BaseButton:
			changes["theme_override_colors/font_color"] = TEXT
		if node is BaseButton:
			changes["theme_override_styles/normal"] = button_box()
			changes["theme_override_styles/hover"] = button_box(Color("223247"), ACCENT)
		var original: Dictionary = {}
		for key in changes:
			original[key] = node.get(key)
			node.set(key, changes[key])
		node.set_meta("atlas_overrides", original)
	for child in node.get_children(): adopt(child)

static func release(node: Node) -> void:
	if node.has_meta("atlas_overrides"):
		var original: Dictionary = node.get_meta("atlas_overrides")
		for key in original: node.set(key, original[key])
		node.remove_meta("atlas_overrides")
	for child in node.get_children(): release(child)
