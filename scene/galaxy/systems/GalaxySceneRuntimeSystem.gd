extends RefCounted

var _host: Node3D = null


func bind(host: Node3D) -> void:
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
	_host.system_view.hide_view()
	_host._set_galaxy_presentation_visible(true)
	_host.core_stars.multimesh = null
	_host.glow_stars.multimesh = null
	_host.ownership_markers.mesh = null
	_host.ownership_connectors.mesh = null
	_host.hyperlanes.mesh = null
	_host._runtime_placeholder_renderer.clear_runtime_placeholders()
	_host.system_preview_image.texture = null
	if _host.camera_rig.has_method("reset_view"):
		_host.camera_rig.reset_view(_host.galaxy_radius)

	_host._set_loading_state(true, "Resolving settings...", 0.1)
	await _host.get_tree().process_frame

	var resolved_settings := {
		"seed_text": _host.seed_text,
		"star_count": _host.star_count,
		"galaxy_radius": _host.galaxy_radius,
		"min_system_distance": _host.min_system_distance,
		"spiral_arms": _host.spiral_arms,
		"shape": _host.galaxy_shape,
		"hyperlane_density": _host.hyperlane_density,
	}
	for key in _host.generation_settings.keys():
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
	if _host.camera_rig.has_method("set_galaxy_radius"):
		_host.camera_rig.set_galaxy_radius(_host.galaxy_radius)
	if _host.camera_rig.has_method("reset_view"):
		_host.camera_rig.reset_view(_host.galaxy_radius)

	_host._set_loading_state(true, "Preparing empire shells...", 0.6)
	await _host.get_tree().process_frame
	initialize_empires()
	_host._sync_debug_spawner()

	_host._set_loading_state(true, "Bootstrapping economy...", 0.68)
	await _host.get_tree().process_frame
	bootstrap_economy()

	_host._set_loading_state(true, "Preparing scene data...", 0.72)
	await _host.get_tree().process_frame

	_host._set_loading_state(true, "Rendering stars...", 0.84)
	await _host.get_tree().process_frame
	_host._render_stars()

	_host._set_loading_state(true, "Rendering hyperlanes...", 0.92)
	await _host.get_tree().process_frame
	_host._render_hyperlanes()
	_host._render_ownership_markers()
	_host._render_runtime_placeholders()
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
	var owner_name := "Unclaimed"
	if _host.empires_by_id.has(owner_id):
		owner_name = str(_host.empires_by_id[owner_id].get("name", owner_name))

	details["owner_empire_id"] = owner_id
	details["owner_name"] = owner_name
	details["space_presence"] = get_system_space_presence(system_id)
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
		"economy": EconomyManager.build_snapshot(),
	}


func get_system_space_presence(system_id: String) -> Dictionary:
	if system_id.is_empty():
		return {}
	return SpaceManager.build_system_presence(system_id)


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
	_sync_system_economy_sources(system_id)
	_host._render_ownership_markers()
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
			_host._render_hyperlanes()
			_host._render_ownership_markers()
			return true

	_host._render_stars()
	_host._render_hyperlanes()
	_host._render_ownership_markers()
	if not _host.system_records.is_empty():
		var created_system_id: String = str(_host.system_records[_host.system_records.size() - 1].get("id", ""))
		_sync_system_economy_sources(created_system_id)
	_host._update_system_panel()
	_host._update_info_label()
	return true


func add_runtime_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	if _host == null or not _host.galaxy_state.add_hyperlane(system_a_id, system_b_id):
		return false

	sync_cached_state()
	_host._render_hyperlanes()
	_host._update_system_panel()
	_host._update_info_label()
	return true


func remove_runtime_hyperlane(system_a_id: String, system_b_id: String) -> bool:
	if _host == null or not _host.galaxy_state.remove_hyperlane(system_a_id, system_b_id):
		return false

	sync_cached_state()
	_host._render_hyperlanes()
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
	_sync_system_economy_sources(system_id, resolved_details)
	_host._render_stars()
	_host._update_system_panel()
	_host._update_info_label()
	return true


func _sync_system_economy_sources(system_id: String, resolved_details: Dictionary = {}) -> void:
	if _host == null or not EconomyManager.is_bootstrapped():
		return
	if system_id.is_empty() or not _host.systems_by_id.has(system_id):
		return

	var system_details := resolved_details.duplicate(true)
	if system_details.is_empty():
		system_details = resolve_system_details(system_id)

	EconomyManager.sync_system_sources(
		system_id,
		_host.galaxy_state.get_system_owner_id(system_id),
		system_details.get("orbitals", []),
		_host.generated_seed
	)


func initialize_empires() -> void:
	if _host == null:
		return

	var preset_empires: Array[Dictionary] = EmpirePresetManager.build_galaxy_empire_records()
	var desired_empire_count := maxi(_host.DEFAULT_EMPIRE_COUNT, preset_empires.size())
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


func bootstrap_economy() -> void:
	if _host == null:
		return

	var empire_ids := PackedStringArray()
	for empire_record_variant in _host.empire_records:
		var empire_record: Dictionary = empire_record_variant
		var empire_id: String = str(empire_record.get("id", "")).strip_edges()
		if empire_id.is_empty():
			continue
		empire_ids.append(empire_id)

	EconomyManager.bootstrap(empire_ids, build_economy_galaxy_snapshot())


func build_economy_galaxy_snapshot() -> Dictionary:
	if _host == null:
		return {}

	var systems: Array[Dictionary] = []
	for system_record_variant in _host.system_records:
		var system_record: Dictionary = system_record_variant
		var system_id: String = str(system_record.get("id", "")).strip_edges()
		if system_id.is_empty():
			continue
		var system_details: Dictionary = resolve_system_details(system_id)
		systems.append({
			"id": system_id,
			"owner_empire_id": str(system_record.get("owner_empire_id", "")),
			"orbitals": system_details.get("orbitals", []).duplicate(true),
		})

	return {
		"generated_seed": _host.generated_seed,
		"systems": systems,
	}


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
	var runtime_signals := [
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
	var runtime_signals := [
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
	if _host == null:
		return
	_host._render_runtime_placeholders()
	_host._update_system_panel()
