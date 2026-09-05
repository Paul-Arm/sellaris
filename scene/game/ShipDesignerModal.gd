class_name ShipDesignerModal
extends Control

## Ship designer (COMBAT_DESIGN.md Phase D): pick a hull, fill its equipment
## slots from the empire's unlocked components, preview compiled stats live,
## and save/manage per-empire designs through the SpaceManager design API.

signal close_requested

const PANEL_MINIMUM_SIZE := Vector2(1100, 640)
const COLOR_PANEL := ObservatoryStyle.SURFACE
const COLOR_PANEL_BORDER := Color(0.44, 0.64, 0.74, 0.56)
const COLOR_TEXT := Color(0.96, 0.98, 1.0, 0.96)
const COLOR_MUTED := Color(0.76, 0.84, 0.9, 0.78)
const COLOR_ACCENT := Color(0.86, 0.62, 0.5, 1.0)
const COLOR_ERROR := Color(1.0, 0.5, 0.42, 0.95)
const NEW_DESIGN_OPTION_ID := "__new_design__"
const EMPTY_COMPONENT_ID := ""

const SLOT_KIND_LABELS := {
	"weapon": "Waffe",
	"defense": "Verteidigung",
	"drive": "Antrieb",
	"utility": "Hilfssystem",
}

var _empire_id: String = ""
var _selected_class_id: String = ""
var _selected_design_id: String = ""
var _draft_assignments: Dictionary = {}
var _hull_class_ids: Array[String] = []
var _is_refreshing: bool = false

var _panel: PanelContainer = null
var _hull_list: ItemList = null
var _design_select: OptionButton = null
var _name_edit: LineEdit = null
var _slots_box: VBoxContainer = null
var _slot_controls: Dictionary = {}
var _stats_label: Label = null
var _errors_label: Label = null
var _status_label: Label = null
var _save_button: Button = null
var _default_button: Button = null
var _delete_button: Button = null


func _ready() -> void:
	z_index = 1000
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_overlay_rect()
	if not get_viewport().size_changed.is_connected(_sync_overlay_rect):
		get_viewport().size_changed.connect(_sync_overlay_rect)
	_build_layout()
	hide()


func _exit_tree() -> void:
	if get_viewport() != null and get_viewport().size_changed.is_connected(_sync_overlay_rect):
		get_viewport().size_changed.disconnect(_sync_overlay_rect)


func open(empire_id: String) -> void:
	if not is_node_ready():
		await ready
	_empire_id = empire_id.strip_edges()
	_status_label.text = ""
	_populate_hull_list()
	if _hull_class_ids.is_empty():
		_selected_class_id = ""
	else:
		_hull_list.select(0)
		_select_hull(_hull_class_ids[0])
	visible = true
	move_to_front()
	_sync_overlay_rect()


func close() -> void:
	visible = false
	_empire_id = ""
	_selected_class_id = ""
	_selected_design_id = ""
	_draft_assignments.clear()
	close_requested.emit()


func get_selected_class_id() -> String:
	return _selected_class_id


func get_selected_design_id() -> String:
	return _selected_design_id


func _sync_overlay_rect() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func _build_layout() -> void:
	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.76)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "ShipDesignerCard"
	_panel.custom_minimum_size = PANEL_MINIMUM_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)

	var title := Label.new()
	title.name = "DesignerTitle"
	title.text = "Schiffsdesigner"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := Button.new()
	close_button.name = "DesignerCloseButton"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(34.0, 30.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(0.0, 1.0)
	accent.color = COLOR_ACCENT
	root.add_child(accent)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	root.add_child(columns)

	# Left: hull list.
	var hull_box := VBoxContainer.new()
	hull_box.custom_minimum_size = Vector2(230.0, 0.0)
	hull_box.add_theme_constant_override("separation", 6)
	columns.add_child(hull_box)
	hull_box.add_child(_build_section_label("Huellen"))
	_hull_list = ItemList.new()
	_hull_list.name = "HullList"
	_hull_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hull_list.item_selected.connect(_on_hull_selected)
	hull_box.add_child(_hull_list)

	# Middle: design selection + slots.
	var middle_box := VBoxContainer.new()
	middle_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle_box.add_theme_constant_override("separation", 8)
	columns.add_child(middle_box)

	middle_box.add_child(_build_section_label("Design"))
	_design_select = OptionButton.new()
	_design_select.name = "DesignSelect"
	_design_select.item_selected.connect(_on_design_option_selected)
	middle_box.add_child(_design_select)

	_name_edit = LineEdit.new()
	_name_edit.name = "DesignNameEdit"
	_name_edit.placeholder_text = "Designname"
	middle_box.add_child(_name_edit)

	middle_box.add_child(_build_section_label("Slots"))
	var slots_scroll := ScrollContainer.new()
	slots_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slots_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle_box.add_child(slots_scroll)
	_slots_box = VBoxContainer.new()
	_slots_box.name = "SlotsBox"
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_box.add_theme_constant_override("separation", 6)
	slots_scroll.add_child(_slots_box)

	# Right: stats preview + actions.
	var right_box := VBoxContainer.new()
	right_box.custom_minimum_size = Vector2(330.0, 0.0)
	right_box.add_theme_constant_override("separation", 8)
	columns.add_child(right_box)

	right_box.add_child(_build_section_label("Werte"))
	var stats_scroll := ScrollContainer.new()
	stats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_box.add_child(stats_scroll)
	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_label.add_theme_color_override("font_color", COLOR_TEXT)
	stats_scroll.add_child(_stats_label)

	_errors_label = Label.new()
	_errors_label.name = "ErrorsLabel"
	_errors_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_errors_label.add_theme_color_override("font_color", COLOR_ERROR)
	right_box.add_child(_errors_label)

	_save_button = Button.new()
	_save_button.name = "SaveDesignButton"
	_save_button.text = "Design speichern"
	_save_button.pressed.connect(_on_save_pressed)
	right_box.add_child(_save_button)

	_default_button = Button.new()
	_default_button.name = "SetDefaultButton"
	_default_button.text = "Als Standard setzen"
	_default_button.pressed.connect(_on_set_default_pressed)
	right_box.add_child(_default_button)

	_delete_button = Button.new()
	_delete_button.name = "DeleteDesignButton"
	_delete_button.text = "Design loeschen"
	_delete_button.pressed.connect(_on_delete_pressed)
	right_box.add_child(_delete_button)

	_status_label = Label.new()
	_status_label.name = "DesignerStatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", COLOR_MUTED)
	right_box.add_child(_status_label)


func _build_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	return label


# --- Hull / design selection ---

func _populate_hull_list() -> void:
	_hull_list.clear()
	_hull_class_ids.clear()
	var entries: Array[Dictionary] = []
	for unit_class in SpaceManager.get_all_unit_classes():
		if unit_class == null or unit_class.get_design_slots().is_empty():
			continue
		entries.append({"class_id": unit_class.class_id, "display_name": unit_class.display_name})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a.get("display_name", "")) == str(b.get("display_name", "")):
			return str(a.get("class_id", "")) < str(b.get("class_id", ""))
		return str(a.get("display_name", "")) < str(b.get("display_name", ""))
	)
	for entry in entries:
		_hull_class_ids.append(str(entry.get("class_id", "")))
		_hull_list.add_item(str(entry.get("display_name", "")))


func _on_hull_selected(index: int) -> void:
	if index < 0 or index >= _hull_class_ids.size():
		return
	_select_hull(_hull_class_ids[index])


func _select_hull(class_id: String) -> void:
	_selected_class_id = class_id
	var default_design_id := SpaceManager.get_default_ship_design_id(_empire_id, class_id)
	_populate_design_select(default_design_id)
	_load_design(default_design_id)


func _populate_design_select(selected_design_id: String) -> void:
	_design_select.clear()
	var selected_index := 0
	var option_index := 0
	for design_id in SpaceManager.get_ship_design_ids_for_empire(_empire_id):
		var design: Dictionary = SpaceManager.get_ship_design(design_id)
		if str(design.get("class_id", "")) != _selected_class_id:
			continue
		var label := str(design.get("display_name", design_id))
		if bool(design.get("is_default", false)):
			label += " (Standard)"
		_design_select.add_item(label)
		_design_select.set_item_metadata(option_index, design_id)
		if design_id == selected_design_id:
			selected_index = option_index
		option_index += 1
	_design_select.add_item("+ Neues Design")
	_design_select.set_item_metadata(option_index, NEW_DESIGN_OPTION_ID)
	if selected_design_id.is_empty():
		selected_index = option_index
	_design_select.select(selected_index)


func _on_design_option_selected(index: int) -> void:
	var design_id := str(_design_select.get_item_metadata(index))
	if design_id == NEW_DESIGN_OPTION_ID:
		_load_design("")
	else:
		_load_design(design_id)


func _load_design(design_id: String) -> void:
	_is_refreshing = true
	_selected_design_id = design_id
	_draft_assignments.clear()
	var unit_class := SpaceManager.get_unit_class(_selected_class_id)
	if design_id.is_empty():
		_name_edit.text = "%s Design" % (unit_class.display_name if unit_class != null else _selected_class_id)
	else:
		var design: Dictionary = SpaceManager.get_ship_design(design_id)
		_name_edit.text = str(design.get("display_name", design_id))
		var assignments_variant: Variant = design.get("slot_assignments", {})
		if assignments_variant is Dictionary:
			_draft_assignments = (assignments_variant as Dictionary).duplicate(true)
	_rebuild_slot_rows()
	_is_refreshing = false
	_refresh_preview()


# --- Slot rows ---

func _rebuild_slot_rows() -> void:
	for child in _slots_box.get_children():
		child.queue_free()
	_slot_controls.clear()
	var unit_class := SpaceManager.get_unit_class(_selected_class_id)
	if unit_class == null:
		return

	for slot in unit_class.get_design_slots():
		var slot_id := str(slot.get("slot_id", ""))
		var slot_kind := str(slot.get("slot_kind", ""))
		var required := bool(slot.get("required", false))

		var row := HBoxContainer.new()
		row.name = "SlotRow_%s" % slot_id
		row.add_theme_constant_override("separation", 8)

		var label := Label.new()
		label.custom_minimum_size = Vector2(170.0, 0.0)
		label.text = "%s%s" % [_format_slot_label(slot_id, slot_kind), " *" if required else ""]
		label.add_theme_color_override("font_color", COLOR_TEXT)
		label.tooltip_text = "Pflichtslot" if required else "Optionaler Slot"
		row.add_child(label)

		var select := OptionButton.new()
		select.name = "SlotSelect_%s" % slot_id
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.add_item("- leer -")
		select.set_item_metadata(0, EMPTY_COMPONENT_ID)
		var assigned := str(_draft_assignments.get(slot_id, ""))
		var selected_index := 0
		var option_index := 1
		for component_id in _get_eligible_component_ids(unit_class, slot):
			var component: Dictionary = SpaceManager.get_ship_component(component_id)
			select.add_item(str(component.get("display_name", component_id)))
			select.set_item_metadata(option_index, component_id)
			if component_id == assigned:
				selected_index = option_index
			option_index += 1
		select.select(selected_index)
		select.item_selected.connect(_on_slot_component_selected.bind(slot_id))
		row.add_child(select)

		_slots_box.add_child(row)
		_slot_controls[slot_id] = select


func _get_eligible_component_ids(unit_class: SpaceUnitClass, slot: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var slot_kind := str(slot.get("slot_kind", ""))
	var slot_size := str(slot.get("slot_size", "medium"))
	for component_id in SpaceManager.get_unlocked_ship_component_ids(_empire_id):
		var component: Dictionary = SpaceManager.get_ship_component(component_id)
		if component.is_empty():
			continue
		if str(component.get("slot_kind", "")) != slot_kind:
			continue
		if str(component.get("slot_size", "medium")) != slot_size:
			continue
		var allowed_kinds_variant: Variant = component.get("allowed_unit_kinds", [])
		if allowed_kinds_variant is Array and not (allowed_kinds_variant as Array).has(unit_class.unit_kind):
			continue
		if bool(component.get("requires_mobility", false)) and not unit_class.has_mobility():
			continue
		result.append(component_id)
	return result


func _on_slot_component_selected(option_index: int, slot_id: String) -> void:
	if _is_refreshing:
		return
	var select: OptionButton = _slot_controls.get(slot_id, null)
	if select == null:
		return
	var component_id := str(select.get_item_metadata(option_index))
	if component_id.is_empty():
		_draft_assignments.erase(slot_id)
	else:
		_draft_assignments[slot_id] = component_id
	_refresh_preview()


func _format_slot_label(slot_id: String, slot_kind: String) -> String:
	return "%s (%s)" % [slot_id.capitalize().replace("_", " "), str(SLOT_KIND_LABELS.get(slot_kind, slot_kind))]


# --- Preview & actions ---

func _refresh_preview() -> void:
	if _selected_class_id.is_empty():
		_stats_label.text = ""
		_errors_label.text = ""
		return
	var stats: Dictionary = SpaceManager.compile_ship_design_draft(_selected_class_id, _draft_assignments)
	_stats_label.text = _format_stats(stats)
	var errors: PackedStringArray = SpaceManager.validate_ship_design_draft(_empire_id, _selected_class_id, _draft_assignments)
	_errors_label.text = _format_errors(errors)
	_save_button.disabled = not errors.is_empty()

	var design: Dictionary = SpaceManager.get_ship_design(_selected_design_id) if not _selected_design_id.is_empty() else {}
	var is_existing := not design.is_empty()
	var is_default := bool(design.get("is_default", false))
	_default_button.disabled = not is_existing or is_default
	_delete_button.disabled = not is_existing or is_default


func _format_stats(stats: Dictionary) -> String:
	if stats.is_empty():
		return ""
	var lines: Array[String] = []
	lines.append("Huelle: %d" % int(stats.get("max_hull_points", 0)))
	if int(stats.get("max_shield_points", 0)) > 0:
		lines.append("Schilde: %d (+%d/Tag)" % [int(stats.get("max_shield_points", 0)), int(stats.get("shield_regen_per_day", 0))])
	if int(stats.get("armor_points", 0)) > 0:
		lines.append("Panzerung: %d" % int(stats.get("armor_points", 0)))
	if int(stats.get("evasion_bp", 0)) > 0:
		lines.append("Ausweichen: %d%%" % int(round(float(stats.get("evasion_bp", 0)) / 100.0)))
	if float(stats.get("cruise_speed", -1.0)) >= 0.0:
		lines.append("Geschwindigkeit: %.1f" % float(stats.get("cruise_speed", 0.0)))
	var weapons: Array = stats.get("weapons", [])
	if not weapons.is_empty():
		lines.append("Waffen: %d" % weapons.size())
		for weapon_variant in weapons:
			if weapon_variant is Dictionary:
				var weapon: Dictionary = weapon_variant
				lines.append("  - %s: %d Schaden / %d Tage, RW %.0f" % [
					str(weapon.get("component_id", "?")),
					int(weapon.get("damage", 0)),
					int(weapon.get("cooldown_days", 1)),
					float(weapon.get("range", 0.0)),
				])
	var abilities: Array = stats.get("abilities", [])
	for ability_variant in abilities:
		if ability_variant is Dictionary:
			lines.append("Faehigkeit: %s (%s)" % [
				str((ability_variant as Dictionary).get("effect_id", "?")),
				"manuell" if str((ability_variant as Dictionary).get("trigger", "")) == "manual" else "automatisch",
			])
	lines.append("")
	lines.append("Bauzeit: %d Tage" % int(stats.get("build_time_days", 0)))
	lines.append("Baukosten: %s" % _format_amounts(stats.get("build_costs", [])))
	lines.append("Unterhalt: %s/Monat" % _format_amounts(stats.get("monthly_upkeep", [])))
	return "\n".join(lines)


func _format_amounts(amounts_variant: Variant) -> String:
	if amounts_variant is not Array:
		return "-"
	var parts: Array[String] = []
	for amount_variant in amounts_variant:
		if amount_variant is not Dictionary:
			continue
		var amount: Dictionary = amount_variant
		parts.append("%.1f %s" % [float(int(amount.get("milliunits", 0))) / 1000.0, str(amount.get("resource_id", ""))])
	return ", ".join(parts) if not parts.is_empty() else "-"


func _format_errors(errors: PackedStringArray) -> String:
	if errors.is_empty():
		return ""
	var lines: Array[String] = []
	for error in errors:
		lines.append("- %s" % _translate_error(error))
	return "\n".join(lines)


func _translate_error(error: String) -> String:
	var parts := error.split(":")
	match parts[0]:
		"required_slot_empty":
			return "Pflichtslot ist leer: %s" % (parts[1] if parts.size() > 1 else "")
		"component_locked":
			return "Komponente nicht freigeschaltet: %s" % (parts[1] if parts.size() > 1 else "")
		"slot_mismatch":
			return "Komponente passt nicht in den Slot: %s" % (parts[parts.size() - 1] if parts.size() > 1 else "")
		"unit_kind_not_allowed":
			return "Komponente nicht fuer diesen Rumpftyp: %s" % (parts[1] if parts.size() > 1 else "")
		"requires_mobility":
			return "Komponente braucht einen mobilen Rumpf: %s" % (parts[1] if parts.size() > 1 else "")
		_:
			return error


func _on_save_pressed() -> void:
	if _selected_class_id.is_empty():
		return
	var design_name := _name_edit.text.strip_edges()
	if _selected_design_id.is_empty():
		var design_id := SpaceManager.create_ship_design(_empire_id, _selected_class_id, _draft_assignments, {
			"display_name": design_name,
		})
		if design_id.is_empty():
			_status_label.text = "Speichern fehlgeschlagen: %s" % ", ".join(SpaceManager.get_last_ship_design_errors())
			return
		_selected_design_id = design_id
		_status_label.text = "Design gespeichert."
	else:
		if not SpaceManager.update_ship_design(_selected_design_id, _draft_assignments):
			_status_label.text = "Aktualisierung fehlgeschlagen: %s" % ", ".join(SpaceManager.get_last_ship_design_errors())
			return
		SpaceManager.rename_ship_design(_selected_design_id, design_name)
		_status_label.text = "Design aktualisiert."
	_populate_design_select(_selected_design_id)
	_refresh_preview()


func _on_set_default_pressed() -> void:
	if _selected_design_id.is_empty():
		return
	if SpaceManager.set_default_ship_design(_selected_design_id):
		_status_label.text = "Standarddesign gesetzt."
	_populate_design_select(_selected_design_id)
	_refresh_preview()


func _on_delete_pressed() -> void:
	if _selected_design_id.is_empty():
		return
	if not SpaceManager.remove_ship_design(_selected_design_id):
		_status_label.text = "Loeschen nicht moeglich (Standarddesign oder in Verwendung)."
		return
	_status_label.text = "Design geloescht."
	_select_hull(_selected_class_id)
