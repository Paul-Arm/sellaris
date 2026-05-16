extends Node

const PANEL_SCRIPT: Script = preload("res://scene/StarSystem/SystemBodyDetailsPanel.gd")


func _ready() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("System body details panel smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()

	var panel = PANEL_SCRIPT.new()
	add_child(panel)
	await get_tree().process_frame

	var planet_record := {
		"id": "alpha_prime",
		"name": "Alpha Prime",
		"type": "planet",
		"size": 2.1,
		"orbit_radius": 34.0,
		"habitability_points": 72,
		"resource_richness_points": 66,
		"is_colonizable": true,
		"metadata": {"planet_visual": {"kind": "landmass", "has_atmosphere": true}},
	}
	var system_details := {
		"id": "sys_alpha",
		"name": "Alpha",
		"generated_seed": 7,
		"anomaly_risk": 0.23,
		"system_summary": {"anomaly_risk": 0.23},
		"orbitals": [planet_record],
		"stars": [],
	}
	var planet_selection := {
		"selection_id": "planet:alpha_prime",
		"selection_kind": "planet",
		"title": "Alpha Prime",
		"subtitle": "Planet",
		"context": {
			"system_id": "sys_alpha",
			"body_id": "alpha_prime",
			"body_type": "planet",
			"body_name": "Alpha Prime",
			"body_record": planet_record,
			"host_kind": ColonyRuntime.HOST_KIND_ORBITAL,
			"host_id": "alpha_prime",
		},
	}

	panel.open_details(planet_selection, system_details, {
		"show_colonize": true,
		"can_colonize": true,
	})
	await get_tree().process_frame
	_expect(panel.visible, "panel should be visible after opening planet details", failures)
	_expect(_label_text(panel, "TitleLabel") == "Alpha Prime", "panel title should show selected body name", failures)
	var colonize_button := panel.find_child("ColonizeButton", true, false) as Button
	_expect(colonize_button != null and colonize_button.visible and not colonize_button.disabled, "colonize button should be enabled for free habitable planet", failures)
	var resource_chips := panel.find_child("ResourceChips", true, false) as HFlowContainer
	_expect(resource_chips != null and resource_chips.get_child_count() > 0, "resource chips should be populated", failures)

	var station_record := {
		"unit_id": "station_alpha",
		"display_name": "Station Alpha",
		"class_display_name": "Outpost",
		"owner_name": "Empire Alpha",
		"current_hull_points": 900.0,
		"max_hull_points": 1000.0,
	}
	var station_selection := {
		"selection_id": "station:station_alpha",
		"selection_kind": "station",
		"title": "Station Alpha",
		"subtitle": "Station / Empire Alpha",
		"context": {
			"system_id": "sys_alpha",
			"body_id": "station_alpha",
			"body_type": "station",
			"body_name": "Station Alpha",
			"body_record": station_record,
			"host_kind": ColonyRuntime.HOST_KIND_SPACE_UNIT,
			"host_id": "station_alpha",
		},
	}
	panel.open_details(station_selection, system_details, {"show_colonize": false})
	await get_tree().process_frame
	_expect(_label_text(panel, "TitleLabel") == "Station Alpha", "selection switch should refresh panel title", failures)
	_expect(colonize_button != null and not colonize_button.visible, "station details should not show colonize button", failures)

	var close_state := {"emitted": false}
	panel.close_requested.connect(func() -> void:
		close_state["emitted"] = true
	)
	panel.close()
	await get_tree().process_frame
	_expect(not panel.visible, "panel close should hide details", failures)
	_expect(bool(close_state.get("emitted", false)), "panel close should emit close_requested", failures)
	panel.free()


func _label_text(root: Node, label_name: String) -> String:
	var label := root.find_child(label_name, true, false) as Label
	if label == null:
		return ""
	return label.text


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
