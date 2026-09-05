extends Control
class_name SystemBodyDetailsPanel

signal close_requested
signal colonize_requested(system_id: String, body_context: Dictionary)
signal anomaly_research_requested(system_id: String, anomaly_id: String)

const PROCEDURAL_PLANET_VISUAL_SCRIPT: Script = preload("res://scene/StarSystem/procedural_planets/ProceduralPlanetVisual.gd")
const BODY_GLYPH_SCRIPT: Script = preload("res://scene/StarSystem/SystemBodyGlyph.gd")

const PANEL_MIN_SIZE := Vector2(660.0, 500.0)
const PREVIEW_SIZE := Vector2(240.0, 220.0)
const COLOR_PANEL := Color(0.028, 0.04, 0.052, 0.94)
const COLOR_PANEL_BORDER := Color(0.44, 0.64, 0.74, 0.56)
const COLOR_TEXT := Color(0.96, 0.98, 1.0, 0.96)
const COLOR_MUTED := Color(0.76, 0.84, 0.9, 0.78)
const COLOR_ACCENT := Color(0.86, 0.62, 0.5, 1.0)
const COLOR_CHIP := Color(0.08, 0.12, 0.15, 0.9)
const COLOR_CHIP_BORDER := Color(0.42, 0.62, 0.72, 0.42)

var _selection_data: Dictionary = {}
var _system_details: Dictionary = {}
var _body_context: Dictionary = {}
var _body_record: Dictionary = {}
var _action_state: Dictionary = {}

var _panel: PanelContainer = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _visual_slot: Control = null
var _facts_grid: GridContainer = null
var _resource_chips: HFlowContainer = null
var _anomaly_label: Label = null
var _anomaly_actions_box: VBoxContainer = null
var _notes_label: Label = null
var _colonize_button: Button = null
var _action_reason_label: Label = null


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_ui()


func open_details(selection_data: Dictionary, system_details: Dictionary, action_state: Dictionary = {}) -> void:
	_selection_data = selection_data.duplicate(true)
	_system_details = system_details.duplicate(true)
	_action_state = action_state.duplicate(true)
	_body_context = _selection_data.get("context", {}).duplicate(true) if _selection_data.get("context", {}) is Dictionary else {}
	_body_record = _resolve_body_record()

	_title_label.text = str(_selection_data.get("title", _body_context.get("body_name", "Selection")))
	_subtitle_label.text = _build_subtitle()
	_populate_visual()
	_populate_properties()
	_populate_resources()
	_populate_anomalies()
	_populate_actions()
	visible = true


func hide_details() -> void:
	visible = false
	_clear_visual()


func close() -> void:
	if not visible:
		return
	hide_details()
	close_requested.emit()


func is_showing() -> bool:
	return visible


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.name = "PanelCenter"
	center.anchors_preset = Control.PRESET_FULL_RECT
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "BodyDetailsCard"
	_panel.custom_minimum_size = PANEL_MIN_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _build_style(COLOR_PANEL, COLOR_PANEL_BORDER, 6, 1))
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.name = "ContentVBox"
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.name = "HeaderRow"
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.name = "TitleBox"
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 3)
	header.add_child(title_box)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", COLOR_TEXT)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.add_theme_color_override("font_color", COLOR_MUTED)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(_subtitle_label)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.tooltip_text = "Schliessen"
	close_button.custom_minimum_size = Vector2(32.0, 28.0)
	close_button.add_theme_stylebox_override("normal", _build_style(Color(0.05, 0.07, 0.085, 0.78), Color(0.3, 0.46, 0.54, 0.42), 4, 1))
	close_button.add_theme_stylebox_override("hover", _build_style(Color(0.09, 0.13, 0.16, 0.92), Color(0.55, 0.75, 0.84, 0.72), 4, 1))
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var accent_line := ColorRect.new()
	accent_line.name = "AccentLine"
	accent_line.custom_minimum_size = Vector2(0.0, 1.0)
	accent_line.color = COLOR_ACCENT
	root.add_child(accent_line)

	var content := HBoxContainer.new()
	content.name = "BodyRow"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	root.add_child(content)

	var visual_frame := PanelContainer.new()
	visual_frame.name = "VisualFrame"
	visual_frame.custom_minimum_size = PREVIEW_SIZE
	visual_frame.add_theme_stylebox_override("panel", _build_style(Color(0.015, 0.024, 0.032, 0.68), Color(0.32, 0.52, 0.62, 0.36), 5, 1))
	content.add_child(visual_frame)

	_visual_slot = Control.new()
	_visual_slot.name = "VisualSlot"
	_visual_slot.custom_minimum_size = PREVIEW_SIZE
	_visual_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_frame.add_child(_visual_slot)

	var right_scroll := ScrollContainer.new()
	right_scroll.name = "DetailsScroll"
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(right_scroll)

	var details_box := VBoxContainer.new()
	details_box.name = "DetailsVBox"
	details_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_box.add_theme_constant_override("separation", 9)
	right_scroll.add_child(details_box)

	_add_section_label(details_box, "Eigenschaften")
	_facts_grid = GridContainer.new()
	_facts_grid.name = "FactsGrid"
	_facts_grid.columns = 2
	_facts_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_facts_grid.add_theme_constant_override("h_separation", 12)
	_facts_grid.add_theme_constant_override("v_separation", 5)
	details_box.add_child(_facts_grid)

	_add_section_label(details_box, "Ressourcen")
	_resource_chips = HFlowContainer.new()
	_resource_chips.name = "ResourceChips"
	_resource_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource_chips.add_theme_constant_override("h_separation", 6)
	_resource_chips.add_theme_constant_override("v_separation", 6)
	details_box.add_child(_resource_chips)

	_add_section_label(details_box, "Anomalien")
	_anomaly_label = _build_body_label("AnomalyLabel", COLOR_MUTED)
	details_box.add_child(_anomaly_label)
	_anomaly_actions_box = VBoxContainer.new()
	_anomaly_actions_box.name = "AnomalyActions"
	_anomaly_actions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anomaly_actions_box.add_theme_constant_override("separation", 6)
	details_box.add_child(_anomaly_actions_box)

	_notes_label = _build_body_label("NotesLabel", COLOR_MUTED)
	details_box.add_child(_notes_label)

	var action_row := HBoxContainer.new()
	action_row.name = "ActionRow"
	action_row.add_theme_constant_override("separation", 8)
	root.add_child(action_row)

	_colonize_button = Button.new()
	_colonize_button.name = "ColonizeButton"
	_colonize_button.text = "Kolonisieren"
	_colonize_button.custom_minimum_size = Vector2(130.0, 32.0)
	_colonize_button.add_theme_stylebox_override("normal", _build_style(Color(0.1, 0.16, 0.18, 0.96), Color(0.72, 0.9, 1.0, 0.62), 5, 1))
	_colonize_button.add_theme_stylebox_override("hover", _build_style(Color(0.14, 0.22, 0.25, 1.0), Color(0.92, 0.98, 1.0, 0.88), 5, 1))
	_colonize_button.add_theme_stylebox_override("disabled", _build_style(Color(0.05, 0.06, 0.07, 0.72), Color(0.16, 0.22, 0.26, 0.44), 5, 1))
	_colonize_button.pressed.connect(_on_colonize_pressed)
	action_row.add_child(_colonize_button)

	_action_reason_label = _build_body_label("ActionReasonLabel", COLOR_MUTED)
	_action_reason_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_action_reason_label)


func _add_section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", COLOR_ACCENT)
	parent.add_child(label)


func _build_body_label(label_name: String, color: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _populate_visual() -> void:
	_clear_visual()
	var body_kind := _get_body_kind()
	if body_kind == "planet":
		_build_planet_preview()
		return

	var glyph = BODY_GLYPH_SCRIPT.new()
	glyph.name = "CompactBodyVisual"
	glyph.anchors_preset = Control.PRESET_FULL_RECT
	glyph.anchor_right = 1.0
	glyph.anchor_bottom = 1.0
	glyph.configure(body_kind, _body_record, _get_body_color())
	_visual_slot.add_child(glyph)


func _build_planet_preview() -> void:
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "PlanetPreview"
	viewport_container.anchors_preset = Control.PRESET_FULL_RECT
	viewport_container.anchor_right = 1.0
	viewport_container.anchor_bottom = 1.0
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual_slot.add_child(viewport_container)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 260)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)

	var root := Node3D.new()
	root.name = "PreviewWorld"
	viewport.add_child(root)

	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(0.0, 0.0, 7.6)
	camera.current = true
	root.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)

	var light := DirectionalLight3D.new()
	light.name = "PreviewLight"
	light.light_energy = 1.2
	light.rotation_degrees = Vector3(-24.0, 38.0, 0.0)
	root.add_child(light)

	var planet := PROCEDURAL_PLANET_VISUAL_SCRIPT.new() as ProceduralPlanetVisual
	planet.name = "ProceduralPlanetVisual"
	planet.configure(_system_details, _body_record, _find_orbital_index(str(_body_record.get("id", ""))))
	root.add_child(planet)


func _populate_properties() -> void:
	_clear_container(_facts_grid)
	var body_kind := _get_body_kind()
	_add_fact("Typ", _format_kind_label(body_kind))

	if body_kind == "planet":
		var world_info: Dictionary = ProceduralPlanetVisual.describe_planet(_system_details, _body_record, _find_orbital_index(str(_body_record.get("id", ""))))
		_add_fact("Klasse", str(world_info.get("label", "Planet")))
		_add_fact("Bewohnbarkeit", "%d%%" % _resolve_points(_body_record, "habitability_points", "habitability", 0))
		_add_fact("Kolonisierbar", "Ja" if _is_record_colonizable(_body_record) else "Nein")
	elif body_kind == "station" or body_kind == "ship" or body_kind == "unit":
		_add_fact("Klasse", str(_body_record.get("class_display_name", _body_record.get("class_id", "Station"))))
		_add_fact("Besitzer", str(_body_record.get("owner_name", _body_record.get("owner_empire_id", "Unbekannt"))))
		if float(_body_record.get("max_hull_points", 0.0)) > 0.0:
			_add_fact("Huelle", "%d%%" % int(round(float(_body_record.get("current_hull_points", 0.0)) / maxf(float(_body_record.get("max_hull_points", 1.0)), 1.0) * 100.0)))
	elif body_kind == "ruin":
		_add_fact("Status", _resolve_ruin_status())

	if _body_record.has("orbit_radius"):
		_add_fact("Orbit", "%.1f" % float(_body_record.get("orbit_radius", 0.0)))
	if _body_record.has("size") or _body_record.has("scale"):
		_add_fact("Groesse", "%.2fx" % float(_body_record.get("size", _body_record.get("scale", 1.0))))
	if _body_record.has("resource_richness") or _body_record.has("resource_richness_points"):
		_add_fact("Reichtum", "%d%%" % _resolve_points(_body_record, "resource_richness_points", "resource_richness", 50))


func _populate_resources() -> void:
	_clear_container(_resource_chips)
	if not _has_deposit_intel():
		_add_chip(_resource_chips, "Vorkommen unbekannt", COLOR_MUTED)
		return

	var added := false
	if _body_record.has("resource_richness") or _body_record.has("resource_richness_points"):
		_add_chip(_resource_chips, "Reichtum %d%%" % _resolve_points(_body_record, "resource_richness_points", "resource_richness", 50), COLOR_ACCENT)
		added = true

	var preview_map := _build_deposit_preview()
	var resource_ids: Array[String] = []
	for resource_id_variant in preview_map.keys():
		var resource_id := str(resource_id_variant)
		if resource_id.is_empty() or int(preview_map[resource_id_variant]) == 0:
			continue
		resource_ids.append(resource_id)
	resource_ids.sort()
	for resource_id in resource_ids:
		_add_chip(_resource_chips, "%s %s" % [_format_token_label(resource_id), _format_milliunits(int(preview_map[resource_id]))], Color(0.62, 0.9, 1.0, 1.0))
		added = true

	if not added:
		_add_chip(_resource_chips, "Keine bekannten Deposits", COLOR_MUTED)


func _populate_anomalies() -> void:
	_clear_container(_anomaly_actions_box)
	var anomaly_risk := _resolve_anomaly_risk()
	var anomaly_parts: Array[String] = ["Systemrisiko %d%%" % int(round(anomaly_risk * 100.0))]
	if _get_body_kind() == "ruin":
		anomaly_parts.append("Ruinenstatus: %s" % _resolve_ruin_status())

	var visible_anomalies := _get_visible_anomalies()
	if visible_anomalies.is_empty():
		anomaly_parts.append("Keine entdeckten Anomalien.")
	else:
		anomaly_parts.append("%d entdeckt" % visible_anomalies.size())
	_anomaly_label.text = "  ".join(anomaly_parts)

	for anomaly in visible_anomalies:
		_add_anomaly_row(anomaly)

	var notes := str(_body_record.get("notes", "")).strip_edges()
	var metadata_text := _format_metadata_preview(_body_record.get("metadata", {}), 4)
	if notes.is_empty() and metadata_text.is_empty():
		_notes_label.text = "Keine Zusatzdaten erfasst."
	elif notes.is_empty():
		_notes_label.text = metadata_text
	elif metadata_text.is_empty():
		_notes_label.text = notes
	else:
		_notes_label.text = "%s\n%s" % [notes, metadata_text]


func _get_visible_anomalies() -> Array[Dictionary]:
	var component: Dictionary = _body_record.get("anomaly_component", {}) if _body_record.get("anomaly_component", {}) is Dictionary else {}
	var result: Array[Dictionary] = []
	for anomaly_variant in component.get("anomalies", []):
		if anomaly_variant is not Dictionary:
			continue
		result.append((anomaly_variant as Dictionary).duplicate(true))
	return result


func _add_anomaly_row(anomaly: Dictionary) -> void:
	if _anomaly_actions_box == null:
		return
	var row := PanelContainer.new()
	row.name = "AnomalyRow"
	row.add_theme_stylebox_override("panel", _build_style(COLOR_CHIP, COLOR_CHIP_BORDER, 4, 1))
	_anomaly_actions_box.add_child(row)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	row.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var title := Label.new()
	title.name = "AnomalyTitle"
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.text = "%s  [%s]" % [
		str(anomaly.get("title", anomaly.get("definition_id", "Anomalie"))),
		_format_token_label(str(anomaly.get("status", "discovered"))),
	]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	var lore := str(anomaly.get("lore", "")).strip_edges()
	if not lore.is_empty():
		var lore_label := _build_body_label("AnomalyLore", COLOR_MUTED)
		lore_label.text = lore
		box.add_child(lore_label)

	var outcome_summary := str(anomaly.get("outcome_summary", "")).strip_edges()
	if not outcome_summary.is_empty():
		var outcome_label := _build_body_label("AnomalyOutcome", COLOR_ACCENT)
		outcome_label.text = outcome_summary
		box.add_child(outcome_label)

	if str(anomaly.get("status", "")) != "discovered":
		return
	var research_button := Button.new()
	research_button.name = "ResearchAnomalyButton"
	var research_days := int(anomaly.get("research_days", 0))
	research_button.text = "Anomalie erforschen" if research_days <= 0 else "Anomalie erforschen (%d T)" % research_days
	research_button.custom_minimum_size = Vector2(180.0, 30.0)
	research_button.add_theme_stylebox_override("normal", _build_style(Color(0.1, 0.16, 0.18, 0.96), Color(0.72, 0.9, 1.0, 0.62), 5, 1))
	research_button.add_theme_stylebox_override("hover", _build_style(Color(0.14, 0.22, 0.25, 1.0), Color(0.92, 0.98, 1.0, 0.88), 5, 1))
	research_button.pressed.connect(_on_research_anomaly_pressed.bind(str(anomaly.get("anomaly_id", ""))), CONNECT_DEFERRED)
	box.add_child(research_button)


func _populate_actions() -> void:
	var show_colonize := bool(_action_state.get("show_colonize", false))
	var can_colonize := bool(_action_state.get("can_colonize", false))
	var reason := str(_action_state.get("colonize_reason", "")).strip_edges()
	_colonize_button.visible = show_colonize
	_colonize_button.disabled = not can_colonize
	_action_reason_label.visible = show_colonize and not reason.is_empty()
	_action_reason_label.text = reason


func _on_colonize_pressed() -> void:
	var system_id := str(_body_context.get("system_id", _system_details.get("id", ""))).strip_edges()
	if system_id.is_empty():
		return
	colonize_requested.emit(system_id, _body_context.duplicate(true))


func _on_research_anomaly_pressed(anomaly_id: String) -> void:
	var system_id := str(_body_context.get("system_id", _system_details.get("id", ""))).strip_edges()
	if system_id.is_empty() or anomaly_id.strip_edges().is_empty():
		return
	anomaly_research_requested.emit(system_id, anomaly_id.strip_edges())


func _add_fact(key: String, value: String) -> void:
	if value.strip_edges().is_empty():
		return
	var key_label := Label.new()
	key_label.text = key
	key_label.add_theme_color_override("font_color", COLOR_MUTED)
	_facts_grid.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_color_override("font_color", COLOR_TEXT)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_facts_grid.add_child(value_label)


func _add_chip(parent: Control, text: String, accent: Color) -> void:
	var chip := Label.new()
	chip.text = text
	chip.add_theme_color_override("font_color", COLOR_TEXT)
	chip.add_theme_stylebox_override("normal", _build_style(COLOR_CHIP, Color(accent.r, accent.g, accent.b, COLOR_CHIP_BORDER.a), 4, 1))
	chip.add_theme_constant_override("margin_left", 8)
	chip.add_theme_constant_override("margin_right", 8)
	chip.add_theme_constant_override("margin_top", 3)
	chip.add_theme_constant_override("margin_bottom", 3)
	parent.add_child(chip)


func _build_style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ObservatoryStyle.SURFACE.lerp(background, 0.22)
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_right = 8
	style.content_margin_bottom = 4
	return style


func _clear_visual() -> void:
	if _visual_slot == null:
		return
	_clear_container(_visual_slot)


func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _resolve_body_record() -> Dictionary:
	var context_record: Variant = _body_context.get("body_record", {})
	if context_record is Dictionary and not (context_record as Dictionary).is_empty():
		return (context_record as Dictionary).duplicate(true)
	var body_id := str(_body_context.get("body_id", _body_context.get("host_id", ""))).strip_edges()
	var body_kind := _get_body_kind()
	for star_variant in _system_details.get("stars", []):
		if star_variant is not Dictionary:
			continue
		var star: Dictionary = star_variant
		if str(star.get("id", star.get("name", ""))) == body_id or (body_kind == "star" and body_id.is_empty()):
			return star.duplicate(true)
	for orbital_variant in _system_details.get("orbitals", []):
		if orbital_variant is not Dictionary:
			continue
		var orbital: Dictionary = orbital_variant
		if str(orbital.get("id", orbital.get("name", ""))) == body_id:
			return orbital.duplicate(true)
	return {}


func _build_deposit_preview() -> Dictionary:
	var body_kind := _get_body_kind()
	if not body_kind in ["star", "planet", "asteroid_belt", "structure", "ruin"]:
		return {}
	if not _has_deposit_intel():
		return {}
	if _body_record.is_empty() or EconomyManager == null:
		return {}
	var system_id := str(_body_context.get("system_id", _system_details.get("id", ""))).strip_edges()
	if system_id.is_empty():
		return {}
	var galaxy_seed := int(_system_details.get("generated_seed", _system_details.get("seed", 0)))
	if EconomyManager.has_method("preview_body_deposit_income"):
		return EconomyManager.preview_body_deposit_income(galaxy_seed, system_id, _body_record)
	if EconomyManager.has_method("preview_orbital_deposit_income"):
		return EconomyManager.preview_orbital_deposit_income(galaxy_seed, system_id, _body_record)
	return {}


func _has_deposit_intel() -> bool:
	if _system_details.has("has_full_intel"):
		return bool(_system_details.get("has_full_intel", false))
	return true


func _build_subtitle() -> String:
	var subtitle := str(_selection_data.get("subtitle", "")).strip_edges()
	var system_name := str(_system_details.get("name", "")).strip_edges()
	if subtitle.is_empty():
		subtitle = _format_kind_label(_get_body_kind())
	if system_name.is_empty():
		return subtitle
	return "%s / %s" % [subtitle, system_name]


func _get_body_kind() -> String:
	var body_kind := str(_body_context.get("body_type", "")).strip_edges()
	if body_kind.is_empty():
		body_kind = str(_selection_data.get("selection_kind", "")).strip_edges()
	if body_kind.is_empty():
		body_kind = str(_body_record.get("type", "unknown")).strip_edges()
	return body_kind


func _get_body_color() -> Color:
	var color_variant: Variant = _body_record.get("color", Color(0.62, 0.9, 1.0, 1.0))
	if color_variant is Color:
		return color_variant
	match _get_body_kind():
		"ruin":
			return Color(0.72, 0.74, 0.8, 1.0)
		"asteroid_belt":
			return Color(0.64, 0.6, 0.54, 1.0)
		"station", "structure":
			return Color(0.52, 0.82, 1.0, 1.0)
		_:
			return Color(0.62, 0.9, 1.0, 1.0)


func _find_orbital_index(body_id: String) -> int:
	for orbital_index in range(_system_details.get("orbitals", []).size()):
		var orbital_variant: Variant = _system_details.get("orbitals", [])[orbital_index]
		if orbital_variant is not Dictionary:
			continue
		var orbital: Dictionary = orbital_variant
		if str(orbital.get("id", "")) == body_id:
			return orbital_index
	return -1


func _resolve_anomaly_risk() -> float:
	if _body_record.has("anomaly_risk"):
		return clampf(float(_body_record.get("anomaly_risk", 0.0)), 0.0, 1.0)
	var summary: Dictionary = _system_details.get("system_summary", {}) if _system_details.get("system_summary", {}) is Dictionary else {}
	return clampf(float(_system_details.get("anomaly_risk", summary.get("anomaly_risk", 0.0))), 0.0, 1.0)


func _resolve_ruin_status() -> String:
	var metadata: Dictionary = _body_record.get("metadata", {}) if _body_record.get("metadata", {}) is Dictionary else {}
	var status := str(_body_record.get("ruin_status", metadata.get("status", metadata.get("ruin_status", "")))).strip_edges()
	return _format_token_label(status) if not status.is_empty() else "Unbekannt"


func _format_metadata_preview(metadata_variant: Variant, limit: int) -> String:
	if metadata_variant is not Dictionary:
		return ""
	var metadata: Dictionary = metadata_variant
	var lines: Array[String] = []
	var keys: Array[String] = []
	for key_variant in metadata.keys():
		var key := str(key_variant)
		if key in ["planet_visual", "buildable_component"]:
			continue
		keys.append(key)
	keys.sort()
	for key in keys:
		if lines.size() >= limit:
			break
		var value: Variant = metadata.get(key)
		if value is Dictionary or value is Array:
			continue
		lines.append("%s: %s" % [_format_token_label(key), str(value)])
	return "\n".join(lines)


func _format_kind_label(kind: String) -> String:
	match kind:
		"planet":
			return "Planet"
		"star":
			return "Stern"
		"asteroid_belt":
			return "Asteroidenguertel"
		"structure":
			return "Struktur"
		"ruin":
			return "Ruine"
		"station":
			return "Station"
		"fleet":
			return "Flotte"
		"ship", "unit":
			return "Schiff"
		"creature":
			return "Kreatur"
		_:
			return _format_token_label(kind)


func _format_token_label(value: String) -> String:
	var trimmed := value.strip_edges()
	if trimmed.is_empty():
		return "Unbekannt"
	return trimmed.replace("_", " ").capitalize()


func _format_milliunits(value: int) -> String:
	var sign := "+" if value >= 0 else "-"
	var absolute_value := absi(value)
	var whole := int(absolute_value / 1000)
	var fraction := absolute_value % 1000
	if fraction == 0:
		return "%s%d" % [sign, whole]
	return "%s%d.%03d" % [sign, whole, fraction]


func _resolve_points(record: Dictionary, points_key: String, fraction_key: String, default_points: int) -> int:
	if record.has(points_key):
		return clampi(int(record.get(points_key, default_points)), 0, 100)
	if record.has(fraction_key):
		return clampi(int(round(clampf(float(record.get(fraction_key, float(default_points) / 100.0)), 0.0, 1.0) * 100.0)), 0, 100)
	return default_points


func _is_record_colonizable(record: Dictionary) -> bool:
	return str(record.get("type", "")) == "planet" and (bool(record.get("is_colonizable", false)) or _resolve_points(record, "habitability_points", "habitability", 0) >= 45)
