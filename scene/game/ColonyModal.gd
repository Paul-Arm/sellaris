class_name ColonyModal
extends Control

signal close_requested
signal assign_requested(colony_id: String, pop_unit_id: String, job_id: String)
signal unassign_requested(colony_id: String, pop_unit_id: String)
signal job_cap_changed(colony_id: String, job_id: String, cap: int)
signal building_place_requested(colony_id: String, slot_id: String, building_id: String)

const BUILDING_PALETTE_CARD_SCRIPT := preload("res://scene/game/BuildingPaletteCard.gd")
const BUILDING_HEX_SLOT_SCRIPT := preload("res://scene/game/BuildingHexSlot.gd")
const PROCEDURAL_PLANET_VISUAL_SCRIPT := preload("res://scene/StarSystem/procedural_planets/ProceduralPlanetVisual.gd")
const PANEL_MINIMUM_SIZE := Vector2(1320, 860)
const HEX_SLOT_SIZE := Vector2(100, 88)
const HEX_GRID_FALLBACK_SIZE := Vector2(1190, 535)
const DISTRICT_PLACEHOLDERS := [
	{"name": "City District", "summary": "Housing and local services", "status": "Coming later"},
	{"name": "Generator District", "summary": "Energy jobs and infrastructure", "status": "Coming later"},
	{"name": "Mining District", "summary": "Matter extraction jobs", "status": "Coming later"},
	{"name": "Agriculture District", "summary": "Food production jobs", "status": "Coming later"},
]

var _colony_id: String = ""
var _is_refreshing: bool = false
var _current_job_caps: Dictionary = {}
var _panel: PanelContainer = null
var _title_label: Label = null
var _summary_label: Label = null
var _overview_stats_label: Label = null
var _buildings_container: VBoxContainer = null
var _districts_container: VBoxContainer = null
var _building_grid_layer: Control = null
var _building_palette_container: HBoxContainer = null
var _building_status_label: Label = null
var _planet_viewport: SubViewport = null
var _planet_visual: Node3D = null
var _planet_visual_key: String = ""
var _management_summary_label: Label = null
var _species_container: VBoxContainer = null
var _jobs_container: VBoxContainer = null


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


func open_details(details: Dictionary) -> void:
	if not is_node_ready():
		await ready
	_colony_id = str(details.get("id", ""))
	_populate(details)
	visible = true
	move_to_front()
	_sync_overlay_rect()


func close() -> void:
	visible = false
	_colony_id = ""
	close_requested.emit()


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
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.76)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	var safe_area := MarginContainer.new()
	safe_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	safe_area.add_theme_constant_override("margin_left", 22)
	safe_area.add_theme_constant_override("margin_top", 22)
	safe_area.add_theme_constant_override("margin_right", 22)
	safe_area.add_theme_constant_override("margin_bottom", 22)
	safe_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(safe_area)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_area.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_MINIMUM_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.04, 0.05, 0.97), Color(0.42, 0.68, 0.82, 0.38), 6, 2))
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	root_vbox.add_child(header_row)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header_row.add_child(title_box)

	_title_label = Label.new()
	_title_label.text = "Planet"
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.clip_text = true
	title_box.add_child(_title_label)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.modulate = Color(0.82, 0.88, 0.92, 0.95)
	title_box.add_child(_summary_label)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(92, 38)
	close_button.add_theme_stylebox_override("normal", _make_button_style(Color(0.08, 0.1, 0.12, 0.95), Color(0.32, 0.48, 0.58, 0.36)))
	close_button.add_theme_stylebox_override("hover", _make_button_style(Color(0.12, 0.16, 0.19, 0.98), Color(0.62, 0.86, 1.0, 0.62)))
	close_button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.04, 0.08, 0.11, 1.0), Color(0.78, 0.96, 1.0, 0.8)))
	close_button.pressed.connect(close)
	header_row.add_child(close_button)

	_overview_stats_label = Label.new()
	_overview_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overview_stats_label.modulate = Color(0.93, 0.95, 0.98, 1.0)
	root_vbox.add_child(_overview_stats_label)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_tab_style(tabs)
	root_vbox.add_child(tabs)

	var infrastructure_tab := _build_infrastructure_tab()
	infrastructure_tab.name = "Buildings / Districts"
	tabs.add_child(infrastructure_tab)

	var management_tab := _build_management_tab()
	management_tab.name = "Management"
	tabs.add_child(management_tab)


func _make_panel_style(fill_color: Color, border_color: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0.0, 6.0)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _make_button_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := _make_panel_style(fill_color, border_color, 3, 1)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0.0, 1.0)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _make_tab_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := _make_panel_style(fill_color, border_color, 2, 1)
	style.shadow_size = 0
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _apply_tab_style(tabs: TabContainer) -> void:
	tabs.add_theme_stylebox_override("panel", _make_panel_style(Color(0.012, 0.018, 0.024, 0.42), Color(0.14, 0.28, 0.36, 0.18), 3, 1))
	tabs.add_theme_stylebox_override("tab_selected", _make_tab_style(Color(0.11, 0.16, 0.19, 0.98), Color(0.62, 0.84, 0.94, 0.62)))
	tabs.add_theme_stylebox_override("tab_unselected", _make_tab_style(Color(0.035, 0.042, 0.052, 0.86), Color(0.18, 0.26, 0.32, 0.62)))
	tabs.add_theme_stylebox_override("tab_hovered", _make_tab_style(Color(0.075, 0.1, 0.12, 0.94), Color(0.45, 0.68, 0.8, 0.52)))
	tabs.add_theme_color_override("font_selected_color", Color(0.93, 0.98, 1.0, 1.0))
	tabs.add_theme_color_override("font_unselected_color", Color(0.68, 0.74, 0.78, 0.96))
	tabs.add_theme_font_size_override("font_size", 16)


func _build_infrastructure_tab() -> Control:
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)

	var stage := Control.new()
	stage.clip_contents = true
	stage.custom_minimum_size = Vector2(0, 552)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(stage)

	var stage_backdrop := ColorRect.new()
	stage_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_backdrop.color = Color(0.0, 0.0, 0.0, 1.0)
	stage_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(stage_backdrop)

	var viewport_container := _build_planet_viewport()
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.modulate = Color(1.0, 1.0, 1.0, 0.82)
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(viewport_container)

	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.0, 0.0, 0.0, 0.02)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(vignette)

	_building_grid_layer = Control.new()
	_building_grid_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_building_grid_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	stage.add_child(_building_grid_layer)

	var status_margin := MarginContainer.new()
	status_margin.anchor_left = 0.0
	status_margin.anchor_top = 1.0
	status_margin.anchor_right = 1.0
	status_margin.anchor_bottom = 1.0
	status_margin.offset_left = 16.0
	status_margin.offset_top = -42.0
	status_margin.offset_right = -16.0
	status_margin.offset_bottom = -10.0
	status_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(status_margin)

	_building_status_label = Label.new()
	_building_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_building_status_label.modulate = Color(1.0, 0.74, 0.56, 0.96)
	_building_status_label.visible = false
	status_margin.add_child(_building_status_label)

	var palette_panel := PanelContainer.new()
	palette_panel.custom_minimum_size = Vector2(0, 148)
	palette_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.025, 0.032, 0.04, 0.94), Color(0.28, 0.48, 0.58, 0.28), 4, 1))
	content.add_child(palette_panel)

	var palette_margin := MarginContainer.new()
	palette_margin.add_theme_constant_override("margin_left", 10)
	palette_margin.add_theme_constant_override("margin_top", 10)
	palette_margin.add_theme_constant_override("margin_right", 10)
	palette_margin.add_theme_constant_override("margin_bottom", 10)
	palette_panel.add_child(palette_margin)

	var palette_scroll := ScrollContainer.new()
	palette_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	palette_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	palette_margin.add_child(palette_scroll)

	_building_palette_container = HBoxContainer.new()
	_building_palette_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building_palette_container.add_theme_constant_override("separation", 10)
	palette_scroll.add_child(_building_palette_container)

	var districts_label := _make_muted_label("Districts: coming later")
	districts_label.modulate = Color(0.72, 0.76, 0.82, 0.6)
	content.add_child(districts_label)
	return content


func _build_planet_viewport() -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.stretch = true

	_planet_viewport = SubViewport.new()
	_planet_viewport.size = Vector2i(768, 768)
	_planet_viewport.transparent_bg = false
	_planet_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := World3D.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 1.0)
	world.environment = environment
	_planet_viewport.world_3d = world
	container.add_child(_planet_viewport)

	var root := Node3D.new()
	_planet_viewport.add_child(root)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 5.2)
	camera.fov = 38.0
	camera.current = true
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	root.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32.0, -38.0, 0.0)
	light.light_energy = 1.6
	root.add_child(light)

	_planet_visual = PROCEDURAL_PLANET_VISUAL_SCRIPT.new() as Node3D
	_planet_visual.scale = Vector3.ONE * 3.35
	root.add_child(_planet_visual)
	return container


func _build_management_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)

	_management_summary_label = Label.new()
	_management_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_management_summary_label)

	content.add_child(_make_section_label("Species"))
	_species_container = VBoxContainer.new()
	_species_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_species_container.add_theme_constant_override("separation", 6)
	content.add_child(_species_container)

	content.add_child(_make_section_label("Jobs"))
	_jobs_container = VBoxContainer.new()
	_jobs_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jobs_container.add_theme_constant_override("separation", 8)
	content.add_child(_jobs_container)
	return scroll


func _populate(details: Dictionary) -> void:
	_is_refreshing = true
	var owner_name := str(details.get("owner_name", details.get("empire_id", ""))).strip_edges()
	var system_name := str(details.get("system_name", "")).strip_edges()
	var planet_name := str(details.get("planet_name", details.get("planet_orbital_id", ""))).strip_edges()
	var planet_type := _format_token(str(details.get("planet_type", "planet")))
	var capital_text := " Capital" if bool(details.get("is_capital", false)) else ""

	_title_label.text = "%s%s" % [str(details.get("name", "Colony")), capital_text]
	_summary_label.text = "%s on %s%s  %s  Habitability %d%%" % [
		owner_name if not owner_name.is_empty() else str(details.get("empire_id", "")),
		planet_name,
		" in %s" % system_name if not system_name.is_empty() else "",
		planet_type,
		int(details.get("habitability_points", 0)),
	]
	_overview_stats_label.text = "Population %s  Assigned %d  Idle %d  Monthly Net %s" % [
		_format_population(int(details.get("total_population", 0))),
		int(details.get("assigned_pop_count", 0)),
		int(details.get("idle_pop_count", 0)),
		_format_resource_map(details.get("monthly_net", {}), true),
	]
	_management_summary_label.text = "Assigned workers %d  Idle workers %d  Income %s  Upkeep %s" % [
		int(details.get("assigned_pop_count", 0)),
		int(details.get("idle_pop_count", 0)),
		_format_resource_map(details.get("monthly_income", {}), false),
		_format_resource_map(details.get("monthly_expense", {}), false),
	]

	_populate_planet_background(details)
	_populate_building_grid(details.get("building_grid_slots", []))
	_populate_building_palette(details.get("building_catalog", []))
	_populate_building_status(str(details.get("last_build_error", "")))
	_populate_species(details.get("species_counts", []))
	_populate_jobs(details.get("jobs", []))
	_is_refreshing = false


func _populate_planet_background(details: Dictionary) -> void:
	if _planet_visual == null or not _planet_visual.has_method("configure"):
		return

	var planet_record: Dictionary = {}
	var planet_record_variant: Variant = details.get("planet_record", {})
	if planet_record_variant is Dictionary:
		planet_record = (planet_record_variant as Dictionary).duplicate(true)
	if planet_record.is_empty():
		planet_record = {
			"id": str(details.get("planet_orbital_id", "capital_world")),
			"name": str(details.get("planet_name", "Capital World")),
			"type": "planet",
			"planet_class_id": str(details.get("planet_type", "continental")),
		}

	if str(planet_record.get("id", "")).strip_edges().is_empty():
		planet_record["id"] = str(details.get("planet_orbital_id", "capital_world"))
	if str(planet_record.get("name", "")).strip_edges().is_empty():
		planet_record["name"] = str(details.get("planet_name", "Capital World"))
	if str(planet_record.get("type", "")).strip_edges().is_empty():
		planet_record["type"] = "planet"
	if not planet_record.has("size"):
		planet_record["size"] = 2.2
	if not planet_record.has("orbit_radius"):
		planet_record["orbit_radius"] = 4.0
	var metadata: Dictionary = planet_record.get("metadata", {}).duplicate(true) if planet_record.get("metadata", {}) is Dictionary else {}
	var planet_visual: Dictionary = metadata.get("planet_visual", {}).duplicate(true) if metadata.get("planet_visual", {}) is Dictionary else {}
	planet_visual["has_ring"] = false
	planet_visual["ring"] = false
	planet_visual["has_atmosphere"] = true
	planet_visual["pixels"] = float(planet_visual.get("pixels", 2600.0))
	planet_visual.erase("scene_variant")
	var kind := str(planet_visual.get("kind", "")).strip_edges()
	if kind == "gas_planet" or kind == "gas" or kind.is_empty():
		planet_visual["kind"] = "landmass"
	metadata["planet_visual"] = planet_visual
	planet_record["metadata"] = metadata

	var visual_key := "%s|%s|%s|%s" % [
		str(details.get("system_id", "")),
		str(planet_record.get("id", "")),
		str(planet_record.get("planet_class_id", "")),
		str(planet_record.get("metadata", {})).hash(),
	]
	if visual_key == _planet_visual_key:
		return
	_planet_visual_key = visual_key

	var system_id := str(details.get("system_id", "system"))
	var system_details := {
		"id": system_id,
		"name": str(details.get("system_name", system_id)),
		"seed": system_id.hash(),
		"star_profile": {"star_class": "G", "special_type": "none"},
		"orbitals": [planet_record],
	}
	_planet_visual.call("configure", system_details, planet_record, 0)


func _populate_building_grid(slots_variant: Variant) -> void:
	if _building_grid_layer == null:
		return
	_clear_node_children(_building_grid_layer)
	var slots: Array = slots_variant if slots_variant is Array else []
	var layer_size := _building_grid_layer.size
	if layer_size.x <= 1.0 or layer_size.y <= 1.0:
		layer_size = HEX_GRID_FALLBACK_SIZE

	var axial_radius := 49.0
	var center := layer_size * 0.5 + Vector2(0.0, 0.0)
	for slot_variant in slots:
		if slot_variant is not Dictionary:
			continue
		var slot_data: Dictionary = slot_variant
		var q := int(slot_data.get("q", 0))
		var r := int(slot_data.get("r", 0))
		var slot_position := Vector2(
			axial_radius * sqrt(3.0) * (float(q) + float(r) * 0.5),
			axial_radius * 1.5 * float(r)
		)
		var slot_node = BUILDING_HEX_SLOT_SCRIPT.new()
		slot_node.size = HEX_SLOT_SIZE
		slot_node.position = center + slot_position - HEX_SLOT_SIZE * 0.5
		slot_node.configure(slot_data)
		slot_node.building_dropped.connect(_on_building_slot_dropped)
		_building_grid_layer.add_child(slot_node)


func _populate_building_palette(catalog_variant: Variant) -> void:
	if _building_palette_container == null:
		return
	_clear_container(_building_palette_container)
	var catalog: Array = catalog_variant if catalog_variant is Array else []
	if catalog.is_empty():
		_building_palette_container.add_child(_make_muted_label("No buildable buildings"))
		return
	for building_variant in catalog:
		if building_variant is not Dictionary:
			continue
		var building: Dictionary = building_variant
		_building_palette_container.add_child(_make_building_palette_card(building))


func _populate_building_status(message: String) -> void:
	if _building_status_label == null:
		return
	message = message.strip_edges()
	_building_status_label.text = message
	_building_status_label.visible = not message.is_empty()


func _make_building_palette_card(building: Dictionary) -> Control:
	var card = BUILDING_PALETTE_CARD_SCRIPT.new()
	card.custom_minimum_size = Vector2(260, 108)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	var name_label := Label.new()
	name_label.text = str(building.get("display_name", building.get("id", "Building")))
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.clip_text = true
	vbox.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = "Cost %s" % _format_amount_array(building.get("build_cost", []), false)
	cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost_label.modulate = Color(0.88, 0.91, 0.95, 0.95)
	vbox.add_child(cost_label)

	var jobs_label := Label.new()
	jobs_label.text = _format_job_slots(building.get("job_slots", {}))
	jobs_label.clip_text = true
	jobs_label.modulate = Color(0.8, 0.9, 1.0, 0.92)
	vbox.add_child(jobs_label)

	var status_label := Label.new()
	status_label.text = "Available" if bool(building.get("can_place", false)) else str(building.get("unavailable_reason", "Unavailable"))
	status_label.clip_text = true
	status_label.modulate = Color(0.72, 1.0, 0.78, 0.9) if bool(building.get("can_place", false)) else Color(1.0, 0.68, 0.55, 0.9)
	vbox.add_child(status_label)

	card.configure(building)
	return card


func _on_building_slot_dropped(slot_id: String, building_id: String) -> void:
	if _colony_id.is_empty() or slot_id.strip_edges().is_empty() or building_id.strip_edges().is_empty():
		return
	building_place_requested.emit(_colony_id, slot_id, building_id)


func _populate_buildings(buildings_variant: Variant) -> void:
	_clear_container(_buildings_container)
	var buildings: Array = buildings_variant if buildings_variant is Array else []
	if buildings.is_empty():
		_buildings_container.add_child(_make_muted_label("No buildings"))
		return
	for building_variant in buildings:
		if building_variant is not Dictionary:
			continue
		var building: Dictionary = building_variant
		_buildings_container.add_child(_make_info_row(
			str(building.get("display_name", building.get("id", "Building"))),
			str(building.get("description", "")),
			_format_job_slots(building.get("job_slots", {}))
		))


func _populate_districts() -> void:
	_clear_container(_districts_container)
	for district in DISTRICT_PLACEHOLDERS:
		var row := _make_info_row(
			str(district.get("name", "District")),
			str(district.get("summary", "")),
			str(district.get("status", ""))
		)
		row.modulate = Color(0.78, 0.82, 0.86, 0.72)
		_districts_container.add_child(row)


func _populate_species(species_counts_variant: Variant) -> void:
	_clear_container(_species_container)
	var species_counts: Array = species_counts_variant if species_counts_variant is Array else []
	if species_counts.is_empty():
		_species_container.add_child(_make_muted_label("No population"))
		return
	for species_variant in species_counts:
		if species_variant is not Dictionary:
			continue
		var species: Dictionary = species_variant
		var trait_ids: Array = species.get("trait_ids", [])
		var traits := "Traits: %s" % ", ".join(_stringify_array(trait_ids)) if not trait_ids.is_empty() else "No traits"
		_species_container.add_child(_make_info_row(
			str(species.get("species_name", "Species")),
			traits,
			_format_population(int(species.get("population", 0)))
		))


func _populate_jobs(jobs_variant: Variant) -> void:
	_clear_container(_jobs_container)
	_current_job_caps.clear()
	var jobs: Array = jobs_variant if jobs_variant is Array else []
	if jobs.is_empty():
		_jobs_container.add_child(_make_muted_label("No available jobs"))
		return

	for job_variant in jobs:
		if job_variant is not Dictionary:
			continue
		var job: Dictionary = job_variant
		var job_id := str(job.get("id", "")).strip_edges()
		var max_slots := int(job.get("max_slots", 0))
		var job_cap := clampi(int(job.get("job_cap", max_slots)), 0, max_slots)
		var used_slots := int(job.get("used_slots", 0))
		var fillable_slots := int(job.get("fillable_slots", mini(job_cap, max_slots)))
		_current_job_caps[job_id] = job_cap
		_jobs_container.add_child(_make_job_row(job, used_slots, job_cap, fillable_slots, max_slots))


func _make_job_row(job: Dictionary, used_slots: int, job_cap: int, _fillable_slots: int, max_slots: int) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.048, 0.058, 0.9), Color(0.22, 0.42, 0.52, 0.34), 4, 1))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	row.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	margin.add_child(hbox)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 3)
	hbox.add_child(text_box)

	var filled_percent := 0
	if max_slots > 0:
		filled_percent = int(round(float(used_slots) / float(max_slots) * 100.0))

	var title := Label.new()
	title.text = "%s  %d/%d filled" % [
		str(job.get("display_name", job.get("id", "Job"))),
		used_slots,
		max_slots,
	]
	title.add_theme_font_size_override("font_size", 16)
	title.clip_text = true
	text_box.add_child(title)

	var description := Label.new()
	description.text = str(job.get("description", ""))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.modulate = Color(0.82, 0.86, 0.9, 0.92)
	text_box.add_child(description)

	var output := Label.new()
	output.text = "Output %s  Upkeep %s  Priority %d" % [
		_format_amount_array(job.get("income", []), false),
		_format_amount_array(job.get("expense", []), false),
		int(job.get("priority", 0)),
	]
	output.modulate = Color(0.92, 0.94, 0.96, 0.95)
	text_box.add_child(output)

	var control_box := VBoxContainer.new()
	control_box.custom_minimum_size = Vector2(260, 0)
	control_box.add_theme_constant_override("separation", 5)
	hbox.add_child(control_box)

	var cap_label := Label.new()
	cap_label.text = "Worker limit %d / %d" % [job_cap, max_slots]
	cap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	control_box.add_child(cap_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = float(max_slots)
	slider.step = 1.0
	slider.value = float(job_cap)
	slider.tick_count = mini(max_slots + 1, 11)
	slider.ticks_on_borders = true
	slider.editable = max_slots > 0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(240, 26)
	slider.value_changed.connect(_on_job_cap_slider_value_changed.bind(str(job.get("id", ""))))
	control_box.add_child(slider)

	var fill_label := Label.new()
	fill_label.text = "Filled %d / %d  %d%%" % [used_slots, max_slots, filled_percent]
	fill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fill_label.modulate = Color(0.78, 0.9, 1.0, 0.95)
	control_box.add_child(fill_label)

	var filled_bar := ProgressBar.new()
	filled_bar.min_value = 0.0
	filled_bar.max_value = float(max_slots)
	filled_bar.value = float(used_slots)
	filled_bar.show_percentage = false
	filled_bar.custom_minimum_size = Vector2(240, 10)
	filled_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filled_bar.tooltip_text = "Current filled workers. The slider above sets the future worker limit."
	control_box.add_child(filled_bar)

	return row


func _make_info_row(title_text: String, body_text: String, right_text: String) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.047, 0.057, 0.86), Color(0.18, 0.34, 0.42, 0.28), 4, 1))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	row.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(text_box)

	var title_label := Label.new()
	title_label.text = title_text
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.clip_text = true
	text_box.add_child(title_label)

	var body_label := Label.new()
	body_label.text = body_text if not body_text.strip_edges().is_empty() else " "
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.modulate = Color(0.82, 0.86, 0.9, 0.9)
	text_box.add_child(body_label)

	var right_label := Label.new()
	right_label.text = right_text
	right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_label.custom_minimum_size = Vector2(160, 0)
	right_label.modulate = Color(0.9, 0.92, 0.96, 0.96)
	hbox.add_child(right_label)
	return row


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.modulate = Color(0.96, 0.88, 0.72, 1.0)
	return label


func _make_muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(0.75, 0.78, 0.82, 0.82)
	return label


func _clear_container(container: Container) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _clear_node_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _on_job_cap_slider_value_changed(value: float, job_id: String) -> void:
	if _is_refreshing or _colony_id.is_empty() or job_id.strip_edges().is_empty():
		return
	var cap := int(round(value))
	if int(_current_job_caps.get(job_id, -1)) == cap:
		return
	_current_job_caps[job_id] = cap
	job_cap_changed.emit(_colony_id, job_id, cap)


func _format_job_slots(job_slots_variant: Variant) -> String:
	if job_slots_variant is not Dictionary:
		return "No jobs"
	var job_slots: Dictionary = job_slots_variant
	var parts: Array[String] = []
	var job_ids: Array[String] = []
	for job_id_variant in job_slots.keys():
		job_ids.append(str(job_id_variant))
	job_ids.sort()
	for job_id in job_ids:
		parts.append("%s %d" % [_format_token(job_id), int(job_slots.get(job_id, 0))])
	if parts.is_empty():
		return "No jobs"
	return ", ".join(parts)


func _format_species_counts(species_counts_variant: Variant) -> String:
	var species_counts: Array = species_counts_variant if species_counts_variant is Array else []
	var parts: Array[String] = []
	for species_variant in species_counts:
		if species_variant is not Dictionary:
			continue
		var species: Dictionary = species_variant
		parts.append("%s %s" % [
			_format_population(int(species.get("population", 0))),
			str(species.get("species_name", "Species")),
		])
	if parts.is_empty():
		return "None"
	return "; ".join(parts)


func _format_resource_map(resource_map_variant: Variant, signed: bool) -> String:
	if resource_map_variant is not Dictionary:
		return "0"
	var resource_map: Dictionary = resource_map_variant
	var resource_ids: Array[String] = []
	for resource_id_variant in resource_map.keys():
		var resource_id := str(resource_id_variant)
		if int(resource_map.get(resource_id_variant, 0)) != 0:
			resource_ids.append(resource_id)
	resource_ids.sort()
	var parts: Array[String] = []
	for resource_id in resource_ids:
		parts.append("%s %s" % [
			resource_id,
			_format_milliunits(int(resource_map.get(resource_id, 0)), signed),
		])
	if parts.is_empty():
		return "0"
	return ", ".join(parts)


func _format_amount_array(amounts_variant: Variant, signed: bool) -> String:
	var amounts: Array = amounts_variant if amounts_variant is Array else []
	var parts: Array[String] = []
	for amount_variant in amounts:
		if amount_variant is not Dictionary:
			continue
		var amount: Dictionary = amount_variant
		parts.append("%s %s" % [
			str(amount.get("resource_id", "")),
			_format_milliunits(int(amount.get("milliunits", 0)), signed),
		])
	if parts.is_empty():
		return "0"
	return ", ".join(parts)


func _format_milliunits(amount: int, signed: bool) -> String:
	var sign: String = ""
	if signed and amount > 0:
		sign = "+"
	var absolute_amount: int = abs(amount)
	var whole: int = int(absolute_amount / 1000)
	var fraction: int = absolute_amount % 1000
	var prefix: String = "-" if amount < 0 else sign
	if fraction == 0:
		return "%s%d" % [prefix, whole]
	return "%s%d.%03d" % [prefix, whole, fraction]


func _format_population(value: int) -> String:
	if value >= 1000 and value % 1000 == 0:
		return "%dk" % int(value / 1000)
	return str(value)


func _format_token(value: String) -> String:
	var trimmed_value := value.strip_edges()
	if trimmed_value.is_empty():
		return ""
	return trimmed_value.replace("_", " ").capitalize()


func _stringify_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result
