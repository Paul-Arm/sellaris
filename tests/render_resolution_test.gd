extends Node

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var view: SystemView = load("res://scene/StarSystem/SystemView.tscn").instantiate()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SettingsManager.set_design_variant("clean", false)
	view.show_system(preload("res://tests/design_variants_test.gd").fixture(), 3)
	view.preview.set_camera_input_blocked(true)
	for requested in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		DisplayServer.window_set_size(requested)
		for frame in range(8):
			await get_tree().process_frame
		var actual := DisplayServer.window_get_size()
		assert(view.preview_viewport.size == actual, "System render must match physical window pixels: %s != %s" % [view.preview_viewport.size, actual])
		assert(SettingsManager.get_resolution() == actual)
		assert(SettingsManager.get_window_mode() == DisplayServer.window_get_mode())
		assert(view.preview_viewport.msaa_3d == SettingsManager.get_msaa())
		var field := view.preview.get_node("Pivot/Bodies/GravityFieldMap") as GravityFieldMap
		for body in field.body_records:
			var anchor := GravityFieldMap.visual_position(body, field.body_records)
			var pixel := view.preview.camera.unproject_position(view.preview.pivot.to_global(anchor))
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			event.position = pixel * view.preview_container.size / Vector2(view.preview_viewport.size)
			view.handle_view_input(event)
			assert(view.preview.get_selected_selection_id().ends_with(str(body["id"])), "Picking must survive UI scaling")
			view.preview.clear_selection()
		print("PASS: native rendering, settings, MSAA and input mapping at ", actual)
	view.queue_free()
	await get_tree().process_frame
	var menu: Control = load("res://scene/MainMenue/MainUI.tscn").instantiate()
	add_child(menu)
	for mode in [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_FULLSCREEN]:
		# Apply transient preferences without writing the user's settings file.
		SettingsManager.set("_window_mode", mode)
		SettingsManager.call("_apply_display_settings")
		for frame in range(8):
			await get_tree().process_frame
		menu.get("_settings_system").refresh_display_settings()
		var option: OptionButton = menu.settings_resolution_option
		assert(option.disabled == (mode != DisplayServer.WINDOW_MODE_WINDOWED))
		assert(option.get_item_metadata(option.selected) == DisplayServer.window_get_size())
		print("PASS: effective resolution and size control for window mode ", mode)
	SettingsManager.set_design_variant("pastel", false)
	get_tree().quit()
