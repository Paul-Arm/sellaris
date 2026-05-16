extends Node

func _ready() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Builder ship smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()

	_expect(SpaceManager.has_unit_class(SpaceManager.BUILDER_SHIP_CLASS_ID), "builder ship class should be registered", failures)
	_expect(SpaceManager.has_unit_class(SpaceManager.BASIC_STATION_CLASS_ID), "basic station class should be registered", failures)
	_expect(SpaceManager.has_unit_class(SpaceManager.STELLAR_STATION_CLASS_ID), "stellar station class should be registered", failures)
	_expect(SpaceManager.has_unit_class(SpaceManager.RESOURCE_COLLECTOR_STATION_CLASS_ID), "resource collector station class should be registered", failures)

	var builder_class := SpaceManager.get_unit_class(SpaceManager.BUILDER_SHIP_CLASS_ID)
	var station_class := SpaceManager.get_unit_class(SpaceManager.BASIC_STATION_CLASS_ID)
	var stellar_station_class := SpaceManager.get_unit_class(SpaceManager.STELLAR_STATION_CLASS_ID)
	var collector_station_class := SpaceManager.get_unit_class(SpaceManager.RESOURCE_COLLECTOR_STATION_CLASS_ID)
	_expect(builder_class != null and builder_class.has_builder(), "builder ship class should expose builder component", failures)
	_expect(station_class != null and station_class.is_buildable(), "station class should expose buildable component", failures)
	_expect(stellar_station_class != null and stellar_station_class.is_buildable(), "stellar station class should expose buildable component", failures)
	_expect(collector_station_class != null and collector_station_class.is_buildable(), "resource collector station should expose buildable component", failures)
	if station_class != null:
		_expect(station_class.get_build_time_days() == 60, "station should take 60 days to build", failures)
		var round_trip_class := SpaceUnitClass.from_dict(station_class.to_dict())
		_expect(round_trip_class != null and round_trip_class.is_buildable(), "buildable component should round-trip through class snapshots", failures)
		_expect(round_trip_class != null and round_trip_class.get_build_time_days() == 60, "build time should round-trip through class snapshots", failures)
	if stellar_station_class != null:
		_expect(stellar_station_class.get_build_time_days() == 60, "stellar station should take 60 days to build", failures)

	var builder := SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, "empire_builder", "sys_alpha", {
		"display_name": "ISS Mason",
		"local_position": Vector3.ZERO,
	})
	_expect(builder != null and builder.can_build_units(), "builder ship should spawn with build capability", failures)
	if builder == null:
		return

	var buildable_ids := SpaceManager.get_buildable_class_ids_for_builder(builder.unit_id)
	_expect(buildable_ids.has(SpaceManager.BASIC_STATION_CLASS_ID), "builder should list station as buildable", failures)
	_expect(buildable_ids.has(SpaceManager.STELLAR_STATION_CLASS_ID), "builder should list stellar station as buildable", failures)
	_expect(buildable_ids.has(SpaceManager.RESOURCE_COLLECTOR_STATION_CLASS_ID), "builder should list resource collector station as buildable", failures)

	var planet_context := _build_body_context("planet_00", "planet", "Alpha I", Vector3(18.0, 0.0, 0.0), ["orbital_station"])
	var star_context := _build_body_context("star_00", "star", "Alpha", Vector3.ZERO, ["stellar_station"])
	var deposit_context := _build_body_context("planet_deposit", "planet", "Alpha II", Vector3(24.0, 0.0, 0.0), ["orbital_station"])
	deposit_context["generated_seed"] = 7
	deposit_context["body_record"] = {
		"id": "planet_deposit",
		"name": "Alpha II",
		"type": "planet",
		"resource_deposit_component": {
			"mode": "fixed",
			"deposits": [{"resource_id": "matter", "milliunits": 50000}],
		},
	}
	var no_deposit_context := _build_body_context("planet_empty", "planet", "Alpha III", Vector3(30.0, 0.0, 0.0), ["orbital_station"])
	no_deposit_context["generated_seed"] = 7
	no_deposit_context["body_record"] = {
		"id": "planet_empty",
		"name": "Alpha III",
		"type": "planet",
		"resource_deposit_component": {"mode": "none"},
	}
	var planet_options := SpaceManager.get_build_options_for_body(builder.unit_id, "sys_alpha", planet_context)
	var star_options := SpaceManager.get_build_options_for_body(builder.unit_id, "sys_alpha", star_context)
	var deposit_options := SpaceManager.get_build_options_for_body(builder.unit_id, "sys_alpha", deposit_context)
	var no_deposit_options := SpaceManager.get_build_options_for_body(builder.unit_id, "sys_alpha", no_deposit_context)
	_expect(_options_have_class(planet_options, SpaceManager.BASIC_STATION_CLASS_ID), "planet should offer basic station", failures)
	_expect(not _options_have_class(planet_options, SpaceManager.STELLAR_STATION_CLASS_ID), "planet should not offer stellar station", failures)
	_expect(_options_have_class(star_options, SpaceManager.STELLAR_STATION_CLASS_ID), "star should offer stellar station", failures)
	_expect(not _options_have_class(star_options, SpaceManager.BASIC_STATION_CLASS_ID), "star should not offer basic station", failures)
	_expect(_options_have_class(deposit_options, SpaceManager.RESOURCE_COLLECTOR_STATION_CLASS_ID), "body with deposits should offer resource collector station", failures)
	_expect(not _options_have_class(no_deposit_options, SpaceManager.RESOURCE_COLLECTOR_STATION_CLASS_ID), "body without deposits should not offer resource collector station", failures)
	_expect(SpaceManager.request_build_order_for_body(builder.unit_id, "sys_alpha", star_context, SpaceManager.BASIC_STATION_CLASS_ID).is_empty(), "nonmatching body tags should reject basic station on star", failures)
	_expect(SpaceManager.request_build_order_for_body(builder.unit_id, "sys_alpha", planet_context, SpaceManager.STELLAR_STATION_CLASS_ID).is_empty(), "nonmatching body tags should reject stellar station on planet", failures)
	_test_preview_build_menu_signal(builder.unit_id, planet_context, failures)

	var project_id := SpaceManager.request_build_order_for_body(builder.unit_id, "sys_alpha", planet_context, SpaceManager.BASIC_STATION_CLASS_ID, {
		"display_name": "Anchor Mason",
	})
	_expect(not project_id.is_empty(), "builder should accept station build order", failures)
	_expect(SpaceManager.is_unit_constructing(builder.unit_id), "builder should be marked constructing", failures)
	_expect(not SpaceManager.issue_unit_move(builder.unit_id, Vector3(4.0, 0.0, 0.0)), "builder should reject movement while constructing", failures)
	builder = SpaceManager.get_unit(builder.unit_id)
	_expect(builder != null and builder.has_active_movement(), "builder should move to the build site before construction starts", failures)
	var second_builder := SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, "empire_builder", "sys_alpha", {
		"display_name": "ISS Trowel",
		"local_position": Vector3(4.0, 0.0, 0.0),
	})
	_expect(second_builder != null, "second builder should spawn", failures)
	if second_builder != null:
		_expect(SpaceManager.request_build_order_for_body(second_builder.unit_id, "sys_alpha", planet_context, SpaceManager.BASIC_STATION_CLASS_ID).is_empty(), "body max_active_projects should block another project on the same body", failures)

	var project := SpaceManager.get_construction_project(project_id)
	_expect(int(project.get("days_total", 0)) == 60, "construction project should keep 60-day total", failures)
	_expect(int(project.get("days_remaining", 0)) == 60, "construction project should begin with 60 days remaining", failures)
	_expect(str(project.get("construction_state", "")) == SpaceManager.CONSTRUCTION_STATE_MOVING_TO_SITE, "construction project should begin by moving builder to site", failures)
	_expect(str(project.get("target_body_id", "")) == "planet_00", "construction project should store target body id", failures)
	_expect(str(project.get("target_body_type", "")) == "planet", "construction project should store target body type", failures)
	_expect(str(project.get("target_body_name", "")) == "Alpha I", "construction project should store target body name", failures)
	_expect(SpaceManager.build_system_presence("sys_alpha").get("construction_project_count", 0) == 1, "system presence should include construction project", failures)

	var snapshot := SpaceManager.build_snapshot()
	_expect(snapshot.has("construction_projects"), "snapshot should emit construction_projects", failures)
	SpaceManager.load_snapshot(snapshot, true)
	_expect(not SpaceManager.get_construction_project(project_id).is_empty(), "snapshot load should restore construction project", failures)
	_expect(str(SpaceManager.get_construction_project(project_id).get("target_body_id", "")) == "planet_00", "snapshot load should preserve target body id", failures)
	_expect(str(SpaceManager.get_construction_project(project_id).get("construction_state", "")) == SpaceManager.CONSTRUCTION_STATE_MOVING_TO_SITE, "snapshot load should preserve moving-to-site state", failures)
	_expect(SpaceManager.is_unit_constructing(builder.unit_id), "snapshot load should restore builder construction index", failures)

	SpaceManager._on_sim_day_tick({})
	_expect(int(SpaceManager.get_construction_project(project_id).get("days_remaining", 0)) == 60, "construction timer should not tick while builder is travelling to site", failures)
	_advance_until_building(project_id, 120, failures)

	for _day in range(59):
		SpaceManager._on_sim_day_tick({})
	_expect(SpaceManager.get_unit_ids_of_class(SpaceManager.BASIC_STATION_CLASS_ID).is_empty(), "station should not complete before 60 days", failures)
	_expect(int(SpaceManager.get_construction_project(project_id).get("days_remaining", 0)) == 1, "project should have one day remaining after 59 ticks", failures)

	SpaceManager._on_sim_day_tick({})
	var station_ids := SpaceManager.get_unit_ids_of_class(SpaceManager.BASIC_STATION_CLASS_ID)
	_expect(station_ids.size() == 1, "station should complete after 60 days", failures)
	_expect(SpaceManager.get_construction_project(project_id).is_empty(), "completed project should be removed", failures)
	_expect(not SpaceManager.is_unit_constructing(builder.unit_id), "builder should be free after project completion", failures)
	if not station_ids.is_empty():
		var station := SpaceManager.get_unit(station_ids[0])
		_expect(station != null and station.display_name == "Anchor Mason", "completed station should use requested display name", failures)
		_expect(station != null and station.owner_empire_id == "empire_builder", "completed station should inherit builder owner", failures)
		_expect(station != null and station.current_system_id == "sys_alpha", "completed station should spawn in builder system", failures)
		_expect(station != null and str(station.metadata.get("target_body_id", "")) == "planet_00", "completed station should keep target body metadata", failures)

	var collector_builder := SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, "empire_builder", "sys_alpha", {
		"display_name": "ISS Harvester",
		"local_position": Vector3(22.0, 0.0, 0.0),
	})
	_expect(collector_builder != null, "collector builder should spawn", failures)
	if collector_builder != null:
		var collector_project_id := SpaceManager.request_build_order_for_body(
			collector_builder.unit_id,
			"sys_alpha",
			deposit_context,
			SpaceManager.RESOURCE_COLLECTOR_STATION_CLASS_ID
		)
		_expect(not collector_project_id.is_empty(), "body with deposits should accept collector build order", failures)
		var duplicate_builder := SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, "empire_builder", "sys_alpha", {
			"display_name": "ISS Duplicate",
			"local_position": Vector3(26.0, 0.0, 0.0),
		})
		_expect(duplicate_builder != null, "duplicate collector builder should spawn", failures)
		if duplicate_builder != null:
			var duplicate_collector_options := SpaceManager.get_build_options_for_body(duplicate_builder.unit_id, "sys_alpha", deposit_context)
			_expect(not _options_have_class(duplicate_collector_options, SpaceManager.RESOURCE_COLLECTOR_STATION_CLASS_ID), "active collector project should block duplicate collector options", failures)

	SpaceManager.reset_runtime_state(true)


func _build_body_context(body_id: String, body_type: String, body_name: String, local_position: Vector3, allowed_tags: Array) -> Dictionary:
	return {
		"body_id": body_id,
		"body_type": body_type,
		"body_name": body_name,
		"local_position": local_position,
		"size": 2.0,
		"buildable_component": {
			"body_type": body_type,
			"allowed_build_tags": allowed_tags,
			"max_active_projects": 1,
		},
	}


func _options_have_class(options: Array, class_id: String) -> bool:
	for option in options:
		if str(option.get("class_id", "")) == class_id:
			return true
	return false


func _test_preview_build_menu_signal(builder_unit_id: String, body_context: Dictionary, failures: Array[String]) -> void:
	var preview := StarSystemPreview.new()
	preview._current_system_details = {"id": "sys_alpha"}
	preview.set_external_selected_builder_unit_id(builder_unit_id)

	var selectable := SystemSelectableComponent.new()
	selectable.context = body_context.duplicate(true)
	var requests: Array[Dictionary] = []
	preview.build_menu_requested.connect(func(emitted_builder_unit_id: String, emitted_body_context: Dictionary, options: Array[Dictionary], screen_position: Vector2) -> void:
		requests.append({
			"builder_unit_id": emitted_builder_unit_id,
			"body_context": emitted_body_context.duplicate(true),
			"options": options.duplicate(true),
			"screen_position": screen_position,
		})
	)

	_expect(preview._try_emit_build_menu(selectable, Vector2(120.0, 80.0)), "preview should emit build menu for selected builder and buildable body", failures)
	_expect(requests.size() == 1, "preview should emit exactly one build-menu request", failures)
	if not requests.is_empty():
		var request := requests[0]
		_expect(str(request.get("builder_unit_id", "")) == builder_unit_id, "preview build-menu request should preserve builder unit id", failures)
		_expect(str(request.get("body_context", {}).get("body_id", "")) == str(body_context.get("body_id", "")), "preview build-menu request should preserve body context", failures)
		_expect(_options_have_class(request.get("options", []), SpaceManager.BASIC_STATION_CLASS_ID), "preview build-menu request should include valid build options", failures)

	var unbuildable_selectable := SystemSelectableComponent.new()
	unbuildable_selectable.context = {
		"body_id": "planet_unbuildable",
		"body_type": "planet",
	}
	_expect(not preview._try_emit_build_menu(unbuildable_selectable, Vector2.ZERO), "preview should fall back when a body has no buildable component", failures)
	_expect(str(preview.get_selected_command_entity().get("record_id", "")) == builder_unit_id, "preview should keep external builder command entity for empty-space movement fallback", failures)
	preview.free()


func _advance_until_building(project_id: String, max_days: int, failures: Array[String]) -> void:
	for _day in range(max_days):
		var project := SpaceManager.get_construction_project(project_id)
		if project.is_empty():
			failures.append("construction project should still exist while builder travels")
			return
		if str(project.get("construction_state", "")) == SpaceManager.CONSTRUCTION_STATE_BUILDING:
			_expect(int(project.get("days_remaining", 0)) == 60, "construction timer should start at full duration when builder arrives", failures)
			return
		SpaceManager._on_sim_day_tick({})
	failures.append("builder should arrive and start construction timer")




func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
