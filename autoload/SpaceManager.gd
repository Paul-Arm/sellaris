extends Node

const SHIP_CLASS_SCRIPT: Script = preload("res://core/space/ShipClass.gd")
const SHIP_RUNTIME_SCRIPT: Script = preload("res://core/space/ShipRuntime.gd")
const FLEET_RUNTIME_SCRIPT: Script = preload("res://core/space/FleetRuntime.gd")
const SHIP_SOURCE_PREFIX := "ship:"

signal ship_class_registered(class_id: String)
signal ship_spawned(ship_id: String)
signal ship_removed(ship_id: String)
signal ship_updated(ship_id: String)
signal fleet_created(fleet_id: String)
signal fleet_removed(fleet_id: String)
signal fleet_updated(fleet_id: String)

var _next_ship_id: int = 1
var _next_fleet_id: int = 1
var _ship_classes: Dictionary = {}
var _ships: Dictionary = {}
var _fleets: Dictionary = {}
var _ship_ids_by_owner: Dictionary = {}
var _ship_ids_by_system: Dictionary = {}
var _ship_ids_by_class: Dictionary = {}
var _fleet_ids_by_owner: Dictionary = {}
var _fleet_ids_by_system: Dictionary = {}


func _ready() -> void:
	if SimClock != null:
		if not SimClock.day_tick.is_connected(_on_sim_day_tick):
			SimClock.day_tick.connect(_on_sim_day_tick)


func reset_runtime_state(clear_ship_classes: bool = false) -> void:
	for ship_id_variant in _ships.keys():
		_remove_ship_economy_source(str(ship_id_variant))
	_next_ship_id = 1
	_next_fleet_id = 1
	_ships.clear()
	_fleets.clear()
	_ship_ids_by_owner.clear()
	_ship_ids_by_system.clear()
	_ship_ids_by_class.clear()
	_fleet_ids_by_owner.clear()
	_fleet_ids_by_system.clear()
	if clear_ship_classes:
		_ship_classes.clear()


func register_ship_class(ship_class: ShipClass, overwrite_existing: bool = false) -> bool:
	if ship_class == null:
		return false

	ship_class.ensure_defaults()
	if ship_class.class_id.is_empty():
		return false
	if _ship_classes.has(ship_class.class_id) and not overwrite_existing:
		return false

	_ship_classes[ship_class.class_id] = ship_class
	if overwrite_existing:
		_rebuild_indexes_and_economy_sources()
	ship_class_registered.emit(ship_class.class_id)
	return true


func register_ship_class_from_data(class_data: Dictionary, overwrite_existing: bool = false) -> bool:
	var ship_class := SHIP_CLASS_SCRIPT.from_dict(class_data) as ShipClass
	if ship_class == null:
		return false
	return register_ship_class(ship_class, overwrite_existing)


func unregister_ship_class(class_id: String) -> bool:
	if class_id.is_empty() or not _ship_classes.has(class_id):
		return false
	if _ship_ids_by_class.has(class_id):
		return false
	_ship_classes.erase(class_id)
	return true


func has_ship_class(class_id: String) -> bool:
	return _ship_classes.has(class_id)


func get_ship_class(class_id: String) -> ShipClass:
	return _ship_classes.get(class_id, null)


func get_all_ship_classes() -> Array[ShipClass]:
	var result: Array[ShipClass] = []
	for ship_class_variant in _ship_classes.values():
		var ship_class: ShipClass = ship_class_variant
		result.append(ship_class)
	return result


func spawn_ship(class_id: String, owner_empire_id: String, system_id: String, spawn_data: Dictionary = {}) -> ShipRuntime:
	var ship_class := get_ship_class(class_id)
	if ship_class == null:
		return null

	ship_class.ensure_defaults()
	if ship_class.ownership_component != null and ship_class.ownership_component.requires_owner and owner_empire_id.is_empty():
		return null

	var ship_id: String = str(spawn_data.get("ship_id", ""))
	if ship_id.is_empty():
		ship_id = _generate_ship_id()
	if _ships.has(ship_id):
		return null

	var controller_kind: String = str(spawn_data.get("controller_kind", ShipOwnershipComponent.CONTROLLER_UNASSIGNED))
	if ship_class.ownership_component != null and not ship_class.ownership_component.supports_controller(controller_kind):
		controller_kind = ShipOwnershipComponent.CONTROLLER_UNASSIGNED

	var ship := SHIP_RUNTIME_SCRIPT.new() as ShipRuntime
	ship.ship_id = ship_id
	ship.class_id = ship_class.class_id
	ship.display_name = str(spawn_data.get("display_name", ship_class.display_name))
	ship.owner_empire_id = owner_empire_id
	ship.controller_kind = controller_kind
	ship.controller_peer_id = int(spawn_data.get("controller_peer_id", 0))
	ship.ai_role = StringName(str(spawn_data.get("ai_role", str(ship_class.default_ai_role))))
	ship.current_system_id = system_id
	ship.destination_system_id = str(spawn_data.get("destination_system_id", ""))
	ship.eta_days_remaining = maxi(int(spawn_data.get("eta_days_remaining", 0)), 0)
	ship.max_hull_points = ship_class.max_hull_points
	ship.current_hull_points = clampf(float(spawn_data.get("current_hull_points", ship.max_hull_points)), 0.0, ship.max_hull_points)
	ship.capability_mask = ship_class.get_capability_mask()
	ship.command_tags = ship_class.command_tags.duplicate()
	ship.metadata = _sanitize_dictionary(spawn_data.get("metadata", ship_class.metadata))

	_ships[ship_id] = ship
	_add_to_index(_ship_ids_by_owner, owner_empire_id, ship_id)
	_add_to_index(_ship_ids_by_system, system_id, ship_id)
	_add_to_index(_ship_ids_by_class, ship.class_id, ship_id)
	_sync_ship_economy_source(ship)
	ship_spawned.emit(ship_id)
	return ship


func remove_ship(ship_id: String) -> bool:
	var ship := get_ship(ship_id)
	if ship == null:
		return false

	if not ship.fleet_id.is_empty():
		remove_ship_from_fleet(ship_id)

	_remove_from_index(_ship_ids_by_owner, ship.owner_empire_id, ship_id)
	_remove_from_index(_ship_ids_by_system, ship.current_system_id, ship_id)
	_remove_from_index(_ship_ids_by_class, ship.class_id, ship_id)
	_remove_ship_economy_source(ship_id)
	_ships.erase(ship_id)
	ship_removed.emit(ship_id)
	return true


func get_ship(ship_id: String) -> ShipRuntime:
	return _ships.get(ship_id, null)


func get_ship_ids_for_owner(empire_id: String) -> PackedStringArray:
	return _get_index_values(_ship_ids_by_owner, empire_id)


func get_ship_ids_in_system(system_id: String) -> PackedStringArray:
	return _get_index_values(_ship_ids_by_system, system_id)


func get_ship_ids_of_class(class_id: String) -> PackedStringArray:
	return _get_index_values(_ship_ids_by_class, class_id)


func get_owner_monthly_upkeep(empire_id: String) -> Dictionary:
	var totals: Dictionary = {}
	for ship_id in get_ship_ids_for_owner(empire_id):
		var ship := get_ship(ship_id)
		if ship == null:
			continue
		var ship_class := get_ship_class(ship.class_id)
		if ship_class == null:
			continue
		_merge_amount_defs_into_map(totals, ship_class.get_monthly_upkeep())
	return totals


func set_ship_owner(
	ship_id: String,
	owner_empire_id: String,
	controller_kind: String = ShipOwnershipComponent.CONTROLLER_UNASSIGNED,
	controller_peer_id: int = 0
) -> bool:
	var ship := get_ship(ship_id)
	if ship == null:
		return false

	var ship_class := get_ship_class(ship.class_id)
	if ship_class == null:
		return false
	if ship_class.ownership_component != null and ship_class.ownership_component.requires_owner and owner_empire_id.is_empty():
		return false
	if ship_class.ownership_component != null and not ship_class.ownership_component.supports_controller(controller_kind):
		return false

	var changed := false
	if ship.owner_empire_id != owner_empire_id:
		_remove_from_index(_ship_ids_by_owner, ship.owner_empire_id, ship_id)
		ship.owner_empire_id = owner_empire_id
		_add_to_index(_ship_ids_by_owner, ship.owner_empire_id, ship_id)
		_sync_ship_economy_source(ship)
		changed = true

	if ship.controller_kind != controller_kind:
		ship.controller_kind = controller_kind
		changed = true
	if ship.controller_peer_id != controller_peer_id:
		ship.controller_peer_id = controller_peer_id
		changed = true

	if changed:
		ship.command_revision += 1
		if not ship.fleet_id.is_empty():
			if ship_class.ownership_component == null or ship_class.ownership_component.transfer_clears_fleet_assignment:
				remove_ship_from_fleet(ship_id)
			else:
				var fleet := get_fleet(ship.fleet_id)
				if fleet != null and fleet.owner_empire_id != owner_empire_id:
					remove_ship_from_fleet(ship_id)
		ship_updated.emit(ship_id)

	return changed


func set_ship_system(ship_id: String, system_id: String) -> bool:
	var ship := get_ship(ship_id)
	if ship == null or not ship.fleet_id.is_empty():
		return false
	if ship.current_system_id == system_id:
		return false

	_remove_from_index(_ship_ids_by_system, ship.current_system_id, ship_id)
	ship.current_system_id = system_id
	ship.destination_system_id = ""
	ship.eta_days_remaining = 0
	ship.command_revision += 1
	_add_to_index(_ship_ids_by_system, ship.current_system_id, ship_id)
	ship_updated.emit(ship_id)
	return true


func create_fleet(owner_empire_id: String, system_id: String, ship_ids_variant: Variant = PackedStringArray(), fleet_data: Dictionary = {}) -> FleetRuntime:
	var generated_fleet_index := _next_fleet_id
	var fleet_id: String = str(fleet_data.get("fleet_id", ""))
	if fleet_id.is_empty():
		fleet_id = _generate_fleet_id()
	if _fleets.has(fleet_id):
		return null

	var fleet := FLEET_RUNTIME_SCRIPT.new() as FleetRuntime
	fleet.fleet_id = fleet_id
	fleet.display_name = str(fleet_data.get("display_name", "Fleet %03d" % generated_fleet_index))
	fleet.owner_empire_id = owner_empire_id
	fleet.controller_kind = str(fleet_data.get("controller_kind", ShipOwnershipComponent.CONTROLLER_UNASSIGNED))
	fleet.controller_peer_id = int(fleet_data.get("controller_peer_id", 0))
	fleet.ai_role = StringName(str(fleet_data.get("ai_role", "")))
	fleet.current_system_id = system_id
	fleet.destination_system_id = str(fleet_data.get("destination_system_id", ""))
	fleet.eta_days_remaining = maxi(int(fleet_data.get("eta_days_remaining", 0)), 0)
	fleet.home_system_id = str(fleet_data.get("home_system_id", system_id))
	fleet.metadata = _sanitize_dictionary(fleet_data.get("metadata", {}))

	_fleets[fleet_id] = fleet
	_add_to_index(_fleet_ids_by_owner, owner_empire_id, fleet_id)
	_add_to_index(_fleet_ids_by_system, system_id, fleet_id)

	for ship_id_variant in _variant_to_packed_string_array(ship_ids_variant):
		add_ship_to_fleet(str(ship_id_variant), fleet_id)

	fleet_created.emit(fleet_id)
	return fleet


func get_fleet(fleet_id: String) -> FleetRuntime:
	return _fleets.get(fleet_id, null)


func get_fleet_ids_for_owner(empire_id: String) -> PackedStringArray:
	return _get_index_values(_fleet_ids_by_owner, empire_id)


func get_fleet_ids_in_system(system_id: String) -> PackedStringArray:
	return _get_index_values(_fleet_ids_by_system, system_id)


func add_ship_to_fleet(ship_id: String, fleet_id: String) -> bool:
	var ship := get_ship(ship_id)
	var fleet := get_fleet(fleet_id)
	if ship == null or fleet == null:
		return false
	if not ship.can_join_fleet():
		return false
	if ship.owner_empire_id != fleet.owner_empire_id:
		return false
	if ship.current_system_id != fleet.current_system_id:
		return false
	if ship.fleet_id == fleet_id:
		return false

	if not ship.fleet_id.is_empty():
		remove_ship_from_fleet(ship_id)

	if not fleet.add_ship(ship_id):
		return false

	ship.fleet_id = fleet_id
	ship.command_revision += 1
	ship_updated.emit(ship_id)
	fleet_updated.emit(fleet_id)
	return true


func remove_ship_from_fleet(ship_id: String) -> bool:
	var ship := get_ship(ship_id)
	if ship == null or ship.fleet_id.is_empty():
		return false

	var fleet_id := ship.fleet_id
	var fleet := get_fleet(fleet_id)
	ship.clear_fleet_assignment()
	ship.command_revision += 1
	ship_updated.emit(ship_id)

	if fleet == null:
		return true
	if not fleet.remove_ship(ship_id):
		return true
	if fleet.is_empty():
		disband_fleet(fleet_id)
		return true

	fleet_updated.emit(fleet_id)
	return true


func disband_fleet(fleet_id: String) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null:
		return false

	var ship_ids: PackedStringArray = fleet.ship_ids.duplicate()
	for ship_id in ship_ids:
		var ship := get_ship(ship_id)
		if ship == null:
			continue
		ship.clear_fleet_assignment()
		ship.command_revision += 1
		ship_updated.emit(ship_id)

	_remove_from_index(_fleet_ids_by_owner, fleet.owner_empire_id, fleet_id)
	_remove_from_index(_fleet_ids_by_system, fleet.current_system_id, fleet_id)
	_fleets.erase(fleet_id)
	fleet_removed.emit(fleet_id)
	return true


func set_fleet_system(fleet_id: String, system_id: String) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null:
		return false
	if fleet.current_system_id == system_id and fleet.destination_system_id.is_empty():
		return false

	_remove_from_index(_fleet_ids_by_system, fleet.current_system_id, fleet_id)
	fleet.current_system_id = system_id
	fleet.destination_system_id = ""
	fleet.eta_days_remaining = 0
	fleet.command_revision += 1
	_add_to_index(_fleet_ids_by_system, system_id, fleet_id)

	for ship_id in fleet.ship_ids:
		var ship := get_ship(ship_id)
		if ship == null:
			continue
		_remove_from_index(_ship_ids_by_system, ship.current_system_id, ship.ship_id)
		ship.current_system_id = system_id
		ship.destination_system_id = ""
		ship.eta_days_remaining = 0
		ship.command_revision += 1
		_add_to_index(_ship_ids_by_system, ship.current_system_id, ship.ship_id)
		ship_updated.emit(ship.ship_id)

	fleet_updated.emit(fleet_id)
	return true


func set_fleet_destination(fleet_id: String, destination_system_id: String, eta_days: int = 0) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null:
		return false
	if fleet.destination_system_id == destination_system_id and fleet.eta_days_remaining == maxi(eta_days, 0):
		return false

	fleet.destination_system_id = destination_system_id
	fleet.eta_days_remaining = maxi(eta_days, 0)
	fleet.command_revision += 1

	for ship_id in fleet.ship_ids:
		var ship := get_ship(ship_id)
		if ship == null:
			continue
		ship.destination_system_id = destination_system_id
		ship.eta_days_remaining = fleet.eta_days_remaining
		ship.command_revision += 1
		ship_updated.emit(ship_id)

	fleet_updated.emit(fleet_id)
	return true


func queue_fleet_command(fleet_id: String, command: Dictionary) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null:
		return false
	fleet.command_queue.append(command.duplicate(true))
	fleet.command_revision += 1
	fleet_updated.emit(fleet_id)
	return true


func clear_fleet_commands(fleet_id: String) -> bool:
	var fleet := get_fleet(fleet_id)
	if fleet == null or fleet.command_queue.is_empty():
		return false
	fleet.command_queue.clear()
	fleet.command_revision += 1
	fleet_updated.emit(fleet_id)
	return true


func build_system_presence(system_id: String) -> Dictionary:
	var presence := {
		"system_id": system_id,
		"ship_count": 0,
		"mobile_ship_count": 0,
		"station_count": 0,
		"fleet_count": 0,
		"owner_breakdown": {},
	}

	for ship_id in get_ship_ids_in_system(system_id):
		var ship := get_ship(ship_id)
		if ship == null:
			continue
		presence["ship_count"] = int(presence.get("ship_count", 0)) + 1
		if ship.is_mobile():
			presence["mobile_ship_count"] = int(presence.get("mobile_ship_count", 0)) + 1
		else:
			presence["station_count"] = int(presence.get("station_count", 0)) + 1

		var owner_breakdown: Dictionary = presence.get("owner_breakdown", {})
		var owner_entry: Dictionary = owner_breakdown.get(ship.owner_empire_id, {
			"ship_count": 0,
			"mobile_ship_count": 0,
			"station_count": 0,
			"fleet_count": 0,
		})
		owner_entry["ship_count"] = int(owner_entry.get("ship_count", 0)) + 1
		if ship.is_mobile():
			owner_entry["mobile_ship_count"] = int(owner_entry.get("mobile_ship_count", 0)) + 1
		else:
			owner_entry["station_count"] = int(owner_entry.get("station_count", 0)) + 1
		owner_breakdown[ship.owner_empire_id] = owner_entry
		presence["owner_breakdown"] = owner_breakdown

	for fleet_id in get_fleet_ids_in_system(system_id):
		var fleet := get_fleet(fleet_id)
		if fleet == null:
			continue
		presence["fleet_count"] = int(presence.get("fleet_count", 0)) + 1
		var owner_breakdown: Dictionary = presence.get("owner_breakdown", {})
		var owner_entry: Dictionary = owner_breakdown.get(fleet.owner_empire_id, {
			"ship_count": 0,
			"mobile_ship_count": 0,
			"station_count": 0,
			"fleet_count": 0,
		})
		owner_entry["fleet_count"] = int(owner_entry.get("fleet_count", 0)) + 1
		owner_breakdown[fleet.owner_empire_id] = owner_entry
		presence["owner_breakdown"] = owner_breakdown

	return presence


func build_system_renderables(system_id: String) -> Dictionary:
	var renderables := {
		"system_id": system_id,
		"ships": [],
		"fleets": [],
	}
	var ship_entries: Array[Dictionary] = []
	var fleet_entries: Array[Dictionary] = []

	for ship_id in get_ship_ids_in_system(system_id):
		var ship := get_ship(ship_id)
		if ship == null:
			continue
		var ship_class := get_ship_class(ship.class_id)
		ship_entries.append({
			"ship_id": ship.ship_id,
			"display_name": ship.display_name,
			"owner_empire_id": ship.owner_empire_id,
			"class_id": ship.class_id,
			"class_display_name": ship_class.display_name if ship_class != null else ship.class_id,
			"class_category": ship_class.category if ship_class != null else "",
			"fleet_id": ship.fleet_id,
			"ai_role": str(ship.ai_role),
			"is_mobile": ship.is_mobile(),
			"is_stationary": ship.is_stationary(),
			"hull_ratio": ship.get_hull_ratio(),
			"current_hull_points": ship.current_hull_points,
			"max_hull_points": ship.max_hull_points,
			"current_system_id": ship.current_system_id,
			"destination_system_id": ship.destination_system_id,
			"eta_days_remaining": ship.eta_days_remaining,
			"controller_kind": ship.controller_kind,
			"controller_peer_id": ship.controller_peer_id,
			"command_revision": ship.command_revision,
			"command_tags": ship.command_tags.duplicate(),
			"metadata": ship.metadata.duplicate(true),
		})

	for fleet_id in get_fleet_ids_in_system(system_id):
		var fleet := get_fleet(fleet_id)
		if fleet == null:
			continue
		fleet_entries.append({
			"fleet_id": fleet.fleet_id,
			"display_name": fleet.display_name,
			"owner_empire_id": fleet.owner_empire_id,
			"ship_count": fleet.ship_ids.size(),
			"ship_ids": fleet.ship_ids.duplicate(),
			"ai_role": str(fleet.ai_role),
			"current_system_id": fleet.current_system_id,
			"destination_system_id": fleet.destination_system_id,
			"eta_days_remaining": fleet.eta_days_remaining,
			"home_system_id": fleet.home_system_id,
			"controller_kind": fleet.controller_kind,
			"controller_peer_id": fleet.controller_peer_id,
			"command_queue_size": fleet.command_queue.size(),
			"command_revision": fleet.command_revision,
			"metadata": fleet.metadata.duplicate(true),
		})

	renderables["ships"] = ship_entries
	renderables["fleets"] = fleet_entries
	return renderables


func build_owner_presence(empire_id: String) -> Dictionary:
	var presence := {
		"empire_id": empire_id,
		"ship_count": 0,
		"mobile_ship_count": 0,
		"station_count": 0,
		"fleet_count": 0,
		"system_breakdown": {},
		"monthly_upkeep": get_owner_monthly_upkeep(empire_id),
	}

	for ship_id in get_ship_ids_for_owner(empire_id):
		var ship := get_ship(ship_id)
		if ship == null:
			continue
		presence["ship_count"] = int(presence.get("ship_count", 0)) + 1
		var system_breakdown: Dictionary = presence.get("system_breakdown", {})
		var system_entry: Dictionary = system_breakdown.get(ship.current_system_id, {
			"ship_count": 0,
			"mobile_ship_count": 0,
			"station_count": 0,
			"fleet_count": 0,
		})
		system_entry["ship_count"] = int(system_entry.get("ship_count", 0)) + 1
		if ship.is_mobile():
			presence["mobile_ship_count"] = int(presence.get("mobile_ship_count", 0)) + 1
			system_entry["mobile_ship_count"] = int(system_entry.get("mobile_ship_count", 0)) + 1
		else:
			presence["station_count"] = int(presence.get("station_count", 0)) + 1
			system_entry["station_count"] = int(system_entry.get("station_count", 0)) + 1
		system_breakdown[ship.current_system_id] = system_entry
		presence["system_breakdown"] = system_breakdown

	for fleet_id in get_fleet_ids_for_owner(empire_id):
		var fleet := get_fleet(fleet_id)
		if fleet == null:
			continue
		presence["fleet_count"] = int(presence.get("fleet_count", 0)) + 1
		var system_breakdown: Dictionary = presence.get("system_breakdown", {})
		var system_entry: Dictionary = system_breakdown.get(fleet.current_system_id, {
			"ship_count": 0,
			"mobile_ship_count": 0,
			"station_count": 0,
			"fleet_count": 0,
		})
		system_entry["fleet_count"] = int(system_entry.get("fleet_count", 0)) + 1
		system_breakdown[fleet.current_system_id] = system_entry
		presence["system_breakdown"] = system_breakdown

	return presence


func build_snapshot() -> Dictionary:
	var ship_class_snapshots: Array[Dictionary] = []
	var ship_snapshots: Array[Dictionary] = []
	var fleet_snapshots: Array[Dictionary] = []

	for ship_class_variant in _ship_classes.values():
		var ship_class: ShipClass = ship_class_variant
		ship_class_snapshots.append(ship_class.to_dict())

	for ship_variant in _ships.values():
		var ship: ShipRuntime = ship_variant
		ship_snapshots.append(ship.to_dict())

	for fleet_variant in _fleets.values():
		var fleet: FleetRuntime = fleet_variant
		fleet_snapshots.append(fleet.to_dict())

	return {
		"next_ship_id": _next_ship_id,
		"next_fleet_id": _next_fleet_id,
		"ship_classes": ship_class_snapshots,
		"ships": ship_snapshots,
		"fleets": fleet_snapshots,
	}


func load_snapshot(snapshot: Dictionary, clear_existing_state: bool = true) -> void:
	if clear_existing_state:
		reset_runtime_state(true)

	_next_ship_id = maxi(int(snapshot.get("next_ship_id", 1)), 1)
	_next_fleet_id = maxi(int(snapshot.get("next_fleet_id", 1)), 1)

	for class_variant in snapshot.get("ship_classes", []):
		var class_data: Dictionary = class_variant
		var ship_class := SHIP_CLASS_SCRIPT.from_dict(class_data) as ShipClass
		if ship_class == null:
			continue
		_ship_classes[ship_class.class_id] = ship_class

	for ship_variant in snapshot.get("ships", []):
		var ship_data: Dictionary = ship_variant
		var ship := SHIP_RUNTIME_SCRIPT.from_dict(ship_data) as ShipRuntime
		if ship == null or ship.ship_id.is_empty():
			continue
		_ships[ship.ship_id] = ship

	for fleet_variant in snapshot.get("fleets", []):
		var fleet_data: Dictionary = fleet_variant
		var fleet := FLEET_RUNTIME_SCRIPT.from_dict(fleet_data) as FleetRuntime
		if fleet == null or fleet.fleet_id.is_empty():
			continue
		_fleets[fleet.fleet_id] = fleet

	_rebuild_indexes_and_economy_sources()


func _on_sim_day_tick(_date: Dictionary) -> void:
	for fleet_variant in _fleets.values():
		var fleet: FleetRuntime = fleet_variant
		if fleet.destination_system_id.is_empty():
			continue
		if fleet.eta_days_remaining > 0:
			fleet.eta_days_remaining -= 1
		if fleet.eta_days_remaining > 0:
			for ship_id in fleet.ship_ids:
				var ship := get_ship(ship_id)
				if ship == null:
					continue
				ship.eta_days_remaining = fleet.eta_days_remaining
				ship_updated.emit(ship_id)
			fleet_updated.emit(fleet.fleet_id)
			continue
		set_fleet_system(fleet.fleet_id, fleet.destination_system_id)


func _generate_ship_id() -> String:
	var ship_id := "ship_%06d" % _next_ship_id
	_next_ship_id += 1
	return ship_id


func _generate_fleet_id() -> String:
	var fleet_id := "fleet_%06d" % _next_fleet_id
	_next_fleet_id += 1
	return fleet_id


func _rebuild_indexes_and_economy_sources() -> void:
	_ship_ids_by_owner.clear()
	_ship_ids_by_system.clear()
	_ship_ids_by_class.clear()
	_fleet_ids_by_owner.clear()
	_fleet_ids_by_system.clear()

	for ship_variant in _ships.values():
		var ship: ShipRuntime = ship_variant
		_add_to_index(_ship_ids_by_owner, ship.owner_empire_id, ship.ship_id)
		_add_to_index(_ship_ids_by_system, ship.current_system_id, ship.ship_id)
		_add_to_index(_ship_ids_by_class, ship.class_id, ship.ship_id)
		_sync_ship_economy_source(ship)

	for fleet_variant in _fleets.values():
		var fleet: FleetRuntime = fleet_variant
		_add_to_index(_fleet_ids_by_owner, fleet.owner_empire_id, fleet.fleet_id)
		_add_to_index(_fleet_ids_by_system, fleet.current_system_id, fleet.fleet_id)


func _sync_ship_economy_source(ship: ShipRuntime) -> void:
	if ship == null:
		return

	var source_id := _get_ship_source_id(ship.ship_id)
	var ship_class := get_ship_class(ship.class_id)
	if EconomyManager == null or ship_class == null or ship.owner_empire_id.is_empty():
		_remove_ship_economy_source(ship.ship_id)
		return

	var upkeep_costs := ship_class.get_monthly_upkeep()
	if upkeep_costs.is_empty():
		_remove_ship_economy_source(ship.ship_id)
		return

	if EconomyManager.has_source(source_id):
		EconomyManager.transfer_source(source_id, ship.owner_empire_id)
		EconomyManager.update_source(source_id, [], upkeep_costs, [])
		return

	EconomyManager.register_source(
		source_id,
		ship.owner_empire_id,
		[],
		upkeep_costs,
		[],
		"ship_upkeep"
	)


func _remove_ship_economy_source(ship_id: String) -> void:
	if EconomyManager == null:
		return
	var source_id := _get_ship_source_id(ship_id)
	if EconomyManager.has_source(source_id):
		EconomyManager.remove_source(source_id)


func _get_ship_source_id(ship_id: String) -> String:
	return "%s%s" % [SHIP_SOURCE_PREFIX, ship_id]


func _merge_amount_defs_into_map(target: Dictionary, amounts: Array[ResourceAmountDef]) -> void:
	for amount in amounts:
		if amount == null or amount.resource_id.is_empty() or amount.milliunits == 0:
			continue
		target[amount.resource_id] = int(target.get(amount.resource_id, 0)) + amount.milliunits


func _add_to_index(index: Dictionary, key: String, value: String) -> void:
	if key.is_empty() or value.is_empty():
		return
	var bucket: Dictionary = index.get(key, {})
	bucket[value] = true
	index[key] = bucket


func _remove_from_index(index: Dictionary, key: String, value: String) -> void:
	if key.is_empty() or value.is_empty() or not index.has(key):
		return
	var bucket: Dictionary = index[key]
	bucket.erase(value)
	if bucket.is_empty():
		index.erase(key)
		return
	index[key] = bucket


func _get_index_values(index: Dictionary, key: String) -> PackedStringArray:
	var result := PackedStringArray()
	if key.is_empty() or not index.has(key):
		return result
	var bucket: Dictionary = index[key]
	for value_variant in bucket.keys():
		result.append(str(value_variant))
	return result


static func _variant_to_packed_string_array(values: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if values is PackedStringArray:
		return values
	if values is not Array:
		return result
	for value_variant in values:
		var value: String = str(value_variant).strip_edges()
		if value.is_empty():
			continue
		result.append(value)
	return result


static func _sanitize_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}
