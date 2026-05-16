extends Node

const PREVIEW_SCENE: PackedScene = preload("res://scene/StarSystem/StarSystemPreview.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("Construction progress preview smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	SpaceManager.reset_runtime_state(true)

	var builder := SpaceManager.spawn_unit(SpaceManager.BUILDER_SHIP_CLASS_ID, "empire_builder", "sys_alpha", {
		"unit_id": "builder_progress",
		"display_name": "ISS Progress",
		"local_position": Vector3(22.0, 0.0, 0.0),
	})
	_expect(builder != null, "builder should spawn", failures)
	if builder == null:
		return

	var body_context := {
		"body_id": "planet_progress",
		"body_type": "planet",
		"body_name": "Progress World",
		"local_position": Vector3(18.0, 0.0, 0.0),
		"size": 2.0,
		"buildable_component": {
			"body_type": "planet",
			"allowed_build_tags": ["orbital_station"],
			"max_active_projects": 1,
		},
	}
	var project_id := SpaceManager.request_build_order_for_body(
		builder.unit_id,
		"sys_alpha",
		body_context,
		SpaceManager.BASIC_STATION_CLASS_ID,
		{"local_position": Vector3(22.0, 0.0, 0.0)}
	)
	_expect(not project_id.is_empty(), "station build order should be accepted", failures)
	if project_id.is_empty():
		SpaceManager.reset_runtime_state(true)
		return

	var project := SpaceManager.get_construction_project(project_id)
	_expect(str(project.get("construction_state", "")) == SpaceManager.CONSTRUCTION_STATE_BUILDING, "nearby builder should start building immediately", failures)
	SpaceManager._on_sim_day_tick({})

	var renderables := SpaceManager.build_system_renderables("sys_alpha")
	var projects: Array = renderables.get("construction_projects", [])
	_expect(projects.size() == 1, "system renderables should include construction project", failures)
	if not projects.is_empty():
		var renderable: Dictionary = projects[0]
		_expect(float(renderable.get("progress_ratio", 0.0)) > 0.0, "construction renderable should expose positive progress", failures)
		_expect(int(renderable.get("progress_percent", 0)) > 0, "construction renderable should expose progress percent", failures)

	var preview := PREVIEW_SCENE.instantiate() as StarSystemPreview
	add_child(preview)
	await get_tree().process_frame
	preview.set_system_details({
		"id": "sys_alpha",
		"name": "Alpha",
		"generated_seed": 7,
		"has_full_intel": true,
		"stars": [],
		"orbitals": [],
		"space_renderables": renderables,
	})
	await get_tree().process_frame

	var label := preview.find_child("ConstructionLabel_%s" % project_id, true, false) as Label3D
	_expect(label != null and label.text.begins_with("Bau "), "preview should render construction progress label", failures)
	var particles := preview.find_child("ConstructionParticles", true, false) as MultiMeshInstance3D
	_expect(particles != null and particles.multimesh != null and particles.multimesh.instance_count > 0, "preview should render construction particle stream", failures)
	_expect(_has_selectable(preview, "construction:%s" % project_id), "construction site should be selectable", failures)

	preview.free()
	SpaceManager.reset_runtime_state(true)


func _has_selectable(preview: StarSystemPreview, selection_id: String) -> bool:
	for selectable in preview._selectables:
		if selectable.selection_id == selection_id:
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
