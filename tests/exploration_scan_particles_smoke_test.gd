extends Node

const PREVIEW_SCENE: PackedScene = preload("res://scene/StarSystem/StarSystemPreview.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("Exploration scan particles smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	SpaceManager.reset_runtime_state(true)
	var ship := SpaceManager.spawn_unit(SpaceManager.SCIENCE_SHIP_CLASS_ID, "empire_explorer", "sys_alpha", {
		"unit_id": "science_particles",
		"display_name": "ISS Lens",
		"local_position": Vector3.ZERO,
	})
	_expect(ship != null, "test science ship should spawn", failures)
	if ship == null:
		return

	var details := _build_system_details()
	var order_id := SpaceManager.request_explore_system(ship.unit_id, "sys_alpha", details, 0, {"galaxy_seed": 91})
	_expect(not order_id.is_empty(), "exploration order should start for particle smoke test", failures)
	for _day in range(12):
		var order: Dictionary = SpaceManager.get_exploration_order(order_id)
		if bool(order.get("is_scanning", false)):
			break
		SpaceManager._on_sim_day_tick({})
	var active_order: Dictionary = SpaceManager.get_exploration_order(order_id)
	_expect(bool(active_order.get("is_scanning", false)), "exploration should enter scanning state", failures)

	var preview := PREVIEW_SCENE.instantiate() as StarSystemPreview
	add_child(preview)
	await get_tree().process_frame
	details["space_renderables"] = SpaceManager.build_system_renderables("sys_alpha")
	preview.set_system_details(details)
	await get_tree().process_frame

	var particles := preview.find_child("ExplorationScanParticles", true, false) as MultiMeshInstance3D
	_expect(particles != null and particles.multimesh != null and particles.multimesh.instance_count > 0, "preview should render exploration scan particles", failures)
	preview.free()
	SpaceManager.reset_runtime_state(true)


func _build_system_details() -> Dictionary:
	return {
		"id": "sys_alpha",
		"name": "Alpha",
		"generated_seed": 91,
		"has_full_intel": true,
		"owner_empire_id": "empire_explorer",
		"owner_name": "Explorers",
		"active_empire_id": "empire_explorer",
		"system_summary": {
			"star_count": 1,
			"star_class": "G",
			"special_type": "none",
			"planet_count": 1,
			"asteroid_belt_count": 0,
			"structure_count": 0,
			"ruin_count": 0,
			"colonizable_worlds": 0,
			"habitable_worlds": 0,
			"anomaly_risk": 0.0,
		},
		"star_profile": {
			"star_class": "G",
			"star_count": 1,
			"special_type": "none",
		},
		"stars": [{
			"id": "alpha_star",
			"name": "Alpha",
			"type": "star",
			"star_class": "G",
			"color": Color(1.0, 0.86, 0.28, 1.0),
			"scale": 1.0,
			"is_primary": true,
			"orbit_radius": 0.0,
			"orbit_angle": 0.0,
		}],
		"orbitals": [{
			"id": "alpha_i",
			"name": "Alpha I",
			"type": "planet",
			"size": 1.2,
			"orbit_radius": 10.0,
			"orbit_angle": 0.35,
			"vertical_offset": 0.0,
			"color": Color(0.38, 0.62, 0.82, 1.0),
			"metadata": {
				"planet_visual": {
					"kind": "landmass",
					"pixels": 800.0,
					"has_atmosphere": true,
				},
			},
		}],
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
