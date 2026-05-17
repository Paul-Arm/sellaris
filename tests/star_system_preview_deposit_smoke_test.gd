extends Node

const PREVIEW_SCENE: PackedScene = preload("res://scene/StarSystem/StarSystemPreview.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("Star system preview deposit smoke test passed.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()

	var preview := PREVIEW_SCENE.instantiate() as StarSystemPreview
	add_child(preview)
	await get_tree().process_frame

	var system_details := _system_details(true)
	preview.set_system_details(system_details)
	await get_tree().process_frame
	var deposit_label := preview.find_child("DepositLabel_planet_deposit", true, false) as Label3D
	_expect(deposit_label != null, "explored system preview should render a deposit label", failures)
	_expect(deposit_label != null and deposit_label.text.find("Matter +50") >= 0, "deposit label should include fixed deposit amount", failures)
	_expect(preview._select_selectable_by_id("planet:planet_deposit"), "preview should select the deposit planet", failures)
	preview.set_system_details(_system_details(true))
	await get_tree().process_frame
	_expect(preview.get_selected_selection_id() == "planet:planet_deposit", "same-system refresh should preserve selected body", failures)
	preview.set_system_details(_system_details(true, "sys_beta"))
	await get_tree().process_frame
	_expect(preview.get_selected_selection_id().is_empty(), "system switch should not restore a matching local body id", failures)

	preview.set_system_details(_system_details(false))
	await get_tree().process_frame
	deposit_label = preview.find_child("DepositLabel_planet_deposit", true, false) as Label3D
	_expect(deposit_label == null, "redacted system preview should not render deposit labels", failures)

	preview.free()


func _system_details(has_full_intel: bool, system_id: String = "sys_alpha") -> Dictionary:
	return {
		"id": system_id,
		"name": "Alpha" if system_id == "sys_alpha" else "Beta",
		"generated_seed": 7,
		"has_full_intel": has_full_intel,
		"stars": [],
		"orbitals": [{
			"id": "planet_deposit",
			"name": "Deposit World",
			"type": "planet",
			"size": 1.6,
			"orbit_radius": 18.0,
			"orbit_angle": 0.4,
			"resource_deposit_component": {
				"mode": "fixed",
				"deposits": [{"resource_id": "matter", "milliunits": 50000}],
			},
		}],
		"space_renderables": {},
	}


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
