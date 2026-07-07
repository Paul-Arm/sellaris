extends Node

const SYSTEM_VIEW_SCENE: PackedScene = preload("res://scene/StarSystem/SystemView.tscn")

const EMPIRE_ID := "empire_shipset"
const SYSTEM_ID := "sys_shipset"


class TestShipSet:
	static func build_mesh(visual_key: String) -> Mesh:
		if visual_key == "corvette":
			return BoxMesh.new()
		return null


func _ready() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("Ship set smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	_run_registry_checks(failures)
	_run_builtin_glb_set_checks(failures)
	_run_set_switching_checks(failures)
	await _run_renderer_checks(failures)


func _run_registry_checks(failures: Array[String]) -> void:
	SpaceManager.reset_runtime_state(true)

	# Every visual key resolves to a mesh, and meshes are cached.
	for visual_key in ["corvette", "science", "builder", "ship", "station", "stellar_station", "collector_station"]:
		var mesh := ShipSetRegistry.get_mesh(visual_key)
		_expect(mesh != null and mesh.get_surface_count() > 0, "default set should build a mesh for %s" % visual_key, failures)
		_expect(ShipSetRegistry.get_mesh(visual_key) == mesh, "meshes should be cached per set and key", failures)

	# Class resolution: known ids, metadata override, kind fallback.
	_expect(
		ShipSetRegistry.resolve_visual_key_for_class(SpaceManager.get_unit_class(SpaceManager.CORVETTE_CLASS_ID)) == "corvette",
		"corvette class should resolve to the corvette model",
		failures
	)
	_expect(
		ShipSetRegistry.resolve_visual_key_for_class(SpaceManager.get_unit_class(SpaceManager.SCIENCE_SHIP_CLASS_ID)) == "science",
		"science ship class should resolve to the science model",
		failures
	)
	_expect(
		ShipSetRegistry.resolve_visual_key_for_class(SpaceManager.get_unit_class(SpaceManager.BUILDER_SHIP_CLASS_ID)) == "builder",
		"builder ship class should resolve to the builder model",
		failures
	)
	_expect(
		ShipSetRegistry.resolve_visual_key_for_class(SpaceManager.get_unit_class(SpaceManager.RESOURCE_COLLECTOR_STATION_CLASS_ID)) == "collector_station",
		"collector station class should resolve to the collector model",
		failures
	)

	SpaceManager.register_unit_class_from_data({
		"class_id": "shipset_custom",
		"display_name": "Custom Visual",
		"unit_kind": "ship",
		"category": "combat",
		"max_hull_points": 100,
		"mobility_component": {"cruise_speed": 5.0},
		"metadata": {"visual_key": "science"},
	}, true)
	_expect(
		ShipSetRegistry.resolve_visual_key_for_class(SpaceManager.get_unit_class("shipset_custom")) == "science",
		"metadata visual_key should override the class mapping",
		failures
	)

	SpaceManager.register_unit_class_from_data({
		"class_id": "shipset_unknown_station",
		"display_name": "Unknown Station",
		"unit_kind": "station",
		"category": "station",
		"max_hull_points": 500,
	}, true)
	_expect(
		ShipSetRegistry.resolve_visual_key_for_class(SpaceManager.get_unit_class("shipset_unknown_station")) == "station",
		"unknown station classes should fall back to the station model",
		failures
	)


func _run_builtin_glb_set_checks(failures: Array[String]) -> void:
	var registered := ShipSetRegistry.get_registered_set_ids()
	for set_id in ["forge", "tidal", "vanguard", "void"]:
		_expect(registered.has(set_id), "builtin set %s should be registered" % set_id, failures)

	for set_id in ["forge", "tidal", "vanguard", "void"]:
		_expect(ShipSetRegistry.set_active_set_id(set_id), "builtin set %s should activate" % set_id, failures)
		for visual_key in ["corvette", "destroyer", "cruiser", "battleship", "science", "builder", "ship", "station", "stellar_station", "collector_station"]:
			var mesh := ShipSetRegistry.get_mesh(visual_key)
			var label := "%s/%s" % [set_id, visual_key]
			_expect(mesh != null and mesh.get_surface_count() > 0, "%s should resolve to a mesh with surfaces" % label, failures)
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			var material := mesh.surface_get_material(0) as BaseMaterial3D
			_expect(material != null, "%s should carry its own material (textured set)" % label, failures)
			if material == null:
				continue
			_expect(material.vertex_color_use_as_albedo, "%s material should enable vertex color tint for owner colors" % label, failures)
			_expect(material.albedo_texture != null, "%s material should reference the set's albedo texture" % label, failures)

	_expect(ShipSetRegistry.set_active_set_id(ShipSetRegistry.DEFAULT_SET_ID), "switching back to the default set after builtin checks should work", failures)


func _run_set_switching_checks(failures: Array[String]) -> void:
	_expect(not ShipSetRegistry.set_active_set_id("missing_set"), "unregistered set ids should be rejected", failures)

	_expect(ShipSetRegistry.register_set("test_set", TestShipSet), "custom ship set script should register", failures)
	_expect(ShipSetRegistry.get_registered_set_ids().has("test_set"), "registered sets should be listed", failures)
	_expect(ShipSetRegistry.set_active_set_id("test_set"), "registered set should activate", failures)
	var custom_mesh := ShipSetRegistry.get_mesh("corvette")
	_expect(custom_mesh is BoxMesh, "active set should provide its own corvette mesh", failures)
	_expect(ShipSetRegistry.get_mesh("corvette") == custom_mesh, "custom set meshes should be cached", failures)
	var fallback_mesh := ShipSetRegistry.get_mesh("science")
	_expect(fallback_mesh != null and fallback_mesh is not BoxMesh, "missing keys should fall back to the default set", failures)
	_expect(ShipSetRegistry.set_active_set_id(ShipSetRegistry.DEFAULT_SET_ID), "switching back to the default set should work", failures)


func _run_renderer_checks(failures: Array[String]) -> void:
	SpaceManager.reset_runtime_state(true)
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {"unit_id": "set_corvette", "local_position": Vector3(4.0, 0.0, 0.0)})
	SpaceManager.spawn_unit(SpaceManager.SCIENCE_SHIP_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {"unit_id": "set_science", "local_position": Vector3(6.0, 0.0, 0.0)})
	SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {"unit_id": "set_builder", "local_position": Vector3(8.0, 0.0, 0.0)})
	SpaceManager.spawn_unit(SpaceManager.BASIC_STATION_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {"unit_id": "set_station", "local_position": Vector3(10.0, 0.0, 0.0)})
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {"unit_id": "set_fleet_a", "local_position": Vector3(12.0, 0.0, 0.0)})
	SpaceManager.spawn_unit(SpaceManager.CORVETTE_CLASS_ID, EMPIRE_ID, SYSTEM_ID, {"unit_id": "set_fleet_b", "local_position": Vector3(13.0, 0.0, 0.0)})
	SpaceManager.create_fleet(EMPIRE_ID, SYSTEM_ID, PackedStringArray(["set_fleet_a", "set_fleet_b"]), {"display_name": "Set Fleet"})

	var system_view := SYSTEM_VIEW_SCENE.instantiate()
	add_child(system_view)
	await get_tree().process_frame

	system_view.show_system({
		"id": SYSTEM_ID,
		"name": "Shipset System",
		"generated_seed": 7,
		"has_full_intel": true,
		"stars": [],
		"orbitals": [],
		"system_summary": {},
		"star_profile": {},
		"space_renderables": SpaceManager.build_system_renderables(SYSTEM_ID),
	}, 0)
	await get_tree().process_frame

	var effects_root: Node3D = system_view.preview.get_runtime_effects_root()
	var marker_keys: Dictionary = {}
	var total_model_instances := 0
	for child in effects_root.get_children():
		if child is MultiMeshInstance3D and str(child.name).begins_with("ModelMarker_"):
			var marker := child as MultiMeshInstance3D
			var key := str(child.name).trim_prefix("ModelMarker_").rsplit("_", true, 1)[0]
			marker_keys[key] = int(marker_keys.get(key, 0)) + (marker.multimesh.instance_count if marker.multimesh != null else 0)
			if marker.multimesh != null:
				total_model_instances += marker.multimesh.instance_count

	_expect(int(marker_keys.get("corvette", 0)) == 3, "corvette model group should hold the lone corvette and both fleet members, got %d" % int(marker_keys.get("corvette", 0)), failures)
	_expect(int(marker_keys.get("science", 0)) == 1, "science model group should hold the science ship", failures)
	_expect(int(marker_keys.get("builder", 0)) == 1, "builder model group should hold the builder ship", failures)
	_expect(int(marker_keys.get("station", 0)) == 1, "station model group should hold the station", failures)
	_expect(total_model_instances == 6, "all six units should be instanced as models, got %d" % total_model_instances, failures)

	system_view.queue_free()
	await get_tree().process_frame
	SpaceManager.reset_runtime_state(true)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
