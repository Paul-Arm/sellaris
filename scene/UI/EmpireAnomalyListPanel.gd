extends Control
class_name EmpireAnomalyListPanel

signal anomaly_open_requested(entry: Dictionary)

const ROW_SCRIPT: Script = preload("res://scene/UI/EmpireListActionRow.gd")

var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _empty_label: Label = null
var _entries: Array[Dictionary] = []


func _ready() -> void:
	_build()
	_refresh()


func set_entries(entries: Array) -> void:
	_entries.clear()
	for entry_variant in entries:
		if entry_variant is not Dictionary:
			continue
		var entry: Dictionary = entry_variant
		_entries.append(entry.duplicate(true))
	_refresh()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.name = "PanelTitle"
	title.text = "Anomalien / Situationen"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 0.98))
	root.add_child(title)

	_empty_label = Label.new()
	_empty_label.name = "EmptyLabel"
	_empty_label.text = "Keine entdeckten Anomalien."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.add_theme_font_size_override("font_size", 13)
	_empty_label.add_theme_color_override("font_color", Color(0.72, 0.8, 0.86, 0.82))
	root.add_child(_empty_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 7)
	_scroll.add_child(_list)


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()

	_empty_label.visible = _entries.is_empty()
	_scroll.visible = not _entries.is_empty()
	if _entries.is_empty():
		return

	for entry in _entries:
		var row := ROW_SCRIPT.new() as Control
		row.name = "EmpireListActionRow"
		row.call("set_entry", entry)
		row.connect("action_requested", Callable(self, "_on_row_action_requested"))
		_list.add_child(row)


func _on_row_action_requested(entry: Dictionary) -> void:
	anomaly_open_requested.emit(entry)
