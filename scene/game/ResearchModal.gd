class_name ResearchModal
extends Control

## Research overview: one column per domain with active projects, progress,
## and the current deterministic draft. Players pick options here; momentum
## and inspirations are summarized in the footer.

signal close_requested

const PANEL_MINIMUM_SIZE := Vector2(1180, 680)
const COLOR_PANEL := ObservatoryStyle.SURFACE
const COLOR_PANEL_BORDER := Color(0.44, 0.64, 0.74, 0.56)
const COLOR_TEXT := Color(0.96, 0.98, 1.0, 0.96)
const COLOR_MUTED := Color(0.76, 0.84, 0.9, 0.78)
const COLOR_ACCENT := ObservatoryStyle.ACCENT
const COLOR_RARE := Color(0.95, 0.81, 0.38, 1.0)
const COLOR_INSPIRED := Color(0.62, 0.9, 1.0, 1.0)
const COLOR_PROGRESS := Color(0.45, 0.78, 0.58, 1.0)

var _empire_id: String = ""
var _panel: PanelContainer = null
var _stockpile_label: Label = null
var _columns_box: HBoxContainer = null
var _footer_label: Label = null
var _status_label: Label = null


func _ready() -> void:
	z_index = 1000
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_overlay_rect()
	if not get_viewport().size_changed.is_connected(_sync_overlay_rect):
		get_viewport().size_changed.connect(_sync_overlay_rect)
	_build_layout()
	_connect_runtime_signals()
	hide()


func _exit_tree() -> void:
	if get_viewport() != null and get_viewport().size_changed.is_connected(_sync_overlay_rect):
		get_viewport().size_changed.disconnect(_sync_overlay_rect)


func open(empire_id: String) -> void:
	if not is_node_ready():
		await ready
	_empire_id = empire_id.strip_edges()
	_status_label.text = ""
	_refresh_content()
	visible = true
	move_to_front()
	_sync_overlay_rect()


func close() -> void:
	visible = false
	_empire_id = ""
	close_requested.emit()


func _sync_overlay_rect() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func _connect_runtime_signals() -> void:
	if ResearchManager == null:
		return
	ResearchManager.research_state_changed.connect(_on_research_state_changed)
	ResearchManager.project_progressed.connect(_on_project_progressed)
	if EconomyManager != null:
		EconomyManager.empire_stockpile_changed.connect(_on_stockpile_changed)


func _on_research_state_changed(empire_id: String) -> void:
	if visible and empire_id == _empire_id:
		_refresh_content()


func _on_project_progressed(empire_id: String, _domain_id: String, _tech_id: String, _invested: int, _total: int) -> void:
	if visible and empire_id == _empire_id:
		_refresh_content()


func _on_stockpile_changed(empire_id: String, _revision: int) -> void:
	if visible and empire_id == _empire_id:
		_update_stockpile_label()


# --- Layout ---

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
	_panel.name = "ResearchCard"
	_panel.custom_minimum_size = PANEL_MINIMUM_SIZE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL
	panel_style.border_color = COLOR_PANEL_BORDER
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)

	var title := Label.new()
	title.text = "Forschung"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(title)

	_stockpile_label = Label.new()
	_stockpile_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stockpile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stockpile_label.add_theme_font_size_override("font_size", 14)
	_stockpile_label.add_theme_color_override("font_color", COLOR_MUTED)
	header.add_child(_stockpile_label)

	var close_button := Button.new()
	close_button.name = "CloseResearchButton"
	close_button.text = "Schliessen"
	close_button.custom_minimum_size = Vector2(110.0, 30.0)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	root.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_columns_box = HBoxContainer.new()
	_columns_box.name = "DomainColumns"
	_columns_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_columns_box)

	root.add_child(HSeparator.new())

	_footer_label = Label.new()
	_footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer_label.add_theme_font_size_override("font_size", 12)
	_footer_label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(_footer_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", COLOR_ACCENT)
	root.add_child(_status_label)


# --- Content ---

func _refresh_content() -> void:
	if _columns_box == null or _empire_id.is_empty() or ResearchManager == null:
		return
	for child in _columns_box.get_children():
		child.queue_free()

	for overview in ResearchManager.get_domains_overview(_empire_id):
		_columns_box.add_child(_build_domain_column(overview))
	_update_stockpile_label()
	_update_footer()


func _update_stockpile_label() -> void:
	if _stockpile_label == null or _empire_id.is_empty():
		return
	if EconomyManager == null or not EconomyManager.is_bootstrapped():
		_stockpile_label.text = ""
		return
	var stockpile := EconomyManager.get_amount(_empire_id, ResearchManager.RESEARCH_RESOURCE_ID)
	var monthly_net := EconomyManager.get_projected_monthly_net(_empire_id, ResearchManager.RESEARCH_RESOURCE_ID)
	_stockpile_label.text = "Forschungsdaten: %s   (%s/Monat)" % [
		_format_units(stockpile),
		_format_units_signed(monthly_net),
	]


func _update_footer() -> void:
	if _footer_label == null:
		return
	var parts: Array[String] = []

	var inspiration_parts: Array[String] = []
	for inspiration in ResearchManager.get_inspirations(_empire_id):
		var tag_names: Array[String] = []
		for tag_variant in inspiration.get("tags", []):
			tag_names.append(str(tag_variant))
		inspiration_parts.append("%s (-%d%%)" % [", ".join(tag_names), int(inspiration.get("discount_bp", 0)) / 100])
	if not inspiration_parts.is_empty():
		parts.append("Inspirationen: %s" % " | ".join(inspiration_parts))

	var momentum_map: Dictionary = ResearchManager.get_momentum_map(_empire_id)
	if not momentum_map.is_empty():
		var tags: Array = momentum_map.keys()
		tags.sort_custom(func(a: Variant, b: Variant) -> bool:
			var level_a := int(momentum_map.get(a, 0))
			var level_b := int(momentum_map.get(b, 0))
			if level_a == level_b:
				return str(a) < str(b)
			return level_a > level_b
		)
		var momentum_parts: Array[String] = []
		for tag_index in range(mini(tags.size(), 6)):
			momentum_parts.append("%s x%d" % [str(tags[tag_index]), int(momentum_map.get(tags[tag_index], 0))])
		parts.append("Momentum: %s" % ", ".join(momentum_parts))

	if parts.is_empty():
		_footer_label.text = "Abgeschlossene Forschung erzeugt Momentum auf ihren Tags: verwandte Techs werden haeufiger angeboten und guenstiger. Anomalien koennen Inspirationen mit Rabatten gewaehren."
	else:
		_footer_label.text = "\n".join(parts)


func _build_domain_column(overview: Dictionary) -> Control:
	var domain_color: Color = overview.get("color", Color(0.6, 0.7, 0.8, 1.0))
	var column := PanelContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column_style := StyleBoxFlat.new()
	column_style.bg_color = Color(0.04, 0.055, 0.07, 0.85)
	column_style.border_color = Color(domain_color.r, domain_color.g, domain_color.b, 0.45)
	column_style.set_border_width_all(1)
	column_style.set_corner_radius_all(3)
	column_style.content_margin_left = 10
	column_style.content_margin_top = 8
	column_style.content_margin_right = 10
	column_style.content_margin_bottom = 8
	column.add_theme_stylebox_override("panel", column_style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	column.add_child(box)

	var header := Label.new()
	header.text = str(overview.get("display_name", overview.get("domain_id", "")))
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", domain_color)
	box.add_child(header)

	var active_projects: Array = overview.get("active_projects", [])
	var slots := int(overview.get("slots", 1))
	var tier_label := Label.new()
	var next_requirement := int(overview.get("next_tier_requirement", 0))
	tier_label.text = "Stufe %d · %d erforscht (naechste Stufe: %d) · Slots %d/%d" % [
		int(overview.get("unlocked_tier", 0)),
		int(overview.get("completed_count", 0)),
		next_requirement,
		active_projects.size(),
		slots,
	]
	tier_label.add_theme_font_size_override("font_size", 11)
	tier_label.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(tier_label)

	for project_variant in active_projects:
		if project_variant is Dictionary:
			box.add_child(_build_project_panel(project_variant))

	box.add_child(HSeparator.new())

	var options: Array = overview.get("options", [])
	if options.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Keine Projekte verfuegbar."
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", COLOR_MUTED)
		box.add_child(empty_label)
	else:
		var has_free_slot := active_projects.size() < slots
		for option_variant in options:
			if option_variant is Dictionary:
				box.add_child(_build_option_card(str(overview.get("domain_id", "")), option_variant, has_free_slot))
	return column


func _build_project_panel(project: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.085, 0.1, 0.9)
	style.border_color = Color(COLOR_PROGRESS.r, COLOR_PROGRESS.g, COLOR_PROGRESS.b, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	var invested := int(project.get("invested_milliunits", 0))
	var total := maxi(int(project.get("total_cost_milliunits", 1)), 1)
	var daily_cap := maxi(int(project.get("daily_cap_milliunits", 1)), 1)

	var name_label := Label.new()
	name_label.text = "In Arbeit: %s" % str(project.get("display_name", project.get("tech_id", "")))
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	box.add_child(name_label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(float(invested) / float(total), 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 10.0)
	box.add_child(bar)

	var remaining_days := int(ceili(float(total - invested) / float(daily_cap)))
	var detail_label := Label.new()
	detail_label.text = "%s / %s  ·  noch >= %d Tage" % [
		_format_units(invested),
		_format_units(total),
		maxi(remaining_days, 0),
	]
	detail_label.add_theme_font_size_override("font_size", 11)
	detail_label.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(detail_label)
	return panel


func _build_option_card(domain_id: String, option: Dictionary, has_free_slot: bool) -> Control:
	var is_rare := str(option.get("rarity", "")) == "rare"
	var is_inspired := bool(option.get("inspired", false))
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.09, 0.92)
	if is_inspired:
		style.border_color = Color(COLOR_INSPIRED.r, COLOR_INSPIRED.g, COLOR_INSPIRED.b, 0.7)
	elif is_rare:
		style.border_color = Color(COLOR_RARE.r, COLOR_RARE.g, COLOR_RARE.b, 0.65)
	else:
		style.border_color = Color(0.3, 0.45, 0.55, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)

	var title_parts: Array[String] = []
	title_parts.append(str(option.get("display_name", option.get("tech_id", ""))))
	if int(option.get("level", 1)) > 1:
		title_parts.append("Stufe %d" % int(option.get("level", 1)))
	if is_rare:
		title_parts.append("(selten)")
	if is_inspired:
		title_parts.append("(inspiriert)")
	var name_label := Label.new()
	name_label.text = " ".join(title_parts)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", COLOR_RARE if is_rare else (COLOR_INSPIRED if is_inspired else COLOR_TEXT))
	box.add_child(name_label)

	var description := str(option.get("description", ""))
	if not description.is_empty():
		var description_label := Label.new()
		description_label.text = description
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.add_theme_font_size_override("font_size", 11)
		description_label.add_theme_color_override("font_color", COLOR_MUTED)
		box.add_child(description_label)

	var base_cost := int(option.get("base_cost_milliunits", 0))
	var effective_cost := int(option.get("effective_cost_milliunits", base_cost))
	var discount_bp := int(option.get("discount_bp", 0))
	var cost_text := "Kosten: %s" % _format_units(effective_cost)
	if discount_bp > 0:
		cost_text += "  (statt %s, -%d%%)" % [_format_units(base_cost), discount_bp / 100]
	cost_text += "  ·  >= %d Tage" % int(option.get("min_days", 1))
	var cost_label := Label.new()
	cost_label.text = cost_text
	cost_label.add_theme_font_size_override("font_size", 11)
	cost_label.add_theme_color_override("font_color", COLOR_MUTED)
	box.add_child(cost_label)

	var tag_names: Array[String] = []
	for tag_variant in option.get("tags", []):
		tag_names.append(str(tag_variant))
	if not tag_names.is_empty():
		var tags_label := Label.new()
		tags_label.text = "Tags: %s" % ", ".join(tag_names)
		tags_label.add_theme_font_size_override("font_size", 10)
		tags_label.add_theme_color_override("font_color", Color(0.6, 0.72, 0.8, 0.7))
		box.add_child(tags_label)

	var pick_button := Button.new()
	pick_button.name = "PickButton_%s" % str(option.get("tech_id", ""))
	pick_button.text = "Erforschen"
	pick_button.custom_minimum_size = Vector2(0.0, 28.0)
	pick_button.disabled = not has_free_slot
	pick_button.tooltip_text = "" if has_free_slot else "Alle Slots dieser Disziplin sind belegt."
	pick_button.pressed.connect(_on_pick_pressed.bind(domain_id, str(option.get("tech_id", ""))))
	box.add_child(pick_button)
	return card


func _on_pick_pressed(domain_id: String, tech_id: String) -> void:
	if ResearchManager == null or _empire_id.is_empty():
		return
	if ResearchManager.start_project(_empire_id, domain_id, tech_id):
		_status_label.text = ""
	else:
		_status_label.text = "Projekt konnte nicht gestartet werden."
	_refresh_content()


static func _format_units(milliunits: int) -> String:
	var units := float(milliunits) / 1000.0
	if absf(units - roundf(units)) < 0.05:
		return "%d" % int(roundf(units))
	return "%.1f" % units


static func _format_units_signed(milliunits: int) -> String:
	var formatted := _format_units(absi(milliunits))
	if milliunits < 0:
		return "-%s" % formatted
	return "+%s" % formatted
