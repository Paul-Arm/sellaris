extends SceneTree

const DRAWER_SCRIPT: Script = preload("res://scene/UI/EmpireCommandDrawer.gd")
const ROW_SCRIPT: Script = preload("res://scene/UI/EmpireListActionRow.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	await _run(failures)
	if failures.is_empty():
		print("Empire command drawer smoke test passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _run(failures: Array[String]) -> void:
	var drawer := DRAWER_SCRIPT.new() as Control
	root.add_child(drawer)
	await process_frame

	drawer.call("set_categories", [
		{"id": "anomalies", "title": "Anomalien / Situationen"},
		{"id": "diplomacy", "title": "Diplomatie"},
	])
	drawer.call("set_anomaly_entries", [])
	await process_frame
	var empty_label := drawer.find_child("EmptyLabel", true, false) as Label
	_expect(empty_label != null and empty_label.visible, "empty anomaly state should be visible without entries", failures)

	var signal_state: Dictionary = {"entry": {}}
	drawer.connect("anomaly_open_requested", func(entry: Dictionary) -> void:
		signal_state["entry"] = entry.duplicate(true)
	)
	drawer.call("set_anomaly_entries", [{
		"id": "anom_alpha_vault",
		"anomaly_id": "anom_alpha_vault",
		"system_id": "sys_alpha",
		"title": "Stiller Tresor",
		"status": "discovered",
		"meta": "Alpha  |  Alpha I  |  45 Tage Forschung",
		"action_label": "Oeffnen",
		"action_enabled": true,
	}])
	await process_frame

	var rows := _find_rows(drawer)
	_expect(rows.size() == 1, "drawer should create one reusable action row for one anomaly", failures)
	if rows.size() == 1:
		rows[0].emit_signal("action_requested", {"system_id": "sys_alpha", "anomaly_id": "anom_alpha_vault"})
		var emitted_entry: Dictionary = signal_state.get("entry", {})
		_expect(str(emitted_entry.get("system_id", "")) == "sys_alpha", "row action should bubble through drawer signal", failures)

	drawer.call("set_active_category", "diplomacy")
	await process_frame
	var placeholder := _find_visible_placeholder(drawer)
	_expect(placeholder != null and placeholder.text.contains("Diplomatie"), "placeholder category should be switchable", failures)

	drawer.queue_free()


func _find_rows(root_node: Node) -> Array[Control]:
	var result: Array[Control] = []
	_collect_rows(root_node, result)
	return result


func _collect_rows(node: Node, result: Array[Control]) -> void:
	if node.get_script() == ROW_SCRIPT:
		result.append(node as Control)
	for child in node.get_children():
		_collect_rows(child, result)


func _find_visible_placeholder(root_node: Node) -> Label:
	return root_node.find_child("PlaceholderLabel", true, false) as Label


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
