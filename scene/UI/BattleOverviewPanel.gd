extends VBoxContainer
class_name BattleOverviewPanel

## Reusable battle overview ("fleet combat menu" content): aggregated side
## bars, per-member hull/shield bars, and a tail of recent battle events,
## all read from the SpaceManager battle registry. Embed it anywhere (entity
## details panel, future battle screens) and call refresh() on combat ticks.

const COLOR_TEXT := Color(0.96, 0.98, 1.0, 0.96)
const COLOR_MUTED := Color(0.76, 0.84, 0.9, 0.78)
const COLOR_HULL := Color(0.95, 0.62, 0.35, 0.95)
const COLOR_SHIELD := Color(0.45, 0.82, 1.0, 0.95)
const COLOR_HEADER := Color(1.0, 0.45, 0.36, 0.95)
const MAX_MEMBER_ROWS := 10
const MAX_LOG_LINES := 6

var _battle_id: String = ""
var _owner_names: Dictionary = {}
var _content_box: VBoxContainer = null


func _ready() -> void:
	add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.name = "BattleHeader"
	header.text = "Gefecht"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", COLOR_HEADER)
	add_child(header)

	_content_box = VBoxContainer.new()
	_content_box.name = "BattleContent"
	_content_box.add_theme_constant_override("separation", 5)
	add_child(_content_box)


func set_owner_names(owner_names: Dictionary) -> void:
	_owner_names = owner_names.duplicate(true)


func show_battle(battle_id: String) -> void:
	_battle_id = battle_id.strip_edges()
	refresh()


func get_battle_id() -> String:
	return _battle_id


func refresh() -> void:
	if _content_box == null:
		return
	for child in _content_box.get_children():
		child.queue_free()
	if _battle_id.is_empty():
		visible = false
		return

	var battle: Dictionary = SpaceManager.get_battle(_battle_id)
	if battle.is_empty():
		visible = false
		return
	visible = true

	var member_ids: Array[String] = []
	var members_variant: Variant = battle.get("member_unit_ids", {})
	if members_variant is Dictionary:
		for unit_id_variant in (members_variant as Dictionary).keys():
			member_ids.append(str(unit_id_variant))
	member_ids.sort()

	_add_side_bars(member_ids)
	_add_member_rows(member_ids)
	_add_event_log(battle)


func _add_side_bars(member_ids: Array[String]) -> void:
	var sides: Dictionary = {}
	for unit_id in member_ids:
		var unit: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
		if unit == null:
			continue
		var side: Dictionary = sides.get(unit.owner_empire_id, {
			"unit_count": 0,
			"hull": 0,
			"max_hull": 0,
			"shield": 0,
			"max_shield": 0,
		})
		side["unit_count"] = int(side.get("unit_count", 0)) + 1
		side["hull"] = int(side.get("hull", 0)) + unit.current_hull_points
		side["max_hull"] = int(side.get("max_hull", 0)) + unit.max_hull_points
		side["shield"] = int(side.get("shield", 0)) + unit.current_shield_points
		side["max_shield"] = int(side.get("max_shield", 0)) + unit.max_shield_points
		sides[unit.owner_empire_id] = side

	var empire_ids: Array[String] = []
	for empire_id_variant in sides.keys():
		empire_ids.append(str(empire_id_variant))
	empire_ids.sort()

	for empire_id in empire_ids:
		var side: Dictionary = sides[empire_id]
		var label := Label.new()
		label.text = "%s - %d Schiffe" % [_resolve_owner_name(empire_id), int(side.get("unit_count", 0))]
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", COLOR_TEXT)
		_content_box.add_child(label)
		_content_box.add_child(_build_bar("Huelle", int(side.get("hull", 0)), int(side.get("max_hull", 1)), COLOR_HULL))
		if int(side.get("max_shield", 0)) > 0:
			_content_box.add_child(_build_bar("Schilde", int(side.get("shield", 0)), int(side.get("max_shield", 1)), COLOR_SHIELD))


func _add_member_rows(member_ids: Array[String]) -> void:
	var shown := 0
	for unit_id in member_ids:
		if shown >= MAX_MEMBER_ROWS:
			var more_label := Label.new()
			more_label.text = "... und %d weitere Schiffe" % (member_ids.size() - shown)
			more_label.add_theme_font_size_override("font_size", 11)
			more_label.add_theme_color_override("font_color", COLOR_MUTED)
			_content_box.add_child(more_label)
			return
		var unit: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
		if unit == null:
			continue
		var row := Label.new()
		row.name = "BattleMember_%s" % unit_id
		var shield_text := " | S %d/%d" % [unit.current_shield_points, unit.max_shield_points] if unit.max_shield_points > 0 else ""
		row.text = "  %s  H %d/%d%s" % [unit.display_name, unit.current_hull_points, unit.max_hull_points, shield_text]
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", COLOR_MUTED)
		_content_box.add_child(row)
		shown += 1


func _add_event_log(battle: Dictionary) -> void:
	var event_log: Array = battle.get("event_log", [])
	if event_log.is_empty():
		return
	var log_header := Label.new()
	log_header.text = "Verlauf"
	log_header.add_theme_font_size_override("font_size", 12)
	log_header.add_theme_color_override("font_color", COLOR_TEXT)
	_content_box.add_child(log_header)

	var start_index := maxi(event_log.size() - MAX_LOG_LINES, 0)
	for event_index in range(start_index, event_log.size()):
		var event_variant: Variant = event_log[event_index]
		if event_variant is not Dictionary:
			continue
		var line := _format_event(event_variant as Dictionary)
		if line.is_empty():
			continue
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", COLOR_MUTED)
		_content_box.add_child(label)


func _format_event(event: Dictionary) -> String:
	match str(event.get("type", "")):
		"shot":
			var attacker := _resolve_unit_name(str(event.get("attacker_unit_id", "")))
			var target := _resolve_unit_name(str(event.get("target_unit_id", "")))
			if not bool(event.get("hit", false)):
				return "%s verfehlt %s" % [attacker, target]
			var shield_damage := int(event.get("shield_damage", 0))
			var hull_damage := int(event.get("hull_damage", 0))
			var damage_parts: Array[String] = []
			if shield_damage > 0:
				damage_parts.append("-%d Schilde" % shield_damage)
			if hull_damage > 0:
				damage_parts.append("-%d Huelle" % hull_damage)
			return "%s trifft %s (%s)" % [attacker, target, ", ".join(damage_parts) if not damage_parts.is_empty() else "kein Schaden"]
		"kill":
			return "Zerstoert: %s" % _resolve_unit_name(str(event.get("unit_id", "")))
		"ability":
			return "%s zuendet %s" % [_resolve_unit_name(str(event.get("unit_id", ""))), str(event.get("effect_id", "Faehigkeit"))]
		"battle_started":
			return "Gefecht begonnen"
		"battle_ended":
			return "Gefecht beendet"
		_:
			return ""


func _resolve_unit_name(unit_id: String) -> String:
	var unit: SpaceUnitRuntime = SpaceManager.get_unit(unit_id)
	if unit != null and not unit.display_name.is_empty():
		return unit.display_name
	return unit_id


func _resolve_owner_name(empire_id: String) -> String:
	return str(_owner_names.get(empire_id, empire_id))


func _build_bar(label_text: String, value: int, max_value: int, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(52.0, 0.0)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	row.add_child(label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = float(maxi(max_value, 1))
	bar.value = float(clampi(value, 0, max_value))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 12.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill_style)
	row.add_child(bar)

	var value_label := Label.new()
	value_label.text = "%d/%d" % [value, max_value]
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", COLOR_MUTED)
	row.add_child(value_label)
	return row
