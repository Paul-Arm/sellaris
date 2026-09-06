extends Control
const S = preload("res://scene/UI/atlas/AtlasStyle.gd")
var host: Control
var heading: Label
var subheading: Label
var index_panel: PanelContainer
var rows: VBoxContainer
var filter_row: HBoxContainer
var index_toggle: Button
var back: Button
var reset: Button
var guide: Label
var search: LineEdit
var exit_tags: Array[Button] = []
var _exit_tag_field_id := 0
var _filter := "all"
var _signature := ""
var _collapsed := false

func _ready() -> void:
	name = "AtlasSystemInterface"
	set_meta("atlas_ui", true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading = S.label(self, "", 30)
	subheading = S.label(self, "SYSTEM / LIVE SURVEY", 11, S.ACCENT)
	back = S.button(self, "<  Galaxy", func(): host.close_requested.emit())
	reset = S.button(self, "Recenter", _recenter)
	index_toggle = S.button(self, "Objects", _toggle_objects)
	guide = S.label(self, "SCROLL  Zoom     /     RIGHT DRAG  Orbit     /     MIDDLE DRAG  Pan", 11, S.MUTED)
	index_panel = PanelContainer.new()
	index_panel.add_theme_stylebox_override("panel", S.box())
	add_child(index_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	index_panel.add_child(column)
	S.label(column, "SYSTEM INDEX", 11, S.ACCENT)
	search = LineEdit.new()
	search.placeholder_text = "Find an object..."
	search.custom_minimum_size.y = 36
	search.text_changed.connect(func(_text): _rebuild())
	column.add_child(search)
	filter_row = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	column.add_child(filter_row)
	for entry in [["All", "all"], ["Worlds", "planet"], ["Ships", "ships"], ["Routes", "routes"]]:
		var key: String = entry[1]
		var button := S.button(filter_row, entry[0], func(): _filter = key; _rebuild())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	resized.connect(_layout)
	_layout()

func _process(_delta: float) -> void:
	visible = DesignDirector.is_clean() and host.visible
	if not visible: return
	var details: Dictionary = host.get("_current_system_details")
	heading.text = str(details.get("name", "Unknown system"))
	subheading.text = "SYSTEM  /  " + str(details.get("owner_name", "Unclaimed")).to_upper()
	var signature: String = str(details.get("id", "")) + str(host.preview.get("_selectables").size()) + host.preview.get_selected_selection_id() + str(details.get("hyperlane_exits", []))
	if signature != _signature:
		_signature = signature
		_rebuild()
	var inspecting: bool = host.get("_body_details_panel").visible
	index_toggle.text = "Objects" if _collapsed or inspecting else "Hide list"
	index_panel.visible = not _collapsed and not inspecting
	_update_exit_tags()

func _layout() -> void:
	if index_panel == null: return
	var left := 120.0
	S.rect(subheading, Vector2(left, 89), Vector2(size.x - left - 360, 18))
	S.rect(heading, Vector2(left, 112), Vector2(maxf(200, size.x - left - 360), 42))
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	S.rect(back, Vector2(left, 170), Vector2(116, 36))
	S.rect(reset, Vector2(left + 126, 170), Vector2(106, 36))
	S.rect(index_toggle, Vector2(size.x - 148, 88), Vector2(124, 36))
	S.rect(index_panel, Vector2(size.x - 310, 142), Vector2(286, maxf(220, size.y - 206)))
	S.rect(guide, Vector2(left, size.y - 34), Vector2(size.x - left - 24, 22))
	guide.text = "SCROLL  Zoom     /     RIGHT DRAG  Orbit     /     MIDDLE DRAG  Pan" if size.x > 1050 else "Scroll: zoom   |   Drag: orbit / pan"
	index_panel.visible = not _collapsed

func _rebuild() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for selectable in host.preview.get("_selectables"):
		if _filter == "routes": continue
		var kind: String = selectable.selection_kind
		if _filter == "planet" and kind != "planet": continue
		if _filter == "ships" and kind not in ["ship", "fleet", "unit", "creature"]: continue
		if not search.text.is_empty() and not selectable.title.to_lower().contains(search.text.to_lower()): continue
		var selection_id: String = selectable.selection_id
		var button := S.button(rows, selectable.title + "\n" + kind.capitalize(), func(): _select(selection_id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 58
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if selection_id == host.preview.get_selected_selection_id():
			button.add_theme_stylebox_override("normal", S.button_box(Color("2b3037"), S.ACCENT, 6))
	if _filter in ["all", "routes"]:
		var field: GravityFieldMap = host.preview.get("_gravity_field")
		if field != null:
			for exit_record in field.exit_records:
				var target_name := str(exit_record["name"])
				if not search.text.is_empty() and not target_name.to_lower().contains(search.text.to_lower()): continue
				var point := field.to_global(field.exit_position(exit_record) + Vector3(0, float(exit_record["depth"]) * 0.5, 0))
				var button := S.button(rows, "To " + target_name + "\nHyperlane exit  >", func(): _focus_exit(point))
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				button.add_theme_color_override("font_color", Color("9fe9ff"))
				button.tooltip_text = "Focus the outbound connection toward " + target_name
	if rows.get_child_count() == 0:
		S.label(rows, "No matching objects", 13, S.MUTED)

func _select(selection_id: String) -> void:
	host.preview.call("_select_selectable_by_id", selection_id)

func _recenter() -> void:
	host.preview.call("_set_camera_distance", maxf(70, float(host.preview.get("_static_outer_radius")) + 24))

func _toggle_objects() -> void:
	if host.get("_body_details_panel").visible:
		host.preview.clear_selection()
		_collapsed = false
	else:
		_collapsed = not _collapsed
	_layout()

func _focus_exit(point: Vector3) -> void:
	var rig = host.preview.camera_rig
	rig.configure_view(Vector3(point.x, 0, point.z), maxf(45, float(host.preview.get("_static_outer_radius")) * 0.65), rig.get("_tilt_degrees"), rig.get("_yaw_degrees"))

func _update_exit_tags() -> void:
	var field: GravityFieldMap = host.preview.get("_gravity_field")
	if field == null:
		for tag in exit_tags: tag.hide()
		return
	if _exit_tag_field_id != field.get_instance_id():
		_exit_tag_field_id = field.get_instance_id()
		for tag in exit_tags:
			remove_child(tag)
			tag.queue_free()
		exit_tags.clear()
		for record in field.exit_records:
			var point := field.to_global(field.exit_position(record) + Vector3(0, float(record["depth"]) * 0.5, 0))
			var tag := S.button(self, "To " + str(record["name"]) + "  >", func(): _focus_exit(point))
			tag.custom_minimum_size = Vector2(148, 30)
			tag.add_theme_font_size_override("font_size", 11)
			tag.add_theme_color_override("font_color", Color("9fe9ff"))
			tag.add_theme_stylebox_override("normal", S.button_box(S.INK, Color("476a7b"), 4))
			tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			tag.tooltip_text = "Focus hyperlane toward " + str(record["name"])
			exit_tags.append(tag)
	var occupied: Array[Rect2] = []
	for index in range(exit_tags.size()):
		var record: Dictionary = field.exit_records[index]
		var point := field.to_global(field.exit_position(record))
		var projected: Vector2 = host.call("_preview_to_view_position", host.preview.camera.unproject_position(point))
		var safe := Rect2(Vector2(128, 224), Vector2(maxf(180, size.x - 478), maxf(90, size.y - 280)))
		var tag := exit_tags[index]
		tag.visible = true
		if host.preview.camera.is_position_behind(point):
			projected = safe.get_center() - (projected - safe.get_center())
		var position := Vector2(clampf(projected.x - 74, safe.position.x, safe.end.x - 148), clampf(projected.y, safe.position.y, safe.end.y - 34))
		for rect in occupied:
			if rect.intersects(Rect2(position, Vector2(148, 34))): position.y = maxf(safe.position.y, rect.position.y - 38)
		S.rect(tag, position, Vector2(148, 30))
		occupied.append(Rect2(position, Vector2(148, 34)))
