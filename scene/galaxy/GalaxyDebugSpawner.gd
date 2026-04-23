extends RefCounted
class_name GalaxyDebugSpawner

const DEBUG_FLEET_CLASS_ID: String = "debug_corvette"
const DEBUG_STATION_CLASS_ID: String = "debug_station"

var _panel: PanelContainer = null
var _toggle_button: Button = null
var _empire_picker: OptionButton = null
var _use_active_empire_button: Button = null
var _system_picker: OptionButton = null
var _use_inspected_system_button: Button = null
var _fleet_name_line_edit: LineEdit = null
var _fleet_ship_count_spin_box: SpinBox = null
var _spawn_fleet_button: Button = null
var _spawn_station_button: Button = null
var _status_label: Label = null
var _visible: bool = false
var _get_active_empire_id: Callable = Callable()
var _get_inspected_system_id: Callable = Callable()
var _get_systems_by_id: Callable = Callable()
var _spawn_runtime_ship: Callable = Callable()
var _create_runtime_fleet: Callable = Callable()


func bind(
	panel: PanelContainer,
	toggle_button: Button,
	get_active_empire_id: Callable,
	get_inspected_system_id: Callable,
	get_systems_by_id: Callable,
	spawn_runtime_ship: Callable,
	create_runtime_fleet: Callable
) -> void:
	_panel = panel
	_toggle_button = toggle_button
	_get_active_empire_id = get_active_empire_id
	_get_inspected_system_id = get_inspected_system_id
	_get_systems_by_id = get_systems_by_id
	_spawn_runtime_ship = spawn_runtime_ship
	_create_runtime_fleet = create_runtime_fleet
	_empire_picker = panel.get_node("MarginContainer/VBoxContainer/EmpirePickerRow/EmpireOptionButton") as OptionButton
	_use_active_empire_button = panel.get_node("MarginContainer/VBoxContainer/EmpirePickerRow/UseActiveEmpireButton") as Button
	_system_picker = panel.get_node("MarginContainer/VBoxContainer/SystemPickerRow/SystemOptionButton") as OptionButton
	_use_inspected_system_button = panel.get_node("MarginContainer/VBoxContainer/SystemPickerRow/UseInspectedSystemButton") as Button
	_fleet_name_line_edit = panel.get_node("MarginContainer/VBoxContainer/FleetNameLineEdit") as LineEdit
	_fleet_ship_count_spin_box = panel.get_node("MarginContainer/VBoxContainer/FleetShipCountSpinBox") as SpinBox
	_spawn_fleet_button = panel.get_node("MarginContainer/VBoxContainer/ButtonRow/SpawnFleetButton") as Button
	_spawn_station_button = panel.get_node("MarginContainer/VBoxContainer/ButtonRow/SpawnStationButton") as Button
	_status_label = panel.get_node("MarginContainer/VBoxContainer/StatusLabel") as Label

	_toggle_button.pressed.connect(_on_toggle_pressed)
	_use_active_empire_button.pressed.connect(_on_use_active_empire_pressed)
	_use_inspected_system_button.pressed.connect(_on_use_inspected_system_pressed)
	_spawn_fleet_button.pressed.connect(_on_spawn_fleet_pressed)
	_spawn_station_button.pressed.connect(_on_spawn_station_pressed)

	configure()


func unbind() -> void:
	_panel = null
	_toggle_button = null
	_empire_picker = null
	_use_active_empire_button = null
	_system_picker = null
	_use_inspected_system_button = null
	_fleet_name_line_edit = null
	_fleet_ship_count_spin_box = null
	_spawn_fleet_button = null
	_spawn_station_button = null
	_status_label = null
	_get_active_empire_id = Callable()
	_get_inspected_system_id = Callable()
	_get_systems_by_id = Callable()
	_spawn_runtime_ship = Callable()
	_create_runtime_fleet = Callable()


func configure() -> void:
	if _panel == null:
		return
	_panel.visible = false
	_fleet_ship_count_spin_box.min_value = 1.0
	_fleet_ship_count_spin_box.max_value = 64.0
	_fleet_ship_count_spin_box.step = 1.0
	_fleet_ship_count_spin_box.value = 3.0
	_fleet_name_line_edit.placeholder_text = "Debug Fleet"
	set_status("F9 toggles the spawner.")
	_refresh_toggle_text()


func register_debug_ship_classes() -> void:
	SpaceManager.register_ship_class_from_data({
		"class_id": DEBUG_FLEET_CLASS_ID,
		"display_name": "Debug Corvette",
		"category": "combat",
		"max_hull_points": 300.0,
		"default_ai_role": "combat_patrol",
		"command_tags": ["combat", "fleet"],
		"upkeep_component": {
			"monthly_costs": {
				"energy": 1.0,
				"alloys": 0.2,
			},
			"command_point_cost": 1.0,
		},
		"mobility_component": {
			"cruise_speed": 1.0,
			"acceleration": 1.8,
			"turn_rate_degrees": 220.0,
			"formation_radius": 4.0,
			"can_join_fleets": true,
			"uses_hyperlanes": true,
			"can_orbit_system_objects": true,
		},
	}, true)
	SpaceManager.register_ship_class_from_data({
		"class_id": DEBUG_STATION_CLASS_ID,
		"display_name": "Debug Station",
		"category": "station",
		"max_hull_points": 1800.0,
		"default_ai_role": "system_guard",
		"command_tags": ["station", "defense"],
		"upkeep_component": {
			"monthly_costs": {
				"energy": 3.0,
				"alloys": 0.5,
			},
			"command_point_cost": 0.0,
		},
	}, true)


func populate_panel(empire_records: Array[Dictionary], system_records: Array[Dictionary], active_empire_id: String, inspected_system_id: String) -> void:
	if _empire_picker == null or _system_picker == null:
		return

	_empire_picker.clear()
	for empire_record in empire_records:
		var empire_id: String = str(empire_record.get("id", ""))
		if empire_id.is_empty():
			continue
		_empire_picker.add_item(str(empire_record.get("name", empire_id)))
		var item_index: int = _empire_picker.item_count - 1
		_empire_picker.set_item_metadata(item_index, empire_id)

	_system_picker.clear()
	for system_record in system_records:
		var system_id: String = str(system_record.get("id", ""))
		if system_id.is_empty():
			continue
		_system_picker.add_item(str(system_record.get("name", system_id)))
		var item_index: int = _system_picker.item_count - 1
		_system_picker.set_item_metadata(item_index, system_id)

	sync_defaults(active_empire_id, inspected_system_id, empire_records, system_records)


func sync_defaults(active_empire_id: String, inspected_system_id: String, empire_records: Array[Dictionary], system_records: Array[Dictionary]) -> void:
	if _empire_picker == null or _system_picker == null:
		return

	if _empire_picker.item_count > 0:
		var preferred_empire_id: String = active_empire_id
		if preferred_empire_id.is_empty() and not empire_records.is_empty():
			preferred_empire_id = str(empire_records[0].get("id", ""))
		_select_option_button_value(_empire_picker, preferred_empire_id)

	if _system_picker.item_count > 0:
		var preferred_system_id: String = inspected_system_id
		if preferred_system_id.is_empty() and not system_records.is_empty():
			preferred_system_id = str(system_records[0].get("id", ""))
		_select_option_button_value(_system_picker, preferred_system_id)

	var controls_disabled: bool = _empire_picker.item_count == 0 or _system_picker.item_count == 0
	_spawn_fleet_button.disabled = controls_disabled
	_spawn_station_button.disabled = controls_disabled


func toggle() -> void:
	_visible = not _visible
	if _panel != null:
		_panel.visible = _visible
	_refresh_toggle_text()


func set_visible_state(visible_state: bool) -> void:
	_visible = visible_state
	if _panel != null:
		_panel.visible = _visible
	_refresh_toggle_text()


func is_spawner_visible() -> bool:
	return _visible


func set_status(status_text: String) -> void:
	if _status_label != null:
		_status_label.text = status_text


func _refresh_toggle_text() -> void:
	if _toggle_button != null:
		_toggle_button.text = "Hide Debug Spawner" if _visible else "Show Debug Spawner"


func _select_option_button_value(option_button: OptionButton, value: String) -> void:
	if value.is_empty():
		return
	for item_index in range(option_button.item_count):
		if str(option_button.get_item_metadata(item_index)) != value:
			continue
		option_button.select(item_index)
		return


func _get_selected_empire_id() -> String:
	if _empire_picker == null or _empire_picker.item_count == 0 or _empire_picker.selected < 0:
		return ""
	return str(_empire_picker.get_item_metadata(_empire_picker.selected))


func _get_selected_system_id() -> String:
	if _system_picker == null or _system_picker.item_count == 0 or _system_picker.selected < 0:
		return ""
	return str(_system_picker.get_item_metadata(_system_picker.selected))


func _on_toggle_pressed() -> void:
	toggle()


func _on_use_active_empire_pressed() -> void:
	if not _get_active_empire_id.is_valid():
		return
	_select_option_button_value(_empire_picker, str(_get_active_empire_id.call()))
	set_status("Spawner empire synced to the active empire.")


func _on_use_inspected_system_pressed() -> void:
	if not _get_inspected_system_id.is_valid():
		return
	var inspected_system_id: String = str(_get_inspected_system_id.call())
	_select_option_button_value(_system_picker, inspected_system_id)
	if inspected_system_id.is_empty():
		set_status("No inspected system is available yet.")
		return
	var systems_by_id: Dictionary = _resolve_systems_by_id()
	set_status("Spawner system synced to %s." % str(systems_by_id.get(inspected_system_id, {}).get("name", inspected_system_id)))


func _on_spawn_fleet_pressed() -> void:
	if not _spawn_runtime_ship.is_valid() or not _create_runtime_fleet.is_valid():
		return

	var empire_id: String = _get_selected_empire_id()
	var system_id: String = _get_selected_system_id()
	var ship_count: int = int(_fleet_ship_count_spin_box.value)
	if empire_id.is_empty() or system_id.is_empty() or ship_count <= 0:
		set_status("Choose an empire, a system, and a positive ship count.")
		return

	var ship_ids := PackedStringArray()
	for ship_index in range(ship_count):
		var ship: ShipRuntime = _spawn_runtime_ship.call(DEBUG_FLEET_CLASS_ID, empire_id, system_id, {
			"display_name": "Debug Corvette %02d" % (ship_index + 1),
			"ai_role": "combat_patrol",
		})
		if ship == null:
			set_status("Failed to spawn debug corvettes.")
			return
		ship_ids.append(ship.ship_id)

	var resolved_fleet_name: String = _fleet_name_line_edit.text.strip_edges()
	if resolved_fleet_name.is_empty():
		resolved_fleet_name = "Debug Fleet"

	var fleet: FleetRuntime = _create_runtime_fleet.call(empire_id, system_id, ship_ids, {
		"display_name": resolved_fleet_name,
		"ai_role": "combat_patrol",
	})
	if fleet == null:
		set_status("Fleet creation failed after spawning ships.")
		return

	var systems_by_id: Dictionary = _resolve_systems_by_id()
	set_status("Spawned %d corvettes as %s in %s." % [ship_count, resolved_fleet_name, str(systems_by_id.get(system_id, {}).get("name", system_id))])


func _on_spawn_station_pressed() -> void:
	if not _spawn_runtime_ship.is_valid():
		return

	var empire_id: String = _get_selected_empire_id()
	var system_id: String = _get_selected_system_id()
	if empire_id.is_empty() or system_id.is_empty():
		set_status("Choose an empire and a system first.")
		return

	var presence: Dictionary = SpaceManager.build_system_presence(system_id)
	var station_count: int = int(presence.get("station_count", 0))
	var station: ShipRuntime = _spawn_runtime_ship.call(DEBUG_STATION_CLASS_ID, empire_id, system_id, {
		"display_name": "Debug Station %02d" % (station_count + 1),
		"ai_role": "system_guard",
	})
	if station == null:
		set_status("Failed to spawn debug station.")
		return

	var systems_by_id: Dictionary = _resolve_systems_by_id()
	set_status("Spawned %s in %s." % [station.display_name, str(systems_by_id.get(system_id, {}).get("name", system_id))])


func _resolve_systems_by_id() -> Dictionary:
	if not _get_systems_by_id.is_valid():
		return {}
	var systems_by_id_variant: Variant = _get_systems_by_id.call()
	return systems_by_id_variant if systems_by_id_variant is Dictionary else {}
