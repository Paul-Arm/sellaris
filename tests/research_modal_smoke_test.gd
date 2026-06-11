extends Node

## Instantiates the research modal against the live autoloads, verifies the
## domain columns build, and picks a project through the UI button.
## Preloading the game scene script also compiles the full UI wiring chain.

const GAME_SCENE_SCRIPT := preload("res://scene/game/GameScene.gd")
const GAME_SCENE_UI_CONTROLLER_SCRIPT := preload("res://scene/game/GameSceneUiController.gd")
const RESEARCH_MODAL_SCRIPT := preload("res://scene/game/ResearchModal.gd")

const EMPIRE_ID := "empire_modal"


func _ready() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("Research modal smoke test passed.")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _run(failures: Array[String]) -> void:
	SpaceManager.reset_runtime_state(true)
	EconomyManager.clear_runtime_state(false)
	EconomyManager.load_registry()
	EconomyManager.bootstrap([EMPIRE_ID], {})
	SpaceManager.bootstrap_empires([EMPIRE_ID])
	ResearchManager.reload_catalog()
	ResearchManager.bootstrap([EMPIRE_ID], 777)

	var modal := RESEARCH_MODAL_SCRIPT.new() as Control
	add_child(modal)
	await get_tree().process_frame

	modal.call("open", EMPIRE_ID)
	await get_tree().process_frame

	_expect(modal.visible, "modal should be visible after open", failures)
	var columns := modal.find_child("DomainColumns", true, false)
	_expect(columns != null, "modal should build the domain columns container", failures)
	if columns != null:
		_expect(columns.get_child_count() == 3, "modal should show one column per domain (got %d)" % columns.get_child_count(), failures)

	var pick_buttons: Array[Node] = modal.find_children("PickButton_*", "Button", true, false)
	_expect(pick_buttons.size() >= 9, "modal should offer pick buttons for the drafts (got %d)" % pick_buttons.size(), failures)

	if not pick_buttons.is_empty():
		var button := pick_buttons[0] as Button
		var tech_id := button.name.trim_prefix("PickButton_")
		button.pressed.emit()
		await get_tree().process_frame
		var active_total := 0
		for domain_id in ResearchManager.get_domain_ids():
			for project_variant in ResearchManager.get_active_projects(EMPIRE_ID, domain_id):
				active_total += 1
				_expect(str((project_variant as Dictionary).get("tech_id", "")) == tech_id, "started project should match the pressed button", failures)
		_expect(active_total == 1, "pressing a pick button should start exactly one project", failures)

	modal.call("close")
	_expect(not modal.visible, "modal should hide on close", failures)

	modal.queue_free()
	await get_tree().process_frame


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
