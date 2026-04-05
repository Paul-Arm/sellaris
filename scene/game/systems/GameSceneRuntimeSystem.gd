extends RefCounted

var _host: Node = null


func bind(host: Node) -> void:
	_host = host


func unbind() -> void:
	disconnect_space_runtime_signals()
	_host = null


func generate_async() -> void:
	if _host == null or _host._is_generating:
		return

	_host._is_generating = true
	SpaceManager.reset_runtime_state()
	_host._debug_spawner.register_debug_ship_classes()
	_host.selected_system_id = ""
	_host.hovered_system_id = ""
	_host.pinned_system_id = ""
	_host.active_empire_id = ""
	_host._invalidate_system_panel_snapshot()
	_host._set_empire_picker_visible(false, false)
	_host._set_settings_overlay_visible(false)
	_host._set_loading_state(true, "Preparing generator...", 0.0)
	_host.show_galaxy_view()
	await _host.get_tree().process_frame

	_host.system_positions.clear()
	_host.system_records.clear()
	_host.hyperlane_links.clear()
	_host.hyperlane_graph.clear()
	_host.empire_records.clear()
	_host.systems_by_id.clear()
	_host.system_indices_by_id.clear()
	_host.empires_by_id.clear()
	_host.galaxy_state.reset()
	_host._set_galaxy_presentation_visible(true)
	_host.system_preview_image.texture = null
	clear_galaxy_view()

	var galaxy_view: GalaxyMapView = _host.get_galaxy_view()
	if galaxy_view != null:
		galaxy_view.sync_interaction_state("", "")
		galaxy_view.reset_camera_view(_host.galaxy_radius)

	_host._set_loading_state(true, "Resolving settings...", 0.1)
	await _host.get_tree().process_frame

	var resolved_settings: Dictionary = {
		"seed_text": _host.seed_text,
		"star_count": _host.star_count,
		"galaxy_radius": _host.galaxy_radius,
		"min_system_distance": _host.min_system_distance,
		"spiral_arms": _host.spiral_arms,
		"shape": _host.galaxy_shape,
		"hyperlane_density": _host.hyperlane_density,
	}
	for key_variant in _host.generation_settings.keys():
		var key: Variant = key_variant
		resolved_settings[key] = _host.generation_settings[key]

	_host._set_loading_state(true, "Placing systems and hyperlanes...", 0.45)
	await _host.get_tree().process_frame

	var layout: Dictionary = _host.generator.build_layout(resolved_settings, _host.custom_systems)
	_host.galaxy_state.load_from_layout(layout)
	_host.generated_seed = int(layout.get("seed", 0))
	_host.galaxy_radius = float(layout.get("galaxy_radius", _host.galaxy_radius))
	_host.min_system_distance = float(layout.get("min_system_distance", _host.min_system_distance))
	_host.galaxy_shape = str(layout.get("shape", _host.galaxy_shape))
	_host.hyperlane_density = int(layout.get("hyperlane_density", _host.hyperlane_density))
	sync_cached_state()
	sync_galaxy_view_state()
	if galaxy_view != null:
		galaxy_view.set_galaxy_radius(_host.galaxy_radius)
		galaxy_view.reset_camera_view(_host.galaxy_radius)

	_host._set_loading_state(true, "Preparing empire shells...", 0.6)
	await _host.get_tree().process_frame
	initialize_empires()
	_host._sync_debug_spawner()

	_host._set_loading_state(true, "Preparing scene data...", 0.72)
	await _host.get_tree().process_frame

	_host._set_loading_state(true, "Rendering stars...", 0.84)
	await _host.get_tree().process_frame
	render_stars()

	_host._set_loading_state(true, "Rendering hyperlanes...", 0.92)
	await _host.get_tree().process_frame
	render_hyperlanes()
	render_ownership_markers()
	_host._update_system_panel()
	_host._update_info_label()

	_host._set_loading_state(true, "Finalizing...", 1.0)
	await _host.get_tree().process_frame
	_host._set_loading_state(false)
	_host._is_generating = false
	_host._open_empire_picker(true)


func get_system_details(system_id: String) -> Dictionary:
	var details: Dictionary = resolve_system_details(system_id)
	if details.is_empty():
		return {}

	var owner_id: String = _host.galaxy_state.get_system_owner_id(system_id)
	var owner_name: String = "Unclaimed"
	if _host.empires_by_id.has(owner_id):
		owner_name = str(_host.empires_by_id[owner_id].get("name", owner_name))

	details["owner_empire_id"] = owner_id
	details["owner_name"] = owner_name
	details["space_presence"] = get_system_space_presence(system_id)
	details["space_renderables"] = build_system_renderables(system_id)
	return details


func resolve_system_details(system_id: String) -> Dictionary:
	if _host == null or not _host.systems_by_id.has(system_id):
		return {}

	var detail_override: Dictionary = _host.galaxy_state.get_system_detail_override(system_id)
	return _host.generator.generate_system_details(
		_host.generated_seed,
		_host.systems_by_id[system_id],
		_host.custom_systems,
		detail_override
	)


func get_galaxy_state_snapshot() -> Dictionary:
	if _host == null:
		return {}
	return _host.galaxy_state.build_snapshot()


func get_runtime_snapshot() -> Dictionary:
	return {
		"galaxy": get_galaxy_state_snapshot(),
		"space": SpaceManager.build_snapshot(),
	}


func get_system_space_presence(system_id: String) -> Dictionary:
	if system_id.is_empty():
		return {}
	return SpaceManager.build_system_presence(system_id)


func build_system_renderables(system_id: String) -> Dictionary:
	var renderables: Dictionary = SpaceManager.build_system_renderables(system_id)
	var ships_variant: Variant = renderables.get("ships", [])
	if ships_variant is Array:
		var decorated_ships: Array[Dictionary] = []
		for ship_variant in ships_variant:
			var ship_record: Dictionary = ship_variant
			var decorated_ship: Dictionary = ship_record.duplicate(true)
			var owner_empire_id: String = str(decorated_ship.get("owner_empire_id", ""))
			decorated_ship["owner_color"] = _get_empire_runtime_color(owner_empire_id)
			decorated_ship["owner_name"] = _get_empire_runtime_name(owner_empire_id)
			decorated_ship["destination_system_name"] = _get_system_runtime_name(str(decorated_ship.get("destination_system_id", "")))
			var fleet_id: String = str(decorated_ship.get("fleet_id", ""))
			if not fleet_id.is_empty():
				var fleet: FleetRuntime = SpaceManager.get_fleet(fleet_id)
				if fleet != null:
					decorated_ship["fleet_name"] = fleet.display_name
			decorated_ships.append(decorated_ship)
		renderables["ships"] = decorated_ships

	var fleets_variant: Variant = renderables.get("fleets", [])
	if fleets_variant is Array:
		var decorated_fleets: Array[Dictionary] = []
		for fleet_variant in fleets_variant:
			var fleet_record: Dictionary = fleet_variant
			var decorated_fleet: Dictionary = fleet_record.duplicate(true)
			var owner_empire_id: String = str(decorated_fleet.get("owner_empire_id", ""))
			decorated_fleet["owner_color"] = _get_empire_runtime_color(owner_empire_id)
			decorated_fleet["owner_name"] = _get_empire_runtime_name(owner_empire_id)
			decorated_fleet["destination_system_name"] = _get_system_runtime_name(str(decorated_fleet.get("destination_system_id", "")))
			decorated_fleet["home_system_name"] = _get_system_runtime_name(str(decorated_fleet.get("home_system_id", "")))
			var ship_display_names := PackedStringArray()
			for ship_id in _variant_to_packed_string_array(decorated_fleet.get("ship_ids", PackedStringArray())):
				var ship: ShipRuntime = SpaceManager.get_ship(ship_id)
				if ship == null:
					continue
				ship_display_names.append(ship.display_name)
			decorated_fleet["ship_display_names"] = ship_display_names
			decorated_fleets.append(decorated_fleet)
		renderables["fleets"] = decorated_fleets

	return renderables


func _get_empire_runtime_color(empire_id: String) -> Color:
	if _host.empires_by_id.has(empire_id):
		return _host.empires_by_id[empire_id].get("color", Color.WHITE)
	return Color(0.82, 0.88, 1.0, 1.0)


func _get_empire_runtime_name(empire_id: String) -> String:
	if empire_id.is_empty():
		return "Unclaimed"
	if _host.empires_by_id.has(empire_id):
		return str(_host.empires_by_id[empire_id].get("name", empire_id))
	return empire_id


func _get_system_runtime_name(system_id: String) -> String:
	if system_id.is_empty():
		return ""
	if _host.systems_by_id.has(system_id):
		return str(_host.systems_by_id[system_id].get("name", system_id))
	return system_id


func build_bottom_drawer_runtime_entries(inspected_system_id: String = "") -> Dictionary:
	var result := {
		"starbases": [],
		"passive_fleets": [],
		"military_fleets": [],
	}
	if _host == null or _host.active_empire_id.is_empty():
		return result

	var station_entries: Array[Dictionary] = []
	for ship_id in SpaceManager.get_ship_ids_for_owner(_host.active_empire_id):
		var ship: ShipRuntime = SpaceManager.get_ship(ship_id)
		if ship == null or not ship.is_stationary():
			continue

		var ship_class: ShipClass = SpaceManager.get_ship_class(ship.class_id)
		var system_name: String = _get_system_runtime_name(ship.current_system_id)
		var is_local: bool = not inspected_system_id.is_empty() and ship.current_system_id == inspected_system_id
		station_entries.append({
			"id": ship.ship_id,
			"title": ship.display_name,
			"summary": "%s  Hull %d%%" % [
				ship_class.display_name if ship_class != null else ship.class_id,
				int(round(ship.get_hull_ratio() * 100.0)),
			],
			"location": system_name,
			"is_local": is_local,
			"tooltip": "%s\nClass: %s\nSystem: %s\nHull: %.0f / %.0f" % [
				ship.display_name,
				ship_class.display_name if ship_class != null else ship.class_id,
				system_name,
				ship.current_hull_points,
				ship.max_hull_points,
			],
		})

	var passive_fleet_entries: Array[Dictionary] = []
	var military_fleet_entries: Array[Dictionary] = []
	for fleet_id in SpaceManager.get_fleet_ids_for_owner(_host.active_empire_id):
		var fleet: FleetRuntime = SpaceManager.get_fleet(fleet_id)
		if fleet == null:
			continue

		var fleet_bucket: Array[Dictionary] = military_fleet_entries if _is_military_fleet_runtime(fleet) else passive_fleet_entries
		var system_name: String = _get_system_runtime_name(fleet.current_system_id)
		var destination_name: String = _get_system_runtime_name(fleet.destination_system_id)
		var ship_count: int = fleet.ship_ids.size()
		var is_local: bool = not inspected_system_id.is_empty() and fleet.current_system_id == inspected_system_id
		var status_text: String = "%d ships" % ship_count
		if not destination_name.is_empty():
			status_text += "  ->  %s" % destination_name
			if fleet.eta_days_remaining > 0:
				status_text += " (%dd)" % fleet.eta_days_remaining
		elif not str(fleet.ai_role).is_empty():
			status_text += "  %s" % _format_runtime_token(str(fleet.ai_role))

		var member_names := PackedStringArray()
		for ship_member_id in fleet.ship_ids:
			var member_ship: ShipRuntime = SpaceManager.get_ship(ship_member_id)
			if member_ship == null:
				continue
			member_names.append(member_ship.display_name)

		fleet_bucket.append({
			"id": fleet.fleet_id,
			"title": fleet.display_name,
			"summary": status_text,
			"location": system_name,
			"is_local": is_local,
			"tooltip": "%s\nSystem: %s\nShips: %d\nRole: %s\nMembers: %s" % [
				fleet.display_name,
				system_name,
				ship_count,
				_format_runtime_token(str(fleet.ai_role)),
				", ".join(member_names),
			],
		})

	result["starbases"] = _sort_bottom_drawer_entries(station_entries)
	result["passive_fleets"] = _sort_bottom_drawer_entries(passive_fleet_entries)
	result["military_fleets"] = _sort_bottom_drawer_entries(military_fleet_entries)
	return result


func _sort_bottom_drawer_entries(entries: Array[Dictionary]) -> Array[Dictionary]:
	var local_entries: Array[Dictionary] = []
	var remote_entries: Array[Dictionary] = []
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if bool(entry.get("is_local", false)):
			local_entries.append(entry)
		else:
			remote_entries.append(entry)
	local_entries.sort_custom(_sort_bottom_drawer_entries_by_title)
	remote_entries.sort_custom(_sort_bottom_drawer_entries_by_title)
	var ordered_entries: Array[Dictionary] = []
	ordered_entries.append_array(local_entries)
	ordered_entries.append_array(remote_entries)
	return ordered_entries


func _is_military_fleet_runtime(fleet: FleetRuntime) -> bool:
	for ship_id in fleet.ship_ids:
		var ship: ShipRuntime = SpaceManager.get_ship(ship_id)
		if ship == null:
			continue
		var ship_class: ShipClass = SpaceManager.get_ship_class(ship.class_id)
		if ship_class != null and ship_class.category == ShipClass.CATEGORY_COMBAT:
			return true
		for command_tag in ship.command_tags:
			if str(command_tag).contains("combat"):
				return true
		if str(ship.ai_role).contains("combat") or str(ship.ai_role).contains("patrol") or str(ship.ai_role).contains("defense"):
			return true
	if str(fleet.ai_role).contains("combat") or str(fleet.ai_role).contains("patrol") or str(fleet.ai_role).contains("defense"):
		return true
	return false


func _format_runtime_token(value: String) -> String:
	var trimmed_value: String = value.strip_edges()
	if trimmed_value.is_empty():
		return "Unassigned"
	return trimmed_value.replace("_", " ").capitalize()


static func _sort_bottom_drawer_entries_by_title(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("title", "")).nocasecmp_to(str(b.get("title", ""))) < 0


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


func spawn_runtime_ship(class_id: String, owner_empire_id: String, system_id: String, spawn_data: Dictionary = {}) -> ShipRuntime:
	if _host == null or system_id.is_empty() or not _host.systems_by_id.has(system_id):
		return null
	return SpaceManager.spawn_ship(class_id, owner_empire_id, system_id, spawn_data)


func create_runtime_fleet(owner_empire_id: String, system_id: String, ship_ids_variant: Variant = PackedStringArray(), fleet_data: Dictionary = {}) -> FleetRuntime:
	if _host == null or system_id.is_empty() or not _host.systems_by_id.has(system_id):
		return null
	return SpaceManager.create_fleet(owner_empire_id, system_id, ship_ids_variant, fleet_data)


func assign_active_empire(empire_id: String) -> bool:
	if _host == null or not _host.galaxy_state.set_local_player_empire(empire_id):
		return false

	_host.active_empire_id = empire_id
	sync_cached_state()
	_host._populate_empire_picker()
	_host._sync_debug_spawner()
	_host._update_system_panel()
	_host._update_info_label()
	return true


func set_system_owner(system_id: String, empire_id: String) -> bool:
	if _host == null or not _host.galaxy_state.set_system_owner(system_id, empire_id):
		return false

	sync_cached_state()
	render_ownership_markers()
	_host._update_system_panel()
	_host._update_info_label()
	return true


func clear_system_owner(system_id: String) -> bool:
	return set_system_owner(system_id, "")


func set_runtime_system_details(system_id: String, detail_patch: Dictionary) -> bool:
	if _host == null or not _host.systems_by_id.has(system_id):
		return false

	var resolved_details: Dictionary = _host.generator.generate_system_details(
		_host.generated_seed,
		_host.systems_by_id[system_id],
		_host.custom_systems,
		detail_patch
	)
	return _apply_system_detail_state(system_id, resolved_details, true)


func patch_runtime_system_details(system_id: String, detail_patch: Dictionary) -> bool:
	if _host == null or not _host.systems_by_id.has(system_id):
		return false

	var resolved_details: Dictionary = _host.generator.apply_system_detail_patch(
		resolve_system_details(system_id),
		detail_patch
	)
	return _apply_system_detail_state(system_id, resolved_details, true)


func clear_runtime_system_details(system_id: String) -> bool:
	if _host == null or not _host.systems_by_id.has(system_id):
		return false
	if not _host.galaxy_state.clear_system_detail_override(system_id):
		return false

	var resolved_details: Dictionary = _host.generator.generate_system_details(
		_host.generated_seed,
		_host.systems_by_id[system_id],
		_host.custom_systems
	)
	return _apply_system_detail_state(system_id, resolved_details, false)


func add_runtime_system(system_record: Dictionary, detail_patch: Dictionary = {}) -> bool:
	if _host == null or not _host.galaxy_state.add_system(system_record):
		return false

	sync_cached_state()
	if not detail_patch.is_empty() and not _host.system_records.is_empty():
		var created_record: Dictionary = _host.system_records[_host.system_records.size() - 1]
		var created_system_id: String = str(created_record.get("id", ""))
		if not created_system_id.is_empty():
			var resolved_details: Dictionary = _host.generator.generate_system_details(
				_host.generated_seed,
				created_record,
				_host.custom_systems,
				detail_patch
			)
			if not _apply_system_detail_state(created_system_id, resolved_details, true):
				return false
			render_hyperlanes()
			render_ownership_markers()
			return true

	render_stars()
	render_hyperlanes()
	render_ownership_markers()
	_host._update_system_panel()
	_host._update_info_label()
	return true


func add_runtime_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	if _host == null or not _host.galaxy_state.add_hyperlane(system_a_id, system_b_id):
		return false

	sync_cached_state()
	render_hyperlanes()
	_host._update_system_panel()
	_host._update_info_label()
	return true


func remove_runtime_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	if _host == null or not _host.galaxy_state.remove_hyperlane(system_a_id, system_b_id):
		return false

	sync_cached_state()
	render_hyperlanes()
	_host._update_system_panel()
	_host._update_info_label()
	return true


func _apply_system_detail_state(system_id: String, resolved_details: Dictionary, store_override: bool) -> bool:
	if store_override:
		if not _host.galaxy_state.set_system_detail_override(system_id, resolved_details):
			return false

	if not _host.galaxy_state.update_system_record(system_id, {
		"star_profile": resolved_details.get("star_profile", {}),
		"system_summary": resolved_details.get("system_summary", {}),
	}):
		return false

	_host._invalidate_system_panel_snapshot(system_id)
	sync_cached_state()
	render_stars()
	_host._update_system_panel()
	_host._update_info_label()
	return true


func initialize_empires() -> void:
	if _host == null:
		return

	var preset_empires: Array[Dictionary] = EmpirePresetManager.build_galaxy_empire_records()
	var desired_empire_count: int = maxi(_host.DEFAULT_EMPIRE_COUNT, preset_empires.size())
	var generated_empires: Array[Dictionary] = _host.empire_factory.build_default_empires(
		_host.generated_seed,
		_host.system_records.size(),
		desired_empire_count
	)
	var merged_empires: Array[Dictionary] = []

	for preset_index in range(preset_empires.size()):
		var preset_record: Dictionary = preset_empires[preset_index].duplicate(true)
		preset_record["player_slot"] = preset_index
		merged_empires.append(preset_record)

	for generated_index in range(generated_empires.size()):
		if merged_empires.size() >= desired_empire_count:
			break

		var generated_record: Dictionary = generated_empires[generated_index].duplicate(true)
		generated_record["id"] = "generated_empire_%02d" % generated_index
		generated_record["player_slot"] = merged_empires.size()
		merged_empires.append(generated_record)

	_host.galaxy_state.set_empires(merged_empires)
	sync_cached_state()
	_host._populate_empire_picker()
	_host._sync_debug_spawner()


func sync_cached_state() -> void:
	if _host == null:
		return
	_host.generated_seed = int(_host.galaxy_state.generated_seed)
	_host.system_positions = _host.galaxy_state.system_positions
	_host.system_records = _host.galaxy_state.system_records
	_host.hyperlane_links = _host.galaxy_state.hyperlane_links
	_host.hyperlane_graph = _host.galaxy_state.hyperlane_graph
	_host.systems_by_id = _host.galaxy_state.systems_by_id
	_host.system_indices_by_id = _host.galaxy_state.system_indices_by_id
	_host.empire_records = _host.galaxy_state.empires
	_host.empires_by_id = _host.galaxy_state.empires_by_id


func connect_space_runtime_signals() -> void:
	if _host == null:
		return
	var runtime_signals: Array[Signal] = [
		SpaceManager.ship_spawned,
		SpaceManager.ship_removed,
		SpaceManager.ship_updated,
		SpaceManager.fleet_created,
		SpaceManager.fleet_removed,
		SpaceManager.fleet_updated,
	]
	for runtime_signal in runtime_signals:
		if not runtime_signal.is_connected(_on_space_runtime_changed):
			runtime_signal.connect(_on_space_runtime_changed)


func disconnect_space_runtime_signals() -> void:
	var runtime_signals: Array[Signal] = [
		SpaceManager.ship_spawned,
		SpaceManager.ship_removed,
		SpaceManager.ship_updated,
		SpaceManager.fleet_created,
		SpaceManager.fleet_removed,
		SpaceManager.fleet_updated,
	]
	for runtime_signal in runtime_signals:
		if runtime_signal.is_connected(_on_space_runtime_changed):
			runtime_signal.disconnect(_on_space_runtime_changed)


func _on_space_runtime_changed(_record_id: String) -> void:
	if _host == null or _host._runtime_visual_refresh_queued:
		return
	_host._runtime_visual_refresh_queued = true
	Callable(self, "refresh_runtime_visuals").call_deferred()


func refresh_runtime_visuals() -> void:
	if _host == null:
		return
	_host._runtime_visual_refresh_queued = false
	render_runtime_placeholders()
	_host._update_system_panel()


func sync_galaxy_view_state() -> void:
	var galaxy_view: GalaxyMapView = _host.get_galaxy_view()
	if galaxy_view == null:
		return
	galaxy_view.sync_state(
		_host.system_positions,
		_host.system_records,
		_host.hyperlane_links,
		_host.empires_by_id,
		_host.min_system_distance,
		_host.ownership_bright_rim_enabled,
		_host.ownership_core_opacity,
		_host.pinned_system_id
	)
	galaxy_view.sync_interaction_state(_host.hovered_system_id, _host.pinned_system_id)


func clear_galaxy_view() -> void:
	var galaxy_view: GalaxyMapView = _host.get_galaxy_view()
	if galaxy_view != null:
		galaxy_view.clear_rendered_map()


func render_stars() -> void:
	var galaxy_view: GalaxyMapView = _host.get_galaxy_view()
	if galaxy_view == null:
		return
	sync_galaxy_view_state()
	galaxy_view.render_stars()


func render_runtime_placeholders() -> void:
	var galaxy_view: GalaxyMapView = _host.get_galaxy_view()
	if galaxy_view == null:
		return
	sync_galaxy_view_state()
	galaxy_view.render_runtime_placeholders()


func clear_runtime_placeholders() -> void:
	var galaxy_view: GalaxyMapView = _host.get_galaxy_view()
	if galaxy_view != null:
		galaxy_view.clear_runtime_placeholders()


func render_hyperlanes() -> void:
	var galaxy_view: GalaxyMapView = _host.get_galaxy_view()
	if galaxy_view == null:
		return
	sync_galaxy_view_state()
	galaxy_view.render_hyperlanes()


func render_ownership_markers() -> void:
	var galaxy_view: GalaxyMapView = _host.get_galaxy_view()
	if galaxy_view == null:
		return
	sync_galaxy_view_state()
	galaxy_view.render_ownership_markers()
