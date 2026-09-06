extends Node

var view: SystemView
var move_commands := 0

func _ready() -> void:
	SettingsManager.set_design_variant("clean", false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	view = load("res://scene/StarSystem/SystemView.tscn").instantiate()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.show_system(preload("res://tests/design_variants_test.gd").fixture(), 3)
	view.preview.camera_rig.edge_pan_speed_multiplier = 0.0
	view.preview.movement_order_requested.connect(func(_selection, _target): move_commands += 1)
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(window_size)
		await _frames()
		var center := Vector2(window_size.x * 0.5 - 105, window_size.y * 0.5)
		await _motion(center)
		var distance: float = view.preview.camera_rig.get("_camera_distance")
		await _button(center, MOUSE_BUTTON_WHEEL_UP, true)
		assert(view.preview.camera_rig.get("_camera_distance") < distance, "Wheel must reach the system through GUI input")
		var fleet_selection := SystemSelectableComponent.new()
		fleet_selection.selection_id = "fleet:pointer-test"
		fleet_selection.selection_kind = "fleet"
		view.preview.set("_selected_selectable", fleet_selection)
		var commands_before := move_commands
		var yaw: float = view.preview.camera_rig.get("_yaw_degrees")
		await _button(center, MOUSE_BUTTON_RIGHT, true)
		await _motion(center + Vector2(40, 12), Vector2(40, 12))
		await _button(center + Vector2(40, 12), MOUSE_BUTTON_RIGHT, false)
		assert(not is_equal_approx(yaw, view.preview.camera_rig.get("_yaw_degrees")), "Right drag must rotate")
		assert(move_commands == commands_before, "Rotating must not issue a move command")
		await _button(center, MOUSE_BUTTON_RIGHT, true)
		await _button(center, MOUSE_BUTTON_RIGHT, false)
		assert(move_commands == commands_before + 1, "Right click issues exactly one command")
		var position := view.preview.camera_rig.position
		await _button(center, MOUSE_BUTTON_MIDDLE, true)
		await _motion(center + Vector2(30, 0), Vector2(30, 0))
		await _button(Vector2(window_size.x - 30, 75), MOUSE_BUTTON_MIDDLE, false)
		assert(not position.is_equal_approx(view.preview.camera_rig.position), "Middle drag must pan")
		assert(not view.preview.camera_rig.is_middle_dragging(), "Release over UI must stop drag")
		view.preview.camera_rig.configure_view(Vector3.ZERO, 100, -34, 0)
		await _frames()
		var field := view.preview.get_node("Pivot/Bodies/GravityFieldMap") as GravityFieldMap
		var body: Dictionary = field.body_records[0]
		var point := view.preview.camera.unproject_position(view.preview.pivot.to_global(GravityFieldMap.visual_position(body, field.body_records)))
		await _motion(point)
		await _button(point, MOUSE_BUTTON_LEFT, true)
		await _button(point, MOUSE_BUTTON_LEFT, false)
		assert(view.preview.get_selected_selection_id().ends_with(str(body["id"])), "Real window click must select a body")
		var panel: Control = view.get("_body_details_panel").get("_panel")
		assert(panel.get_global_rect().end.x <= window_size.x + 1 and panel.get_global_rect().end.y <= window_size.y + 1, "Inspector must fit window")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tools/screenshots/clean_ui_%d.png" % window_size.x)
		view.preview.clear_selection()
		view.get("_info_toggle").button_pressed = true
		await _frames()
		var summary: Control = view.get_node("RightPanel")
		assert(summary.get_global_rect().end.y <= window_size.y, "System info must fit window")
		view.get("_info_toggle").button_pressed = false
		print("PASS: GUI wheel, rotate, pan, release, selection and inspector at ", window_size)
	get_tree().quit()

func _frames() -> void:
	for frame in range(4): await get_tree().process_frame

func _motion(position: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	Input.parse_input_event(event)
	await _frames()

func _button(position: Vector2, index: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	await _frames()
