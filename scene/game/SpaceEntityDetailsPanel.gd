extends Control
class_name SpaceEntityDetailsPanel

signal action_requested(action_id: String, payload: Dictionary)
signal member_selected(selection_kind: String, record_id: String)

const PANEL_WIDTH: float = 372.0
const COLOR_PANEL := Color(0.028, 0.04, 0.052, 0.94)
const COLOR_PANEL_BORDER := Color(0.44, 0.64, 0.74, 0.56)
const COLOR_ROW := Color(0.045, 0.064, 0.078, 0.9)
const COLOR_ROW_BORDER := Color(0.34, 0.52, 0.62, 0.36)
const COLOR_TEXT := Color(0.96, 0.98, 1.0, 0.96)
const COLOR_MUTED := Color(0.76, 0.84, 0.9, 0.78)
const COLOR_ACCENT := Color(0.86, 0.62, 0.5, 1.0)
const COLOR_DISABLED := Color(0.55, 0.62, 0.68, 0.68)

var _mode: String = ""
var _unit_id: String = ""
var _fleet_id: String = ""
var _context: Dictionary = {}

var _panel: PanelContainer = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _facts_grid: GridContainer = null
var _actions_box: VBoxContainer = null
var _members_section_label: Label = null
var _members_box: VBoxContainer = null
var _status_label: Label = null


func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_ui()


func open_ship(unit_id: String, context: Dictionary = {}) -> void:
	var unit: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
	if unit == null:
		close()
		return
	_mode = "ship"
	_unit_id = unit.unit_id
	_fleet_id = ""
	_context = context.duplicate(true)
	_populate_ship(unit)
	visible = true


func open_fleet(fleet_id: String, context: Dictionary = {}) -> void:
	var fleet: SpaceFleetRuntime = SpaceManager.get_fleet(fleet_id)
	if fleet == null:
		close()
		return
	if fleet.unit_ids.size() == 1:
		open_ship(fleet.unit_ids[0], context)
		return
	_mode = "fleet"
	_unit_id = ""
	_fleet_id = fleet.fleet_id
	_context = context.duplicate(true)
	_populate_fleet(fleet)
	visible = true


func close() -> void:
	visible = false
	_mode = ""
	_unit_id = ""
	_fleet_id = ""
	_context.clear()
	_clear_dynamic_content()


func refresh() -> void:
	match _mode:
		"ship":
			open_ship(_unit_id, _context)
		"fleet":
			open_fleet(_fleet_id, _context)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "EntityDetailsCard"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_WIDTH - 18.0
	_panel.offset_right = -18.0
	_panel.offset_top = 92.0
	_panel.offset_bottom = -86.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _build_style(COLOR_PANEL, COLOR_PANEL_BORDER, 6, 1))
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "ContentMargin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.name = "ContentVBox"
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.name = "HeaderRow"
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.name = "TitleBox"
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.add_theme_font_size_override("font_size", 22)
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
	_apply_button_style(close_button)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var accent_line := ColorRect.new()
	accent_line.name = "AccentLine"
	accent_line.custom_minimum_size = Vector2(0.0, 1.0)
	accent_line.color = COLOR_ACCENT
	root.add_child(accent_line)

	var scroll := ScrollContainer.new()
	scroll.name = "DetailsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var body := VBoxContainer.new()
	body.name = "DetailsVBox"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	_add_section_label(body, "Status")
	_facts_grid = GridContainer.new()
	_facts_grid.name = "FactsGrid"
	_facts_grid.columns = 2
	_facts_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_facts_grid.add_theme_constant_override("h_separation", 10)
	_facts_grid.add_theme_constant_override("v_separation", 5)
	body.add_child(_facts_grid)

	_add_section_label(body, "Aktionen")
	_actions_box = VBoxContainer.new()
	_actions_box.name = "ActionsBox"
	_actions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions_box.add_theme_constant_override("separation", 7)
	body.add_child(_actions_box)

	_members_section_label = _build_section_label("Flottenmitglieder")
	body.add_child(_members_section_label)

	_members_box = VBoxContainer.new()
	_members_box.name = "FleetMembersVBox"
	_members_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_members_box.add_theme_constant_override("separation", 8)
	body.add_child(_members_box)

	_status_label = _build_body_label("StatusLabel", COLOR_MUTED)
	root.add_child(_status_label)


func _populate_ship(unit: SpaceUnitRuntime) -> void:
	_clear_dynamic_content()
	var unit_class: SpaceUnitClass = SpaceManager.get_unit_class(unit.class_id)
	var class_display_name := unit_class.display_name if unit_class != null else unit.class_id
	var owner_name := _resolve_owner_name(unit.owner_empire_id)
	_title_label.text = unit.display_name
	_subtitle_label.text = "%s / %s" % [class_display_name, owner_name]

	_add_unit_facts(unit, unit_class)
	_add_exploration_progress(unit)
	_add_battle_overview(unit.battle_id)
	_add_combat_actions(unit)
	_add_evasion_action("toggle_unit_evasion", {
		"unit_id": unit.unit_id,
		"active": not bool(unit.metadata.get("evasion_active", false)),
	}, bool(unit.metadata.get("evasion_active", false)), _can_command(unit.owner_empire_id))
	_add_ship_special_actions(unit)

	_members_section_label.visible = false
	_members_box.visible = false
	_status_label.text = "Rechtsklick auf ein Ziel im System bewegt das ausgewaehlte Schiff."


func _populate_fleet(fleet: SpaceFleetRuntime) -> void:
	_clear_dynamic_content()
	var owner_name := _resolve_owner_name(fleet.owner_empire_id)
	_title_label.text = fleet.display_name
	_subtitle_label.text = "Flotte / %s" % owner_name

	_add_fact("Besitzer", owner_name)
	_add_fact("System", _resolve_system_name(fleet.current_system_id))
	_add_fact("Schiffe", str(fleet.unit_ids.size()))
	if not fleet.destination_system_id.is_empty():
		_add_fact("Ziel", _resolve_system_name(fleet.destination_system_id))
		if fleet.eta_days_remaining > 0:
			_add_fact("ETA", "%d Tage" % fleet.eta_days_remaining)
	if not str(fleet.ai_role).is_empty():
		_add_fact("Rolle", _format_token(str(fleet.ai_role)))

	_add_battle_overview(_resolve_fleet_battle_id(fleet))

	var fleet_aggressive := _is_fleet_aggressive(fleet)
	_add_fact("Haltung", "Aggressiv" if fleet_aggressive else "Passiv")
	var fleet_stance_button := _build_action_button(
		"Haltung: Aggressiv" if fleet_aggressive else "Haltung: Passiv",
		"Haltung fuer alle Schiffe dieser Flotte umschalten."
	)
	fleet_stance_button.name = "FleetStanceButton"
	fleet_stance_button.disabled = not _can_command(fleet.owner_empire_id)
	var next_fleet_stance := SpaceUnitRuntime.STANCE_PASSIVE if fleet_aggressive else SpaceUnitRuntime.STANCE_AGGRESSIVE
	fleet_stance_button.pressed.connect(func() -> void:
		action_requested.emit("set_fleet_stance", {
			"fleet_id": fleet.fleet_id,
			"stance": next_fleet_stance,
		})
	)
	_actions_box.add_child(fleet_stance_button)

	var fleet_evasion_active := _is_fleet_evasion_active(fleet)
	_add_evasion_action("toggle_fleet_evasion", {
		"fleet_id": fleet.fleet_id,
		"active": not fleet_evasion_active,
	}, fleet_evasion_active, _can_command(fleet.owner_empire_id))

	var reinforce_button := _build_action_button("Verstaerken", "Debug-Verstaerkung fuer diese Flotte erzeugen.")
	reinforce_button.name = "ReinforceFleetButton"
	reinforce_button.disabled = not _can_command(fleet.owner_empire_id)
	reinforce_button.pressed.connect(func() -> void:
		action_requested.emit("reinforce_fleet", {
			"fleet_id": fleet.fleet_id,
			"template_unit_id": fleet.unit_ids[0] if not fleet.unit_ids.is_empty() else "",
		})
	)
	_actions_box.add_child(reinforce_button)

	_members_section_label.visible = true
	_members_box.visible = true
	for unit_id in fleet.unit_ids:
		var member: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
		if member == null:
			continue
		_members_box.add_child(_build_member_row(fleet, member))

	_status_label.text = "Rechtsklick auf ein Ziel im System bewegt die ganze Flotte."


func _add_unit_facts(unit: SpaceUnitRuntime, unit_class: SpaceUnitClass) -> void:
	_add_fact("Besitzer", _resolve_owner_name(unit.owner_empire_id))
	_add_fact("System", _resolve_system_name(unit.current_system_id))
	_add_fact("Klasse", unit_class.display_name if unit_class != null else unit.class_id)
	if unit_class != null:
		_add_fact("Kategorie", _format_token(unit_class.category))
	_add_fact("Huelle", "%d / %d (%d%%)" % [
		unit.current_hull_points,
		unit.max_hull_points,
		int(round(unit.get_hull_ratio() * 100.0)),
	])
	if unit.max_shield_points > 0:
		_add_fact("Schilde", "%d / %d (%d%%)" % [
			unit.current_shield_points,
			unit.max_shield_points,
			int(round(unit.get_shield_ratio() * 100.0)),
		])
	if unit.armor_points > 0:
		_add_fact("Panzerung", str(unit.armor_points))
	_add_fact("Haltung", "Aggressiv" if unit.is_aggressive() else "Passiv")
	if unit.is_in_battle():
		_add_fact("Kampf", "Im Gefecht")
	if unit.is_stunned():
		_add_fact("Betaeubt", "%d Tage" % unit.stunned_days_remaining)
	if not unit.fleet_id.is_empty():
		var fleet: SpaceFleetRuntime = SpaceManager.get_fleet(unit.fleet_id)
		_add_fact("Flotte", fleet.display_name if fleet != null else unit.fleet_id)
	if not unit.destination_system_id.is_empty():
		_add_fact("Ziel", _resolve_system_name(unit.destination_system_id))
		if unit.eta_days_remaining > 0:
			_add_fact("ETA", "%d Tage" % unit.eta_days_remaining)
	if not str(unit.ai_role).is_empty():
		_add_fact("Rolle", _format_token(str(unit.ai_role)))
	var tags_text := _format_string_list(unit.command_tags, 6)
	if not tags_text.is_empty():
		_add_fact("Tags", tags_text)


func _add_ship_special_actions(unit: SpaceUnitRuntime) -> void:
	var can_command := _can_command(unit.owner_empire_id)
	if unit.can_build_units() and unit.is_mobile():
		var build_button := _build_action_button("Bauziel waehlen", "Dieses Konstruktionsschiff als aktiven Builder setzen.")
		build_button.name = "BuildTargetButton"
		var project := SpaceManager.get_construction_project_for_builder(unit.unit_id)
		build_button.disabled = not can_command or not project.is_empty()
		if not project.is_empty():
			build_button.text = "Bau laeuft"
			build_button.tooltip_text = "Dieses Schiff hat bereits ein aktives Bauprojekt."
		build_button.pressed.connect(func() -> void:
			action_requested.emit("build_target", {"unit_id": unit.unit_id})
		)
		_actions_box.add_child(build_button)

	if unit.can_build_units() and unit.is_stationary():
		_add_shipyard_actions(unit, can_command)

	if _is_science_ship(unit):
		var exploration_order: Dictionary = SpaceManager.get_exploration_order_for_unit(unit.unit_id)
		var survey_button := _build_action_button("System erkunden", "Aktuelles System objektweise erkunden.")
		survey_button.name = "ExploreSystemButton"
		survey_button.disabled = not can_command or not bool(_context.get("can_survey_system", false)) or not exploration_order.is_empty()
		if not exploration_order.is_empty():
			survey_button.text = "Erkundung laeuft"
			survey_button.tooltip_text = "Dieses Wissenschaftsschiff erkundet bereits ein System."
		survey_button.pressed.connect(func() -> void:
			action_requested.emit("explore_system", {
				"unit_id": unit.unit_id,
				"system_id": unit.current_system_id,
			})
		)
		_actions_box.add_child(survey_button)


func _add_shipyard_actions(unit: SpaceUnitRuntime, can_command: bool) -> void:
	var active_project := SpaceManager.get_construction_project_for_builder(unit.unit_id)
	if not active_project.is_empty():
		var status_button := _build_action_button(
			"Bau laeuft: %s (%d Tage)" % [
				str(active_project.get("display_name", active_project.get("build_class_id", ""))),
				int(active_project.get("days_remaining", 0)),
			],
			"Diese Werft hat bereits ein aktives Bauprojekt."
		)
		status_button.name = "ShipyardBusyButton"
		status_button.disabled = true
		_actions_box.add_child(status_button)
		return

	for option in SpaceManager.get_ship_build_options(unit.unit_id):
		var class_id := str(option.get("class_id", ""))
		var design_id := str(option.get("design_id", ""))
		var costs_variant: Variant = option.get("build_costs", [])
		var label := "%s  (%s, %d Tage)" % [
			str(option.get("display_name", class_id)),
			_format_cost_summary(costs_variant),
			int(option.get("build_time_days", 0)),
		]
		var build_ship_button := _build_action_button(label, "Dieses Design in der Werft bauen. Kosten werden sofort abgezogen.")
		build_ship_button.name = "BuildShipButton_%s" % (design_id if not design_id.is_empty() else class_id)
		var affordable := EconomyManager.can_afford(unit.owner_empire_id, costs_variant) if EconomyManager.is_bootstrapped() else true
		build_ship_button.disabled = not can_command or not affordable
		if not affordable:
			build_ship_button.tooltip_text = "Nicht genug Ressourcen."
		build_ship_button.pressed.connect(func() -> void:
			action_requested.emit("build_ship", {
				"unit_id": unit.unit_id,
				"class_id": class_id,
				"design_id": design_id,
			})
		)
		_actions_box.add_child(build_ship_button)


func _format_cost_summary(costs_variant: Variant) -> String:
	if costs_variant is not Array:
		return "-"
	var parts: Array[String] = []
	for amount_variant in costs_variant:
		if amount_variant is not Dictionary:
			continue
		var amount: Dictionary = amount_variant
		parts.append("%d %s" % [int(round(float(int(amount.get("milliunits", 0))) / 1000.0)), str(amount.get("resource_id", ""))])
	return ", ".join(parts) if not parts.is_empty() else "-"


func _add_battle_overview(battle_id: String) -> void:
	if battle_id.is_empty():
		return
	var battle_panel := BattleOverviewPanel.new()
	battle_panel.name = "BattleOverviewSection"
	battle_panel.set_owner_names(_get_owner_names())
	_actions_box.add_child(battle_panel)
	battle_panel.show_battle(battle_id)


func _resolve_fleet_battle_id(fleet: SpaceFleetRuntime) -> String:
	if fleet == null:
		return ""
	for unit_id in fleet.unit_ids:
		var unit: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
		if unit != null and unit.is_in_battle():
			return unit.battle_id
	return ""


func _get_owner_names() -> Dictionary:
	var owner_names_variant: Variant = _context.get("owner_names", {})
	return owner_names_variant if owner_names_variant is Dictionary else {}


func _add_combat_actions(unit: SpaceUnitRuntime) -> void:
	var can_command := _can_command(unit.owner_empire_id)

	var stance_button := _build_action_button(
		"Haltung: Aggressiv" if unit.is_aggressive() else "Haltung: Passiv",
		"Aggressiv greift Feinde im Erfassungsradius automatisch an. Passiv erwidert nur Feuer."
	)
	stance_button.name = "StanceButton"
	stance_button.disabled = not can_command
	var next_stance := SpaceUnitRuntime.STANCE_PASSIVE if unit.is_aggressive() else SpaceUnitRuntime.STANCE_AGGRESSIVE
	stance_button.pressed.connect(func() -> void:
		action_requested.emit("set_unit_stance", {
			"unit_id": unit.unit_id,
			"stance": next_stance,
		})
	)
	_actions_box.add_child(stance_button)

	if unit.design_id.is_empty():
		return
	var design_stats: Dictionary = SpaceManager.get_compiled_ship_design_stats(unit.design_id)
	for ability_variant in design_stats.get("abilities", []):
		if ability_variant is not Dictionary:
			continue
		var ability: Dictionary = ability_variant
		if str(ability.get("trigger", "")) != "manual":
			continue
		var slot_id := str(ability.get("slot_id", ""))
		var component: Dictionary = SpaceManager.get_ship_component(str(ability.get("component_id", "")))
		var ability_name := str(component.get("display_name", ability.get("effect_id", slot_id)))
		var cooldown_days := int(unit.ability_cooldowns.get(slot_id, 0))
		var is_pending := false
		for pending_command in unit.pending_ability_commands:
			if str(pending_command.get("slot_id", "")) == slot_id:
				is_pending = true
				break

		var label := ability_name
		if cooldown_days > 0:
			label = "%s (%d Tage Abklingzeit)" % [ability_name, cooldown_days]
		elif is_pending:
			label = "%s (befohlen)" % ability_name
		var ability_button := _build_action_button(label, "Faehigkeit manuell ausloesen. Wird beim naechsten Tag-Tick ausgefuehrt.")
		ability_button.name = "AbilityButton_%s" % slot_id
		ability_button.disabled = not can_command or cooldown_days > 0 or is_pending
		ability_button.pressed.connect(func() -> void:
			action_requested.emit("trigger_unit_ability", {
				"unit_id": unit.unit_id,
				"slot_id": slot_id,
			})
		)
		_actions_box.add_child(ability_button)


func _add_evasion_action(action_id: String, payload: Dictionary, active: bool, can_command: bool) -> void:
	var button := _build_action_button(
		"Ausweichen aktiv" if active else "Ausweichen passiv",
		"Ausweichmodus fuer diese Auswahl umschalten."
	)
	button.name = "EvasionButton"
	button.disabled = not can_command
	button.pressed.connect(func() -> void:
		action_requested.emit(action_id, payload.duplicate(true))
	)
	_actions_box.add_child(button)


func _add_exploration_progress(unit: SpaceUnitRuntime) -> void:
	if unit == null:
		return
	var order: Dictionary = SpaceManager.get_exploration_order_for_unit(unit.unit_id)
	if order.is_empty():
		return
	_add_fact("Erkundung", "%s %d%%" % [
		str(order.get("state_label", "Aktiv")),
		int(order.get("progress_percent", 0)),
	])
	_add_fact("Scan-Ziel", str(order.get("current_target_name", order.get("current_target_id", ""))))
	var days_remaining := int(order.get("scan_days_remaining", 0))
	if days_remaining > 0:
		_add_fact("Scan Restzeit", "%d Tage" % days_remaining)

	var progress_box := VBoxContainer.new()
	progress_box.name = "ExplorationProgressBox"
	progress_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_box.add_theme_constant_override("separation", 5)

	var label := _build_body_label("ExplorationProgressLabel", COLOR_MUTED)
	label.text = "Erkundungsfortschritt"
	progress_box.add_child(label)

	var progress := ProgressBar.new()
	progress.name = "ExplorationProgressBar"
	progress.min_value = 0.0
	progress.max_value = 100.0
	progress.value = clampf(float(order.get("progress_ratio", 0.0)), 0.0, 1.0) * 100.0
	progress.custom_minimum_size = Vector2(0.0, 18.0)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.show_percentage = true
	progress_box.add_child(progress)

	_actions_box.add_child(progress_box)


func _build_member_row(fleet: SpaceFleetRuntime, unit: SpaceUnitRuntime) -> Control:
	var row := PanelContainer.new()
	row.name = "FleetMember_%s" % unit.unit_id
	row.add_theme_stylebox_override("panel", _build_style(COLOR_ROW, COLOR_ROW_BORDER, 5, 1))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	row.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)

	var title := Label.new()
	title.name = "MemberTitle"
	title.text = unit.display_name
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)

	var unit_class: SpaceUnitClass = SpaceManager.get_unit_class(unit.class_id)
	var meta := Label.new()
	meta.name = "MemberMeta"
	meta.text = "%s  /  Huelle %d%%" % [
		unit_class.display_name if unit_class != null else unit.class_id,
		int(round(unit.get_hull_ratio() * 100.0)),
	]
	meta.add_theme_color_override("font_color", COLOR_MUTED)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(meta)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	column.add_child(buttons)

	var inspect_button := _build_action_button("Ansehen", "Schiff einzeln anzeigen.")
	inspect_button.name = "InspectMemberButton"
	inspect_button.pressed.connect(func() -> void:
		member_selected.emit(SpaceUnitClass.UNIT_KIND_SHIP, unit.unit_id)
	)
	buttons.add_child(inspect_button)

	var split_button := _build_action_button("Split", "Schiff in eine neue Flotte abspalten.")
	split_button.name = "SplitButton"
	split_button.disabled = not _can_command(fleet.owner_empire_id) or fleet.unit_ids.size() <= 1
	split_button.pressed.connect(func() -> void:
		action_requested.emit("split_member", {
			"fleet_id": fleet.fleet_id,
			"unit_id": unit.unit_id,
		})
	)
	buttons.add_child(split_button)

	var remove_button := _build_action_button("Entfernen", "Schiff aus dieser Flotte loesen.")
	remove_button.name = "RemoveMemberButton"
	remove_button.disabled = not _can_command(fleet.owner_empire_id)
	remove_button.pressed.connect(func() -> void:
		action_requested.emit("remove_member", {
			"fleet_id": fleet.fleet_id,
			"unit_id": unit.unit_id,
		})
	)
	buttons.add_child(remove_button)

	return row


func _clear_dynamic_content() -> void:
	_clear_container(_facts_grid)
	_clear_container(_actions_box)
	_clear_container(_members_box)
	if _members_section_label != null:
		_members_section_label.visible = false
	if _members_box != null:
		_members_box.visible = false
	if _status_label != null:
		_status_label.text = ""


func _add_section_label(parent: Control, text: String) -> void:
	parent.add_child(_build_section_label(text))


func _build_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", COLOR_ACCENT)
	return label


func _build_body_label(label_name: String, color: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


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


func _build_action_button(text: String, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(0.0, 30.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button_style(button)
	return button


func _apply_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _build_style(Color(0.065, 0.095, 0.112, 0.96), Color(0.48, 0.68, 0.78, 0.52), 5, 1))
	button.add_theme_stylebox_override("hover", _build_style(Color(0.1, 0.145, 0.17, 1.0), Color(0.72, 0.9, 1.0, 0.78), 5, 1))
	button.add_theme_stylebox_override("pressed", _build_style(Color(0.035, 0.05, 0.065, 0.98), Color(0.86, 0.96, 1.0, 0.9), 5, 1))
	button.add_theme_stylebox_override("disabled", _build_style(Color(0.045, 0.055, 0.064, 0.74), Color(0.15, 0.21, 0.25, 0.46), 5, 1))
	button.add_theme_color_override("font_disabled_color", COLOR_DISABLED)


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


func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _can_command(owner_empire_id: String) -> bool:
	if _context.has("can_command"):
		return bool(_context.get("can_command", false))
	var active_empire_id := str(_context.get("active_empire_id", "")).strip_edges()
	return active_empire_id.is_empty() or active_empire_id == owner_empire_id


func _is_fleet_aggressive(fleet: SpaceFleetRuntime) -> bool:
	if fleet == null or fleet.unit_ids.is_empty():
		return false
	for unit_id in fleet.unit_ids:
		var unit: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
		if unit != null and unit.is_aggressive():
			return true
	return false


func _is_fleet_evasion_active(fleet: SpaceFleetRuntime) -> bool:
	if fleet == null or fleet.unit_ids.is_empty():
		return false
	for unit_id in fleet.unit_ids:
		var unit: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
		if unit == null or not bool(unit.metadata.get("evasion_active", false)):
			return false
	return true


func _is_science_ship(unit: SpaceUnitRuntime) -> bool:
	if unit == null:
		return false
	if unit.class_id == SpaceManager.SCIENCE_SHIP_CLASS_ID:
		return true
	for tag in unit.command_tags:
		if str(tag) in ["science", "survey", "explore"]:
			return true
	return false


func _resolve_owner_name(owner_empire_id: String) -> String:
	var owner_names: Dictionary = _context.get("owner_names", {}) if _context.get("owner_names", {}) is Dictionary else {}
	if owner_names.has(owner_empire_id):
		return str(owner_names.get(owner_empire_id, owner_empire_id))
	if str(_context.get("owner_empire_id", "")) == owner_empire_id and _context.has("owner_name"):
		return str(_context.get("owner_name", owner_empire_id))
	return "Unclaimed" if owner_empire_id.is_empty() else owner_empire_id


func _resolve_system_name(system_id: String) -> String:
	var system_names: Dictionary = _context.get("system_names", {}) if _context.get("system_names", {}) is Dictionary else {}
	if system_names.has(system_id):
		return str(system_names.get(system_id, system_id))
	if str(_context.get("system_id", "")) == system_id and _context.has("system_name"):
		return str(_context.get("system_name", system_id))
	if str(_context.get("destination_system_id", "")) == system_id and _context.has("destination_system_name"):
		return str(_context.get("destination_system_name", system_id))
	return system_id


func _format_token(value: String) -> String:
	var trimmed := value.strip_edges()
	if trimmed.is_empty():
		return "Unassigned"
	return trimmed.replace("_", " ").capitalize()


func _format_string_list(values_variant: Variant, max_items: int) -> String:
	var values := PackedStringArray()
	if values_variant is PackedStringArray:
		values = values_variant
	elif values_variant is Array:
		for value_variant in values_variant:
			var value_text := str(value_variant).strip_edges()
			if not value_text.is_empty():
				values.append(value_text)
	if values.is_empty():
		return ""

	var parts: Array[String] = []
	for value_index in range(mini(values.size(), max_items)):
		parts.append(_format_token(values[value_index]))
	var result := ", ".join(parts)
	if values.size() > max_items:
		result += " +%d" % (values.size() - max_items)
	return result
